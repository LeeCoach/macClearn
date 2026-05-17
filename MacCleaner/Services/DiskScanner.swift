// DiskScanner.swift - 磁盘扫描与清理服务，按类别扫描可清理文件并支持选择性清理

import Foundation
import Combine

/// 磁盘扫描器，按类别扫描磁盘文件（缓存、日志、临时文件等），支持清理和取消操作
class DiskScanner: ObservableObject {
    @Published var scanResults: [ScanCategory] = []
    @Published var isScanning: Bool = false
    @Published var scanProgress: Double = 0.0
    @Published var totalCleanableSize: UInt64 = 0
    @Published var isCleaning: Bool = false
    @Published var cleanProgress: Double = 0.0
    @Published var currentScanningPath: String = ""
    @Published var currentScanningCategory: String = ""

    private let fileManager = FileManager.default
    private var isCancelled = false
    private var excludedPaths: [String] = []
    private var lastScanProgressUpdate = Date.distantPast
    private let scanProgressUpdateInterval: TimeInterval = 0.08

    private var home: String {
        NSHomeDirectory()
    }

    /// 各扫描类别对应的文件系统路径
    private var categoryPaths: [ScanCategoryType: [String]] {
        [
            .caches: ["\(home)/Library/Caches", "/Library/Caches"],
            .logs: ["\(home)/Library/Logs", "/Library/Logs"],
            .tempFiles: ["/tmp", "/private/tmp"],
            .trash: ["\(home)/.Trash"],
            .xcodeCache: [
                "\(home)/Library/Developer/Xcode/DerivedData",
                "\(home)/Library/Developer/Xcode/Archives",
                "\(home)/Library/Developer/Xcode/iOS DeviceSupport"
            ],
            .browserCache: [
                "\(home)/Library/Caches/Google/Chrome",
                "\(home)/Library/Caches/com.apple.Safari",
                "\(home)/Library/Caches/Firefox/Profiles"
            ],
            .largeFiles: [home]
        ]
    }

    func cancelOperation() {
        isCancelled = true
    }

    /// 异步扫描磁盘，按类别逐个扫描并更新进度
    func scanDisk(excludedPaths: [String] = []) async {
        isCancelled = false
        self.excludedPaths = excludedPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path }

        await MainActor.run {
            isScanning = true
            scanProgress = 0.0
            scanResults = []
            totalCleanableSize = 0
            currentScanningPath = ""
            currentScanningCategory = ""
        }
        lastScanProgressUpdate = .distantPast

        let types = ScanCategoryType.allCases
        let total = Double(types.count)
        var results: [ScanCategory] = []

        for (index, type) in types.enumerated() {
            if isCancelled {
                let currentResults = results
                await MainActor.run {
                    scanResults = currentResults
                    currentScanningPath = ""
                    currentScanningCategory = ""
                    isScanning = false
                }
                return
            }

            await MainActor.run {
                currentScanningCategory = type.titleKey
                scanProgress = Double(index) / total
            }

            let category = await scanCategory(
                type,
                baseProgress: Double(index) / total,
                categoryWeight: 1.0 / total
            )
            results.append(category)

            let currentResults = results
            let currentTotalCleanableSize = currentResults
                .filter { $0.categoryType.isCleanable }
                .reduce(0) { $0 + $1.totalSize }
            await MainActor.run {
                scanProgress = Double(index + 1) / total
                scanResults = currentResults
                totalCleanableSize = currentTotalCleanableSize
            }
        }

        let finalResults = results
        await MainActor.run {
            scanResults = finalResults
            currentScanningPath = ""
            currentScanningCategory = ""
            isScanning = false
        }
    }

    /// 扫描指定类别的文件，遍历目录并统计大小和文件列表
    private func scanCategory(_ type: ScanCategoryType, baseProgress: Double, categoryWeight: Double) async -> ScanCategory {
        var category = ScanCategory(categoryType: type)
        guard let paths = categoryPaths[type] else { return category }

        // 大文件类别使用独立的扫描逻辑（基于阈值过滤）
        if type == .largeFiles {
            return await scanLargeFiles(in: paths, baseProgress: baseProgress, categoryWeight: categoryWeight)
        }

        var totalSize: UInt64 = 0
        var fileCount = 0
        var scannedItems = 0
        var files: [ScanFileItem] = []

        for path in paths {
            if isCancelled { break }
            if isPathExcluded(path) { continue }

            let url = URL(fileURLWithPath: path)
            guard let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let fileURL as URL in enumerator {
                if isCancelled { break }
                scannedItems += 1
                await updateScanProgress(
                    baseProgress: baseProgress,
                    categoryWeight: categoryWeight,
                    scannedItems: scannedItems,
                    currentPath: fileURL.path
                )
                do {
                    let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                    if resourceValues.isDirectory == true {
                        // 如果目录本身被排除，跳过其所有子项
                        if isPathExcluded(fileURL.path) {
                            enumerator.skipDescendants()
                        }
                        continue
                    }
                    if isPathExcluded(fileURL.path) || isProtectedPath(fileURL.path) { continue }

                    let fileSize = UInt64(resourceValues.fileSize ?? 0)
                    totalSize += fileSize
                    fileCount += 1

                    files.append(ScanFileItem(url: fileURL, size: fileSize, isProtected: false))
                } catch {
                    continue
                }
            }
        }

        category.totalSize = totalSize
        category.fileCount = fileCount
        category.files = files
        return category
    }

    /// 扫描大文件（≥100MB），跳过 Library 和废纸篓等系统目录
    private func scanLargeFiles(in paths: [String], baseProgress: Double, categoryWeight: Double) async -> ScanCategory {
        var category = ScanCategory(categoryType: .largeFiles)
        // 大文件阈值：100MB
        let threshold: UInt64 = 100 * 1024 * 1024

        var files: [ScanFileItem] = []
        var totalSize: UInt64 = 0
        var scannedItems = 0

        // 大文件扫描时跳过这些目录前缀（避免扫描 Library 等系统目录）
        let skipDirectoryPrefixes = [
            "\(home)/Library",
            "\(home)/.Trash"
        ]

        for path in paths {
            if isCancelled { break }
            if isPathExcluded(path) { continue }

            let url = URL(fileURLWithPath: path)
            guard let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let item as URL in enumerator {
                if isCancelled { break }
                scannedItems += 1
                await updateScanProgress(
                    baseProgress: baseProgress,
                    categoryWeight: categoryWeight,
                    scannedItems: scannedItems,
                    currentPath: item.path
                )
                do {
                    let resourceValues = try item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])

                    if resourceValues.isDirectory == true {
                        if isPathExcluded(item.path) ||
                            skipDirectoryPrefixes.contains(where: { item.path.hasPrefix($0) && item.path != home }) {
                            enumerator.skipDescendants()
                        }
                        continue
                    }

                    if isPathExcluded(item.path) || isProtectedPath(item.path) { continue }

                    let fileSize = UInt64(resourceValues.fileSize ?? 0)
                    if fileSize >= threshold {
                        files.append(ScanFileItem(url: item, size: fileSize, isProtected: false))
                        totalSize += fileSize
                    }
                } catch {
                    continue
                }
            }
        }

        files.sort { $0.size > $1.size }

        category.totalSize = totalSize
        category.fileCount = files.count
        category.files = files
        return category
    }

    /// 在单个扫描分类内部提供平滑进度。目录总文件数未知，因此使用渐进估算并在分类结束时由调用方校准到精确进度。
    private func updateScanProgress(
        baseProgress: Double,
        categoryWeight: Double,
        scannedItems: Int,
        currentPath: String
    ) async {
        let now = Date()
        guard now.timeIntervalSince(lastScanProgressUpdate) >= scanProgressUpdateInterval else { return }
        lastScanProgressUpdate = now

        let itemProgress = min(0.92, Double(scannedItems) / Double(scannedItems + 600))
        let progress = min(baseProgress + categoryWeight * itemProgress, baseProgress + categoryWeight * 0.92)

        await MainActor.run {
            currentScanningPath = currentPath
            scanProgress = max(scanProgress, progress)
        }
    }

    /// 判断路径是否属于受保护的系统目录（用户主目录外的 /Library、/System、/private/var）
    private func isProtectedPath(_ path: String) -> Bool {
        if path.hasPrefix(home) {
            return false
        }
        let systemPrefixes = ["/Library", "/System", "/private/var"]
        return systemPrefixes.contains { path.hasPrefix($0) }
    }

    /// 判断路径是否在用户排除列表中（精确匹配或前缀匹配）
    private func isPathExcluded(_ path: String) -> Bool {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        return excludedPaths.contains { excludedPath in
            normalizedPath == excludedPath || normalizedPath.hasPrefix(excludedPath + "/")
        }
    }

    /// 清理选中的类别文件，废纸篓中的文件直接删除，其余移入废纸篓
    func cleanCategories(_ selected: Set<ScanCategoryType>, excludedPaths: [String] = []) async -> UInt64 {
        isCancelled = false
        self.excludedPaths = excludedPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        var cleanedSize: UInt64 = 0
        var cleanedURLs: Set<URL> = []

        let categoriesToClean = scanResults.filter { selected.contains($0.categoryType) && $0.categoryType.isCleanable }
        let totalFiles = categoriesToClean.reduce(0) { total, category in
            total + category.files.filter { !$0.isProtected && !isPathExcluded($0.url.path) }.count
        }
        var processedFiles = 0

        await MainActor.run {
            isCleaning = true
            cleanProgress = 0.0
        }

        for category in categoriesToClean {
            if isCancelled { break }

            for file in category.files {
                if isCancelled { break }
                if file.isProtected || isPathExcluded(file.url.path) { continue }
                do {
                    if category.categoryType == .trash {
                        // 废纸篓中的文件直接彻底删除
                        try fileManager.removeItem(at: file.url)
                    } else {
                        // 其他类别的文件移入废纸篓
                        var resultURL: NSURL?
                        try fileManager.trashItem(at: file.url, resultingItemURL: &resultURL)
                    }
                    cleanedSize += file.size
                    cleanedURLs.insert(file.url)
                } catch {
                    continue
                }
                processedFiles += 1
                await MainActor.run {
                    cleanProgress = totalFiles > 0 ? Double(processedFiles) / Double(totalFiles) : 0
                }
            }
        }

        await MainActor.run {
            isCleaning = false
            cleanProgress = 0.0
            // 清理完成后更新扫描结果，移除已清理的文件
            scanResults = scanResults.map { category in
                var updated = category
                if selected.contains(updated.categoryType) && updated.categoryType.isCleanable && !isCancelled {
                    updated.files.removeAll { cleanedURLs.contains($0.url) }
                    updated.fileCount = updated.files.count
                    updated.totalSize = updated.files.reduce(0) { $0 + $1.size }
                }
                return updated
            }
            totalCleanableSize = scanResults
                .filter { $0.categoryType.isCleanable }
                .reduce(0) { $0 + $1.totalSize }
        }

        return cleanedSize
    }

    /// 获取当前磁盘可用空间
    func getFreeDiskSpace() -> UInt64 {
        do {
            let attributes = try fileManager.attributesOfFileSystem(forPath: "/")
            return attributes[.systemFreeSize] as? UInt64 ?? 0
        } catch {
            return 0
        }
    }
}

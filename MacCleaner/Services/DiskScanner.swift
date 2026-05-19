// DiskScanner.swift - 磁盘扫描与清理服务，按类别并发扫描可清理文件并支持选择性清理

import Foundation
import Combine

/// 磁盘扫描器，按类别并发扫描磁盘文件（缓存、日志、临时文件等），支持清理和取消操作
class DiskScanner: ObservableObject {
    @Published var scanResults: [ScanCategory] = []
    @Published var isScanning: Bool = false
    @Published var scanProgress: Double = 0.0
    @Published var totalCleanableSize: UInt64 = 0
    @Published var isCleaning: Bool = false
    @Published var cleanProgress: Double = 0.0
    @Published var hasCompletedScan: Bool = false
    @Published var activeScanCount: Int = 0
    @Published var scannedFileCount: Int = 0
    @Published var activeCategoryTypes: Set<ScanCategoryType> = []
    @Published var lastScanDate: Date?

    private let fileManager = FileManager.default
    private var isCancelled = false
    private var isScanCancelled = false
    private var isCleanCancelled = false
    private var excludedPaths: [String] = []
    private var cleanedFileURLs: Set<URL> = []

    private var home: String {
        NSHomeDirectory()
    }

    private var persistenceURL: URL {
        let dir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("MacCleaner_scanResults.json")
    }

    init() {
        loadPersistedResults()
    }

    /// 各扫描类别对应的文件系统路径
    private var categoryPaths: [ScanCategoryType: [String]] {
        [
            .caches: ["\(home)/Library/Caches", "/Library/Caches"],
            .logs: ["\(home)/Library/Logs", "/Library/Logs"],
            .tempFiles: ["/tmp", "/private/tmp"],
            .trash: ["\(home)/.Trash"],
            .downloads: ["\(home)/Downloads"],
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
        isScanCancelled = true
        isCleanCancelled = true
    }

    func cancelScan() {
        isScanCancelled = true
    }

    func cancelClean() {
        isCleanCancelled = true
    }

    private func saveScanResults() {
        do {
            let data = try JSONEncoder().encode(scanResults)
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            print("Failed to save scan results: \(error)")
        }
    }

    private func loadPersistedResults() {
        guard let data = try? Data(contentsOf: persistenceURL),
              let results = try? JSONDecoder().decode([ScanCategory].self, from: data) else { return }
        let types = ScanCategoryType.allCases
        var loaded = results
        loaded.sort {
            guard let a = types.firstIndex(of: $0.categoryType),
                  let b = types.firstIndex(of: $1.categoryType) else { return false }
            return a < b
        }
        scanResults = loaded
        totalCleanableSize = loaded
            .filter { $0.categoryType.isCleanable }
            .reduce(0) { $0 + $1.totalSize }
        hasCompletedScan = true
        lastScanDate = loaded.compactMap(\.scannedAt).max()
    }

    /// 并发扫描磁盘，所有分类同时启动，实时反馈文件计数和中间结果
    func scanDisk(excludedPaths: [String] = []) async {
        isCancelled = false
        isScanCancelled = false
        self.excludedPaths = excludedPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path }

        await MainActor.run {
            isScanning = true
            scanProgress = 0.0
            scanResults = []
            totalCleanableSize = 0
            hasCompletedScan = false
            lastScanDate = nil
            activeScanCount = 0
            scannedFileCount = 0
            activeCategoryTypes = []
            cleanedFileURLs = []
        }

        let types = ScanCategoryType.allCases

        await withTaskGroup(of: ScanCategory.self) { group in
            for type in types {
                group.addTask { [weak self] in
                    guard let self else { return ScanCategory(categoryType: type) }
                    if self.isScanCancelled { return ScanCategory(categoryType: type) }

                    await MainActor.run {
                        self.activeScanCount += 1
                        self.activeCategoryTypes.insert(type)
                    }

                    let category: ScanCategory
                    if type == .largeFiles {
                        category = await self.scanLargeFiles(type)
                    } else {
                        category = await self.scanCategory(type)
                    }

                    await MainActor.run {
                        self.activeScanCount = max(0, self.activeScanCount - 1)
                        self.activeCategoryTypes.remove(type)
                    }

                    return category
                }
            }

            for await category in group {
                if isScanCancelled {
                    group.cancelAll()
                }

                await MainActor.run {
                    let filteredFiles = category.files.filter { !cleanedFileURLs.contains($0.url) }
                    let filteredTotalSize = filteredFiles.reduce(UInt64(0)) { $0 + $1.size }
                    let finalCategory = ScanCategory(
                        categoryType: category.categoryType,
                        totalSize: filteredTotalSize,
                        fileCount: filteredFiles.count,
                        files: filteredFiles
                    )
                    if let index = scanResults.firstIndex(where: { $0.categoryType == finalCategory.categoryType }) {
                        scanResults[index] = finalCategory
                    } else {
                        scanResults.append(finalCategory)
                    }
                    scanResults.sort {
                        guard let a = types.firstIndex(of: $0.categoryType),
                              let b = types.firstIndex(of: $1.categoryType) else { return false }
                        return a < b
                    }
                    totalCleanableSize = scanResults
                        .filter { $0.categoryType.isCleanable }
                        .reduce(0) { $0 + $1.totalSize }
                }
            }
        }

        await MainActor.run {
            let completedAt = Date()
            scanResults = scanResults.map { category in
                var updated = category
                updated.scannedAt = completedAt
                return updated
            }
            isScanning = false
            scanProgress = 1.0
            hasCompletedScan = true
            lastScanDate = completedAt
            activeScanCount = 0
        }
        saveScanResults()
    }

    private static let batchFileThreshold = 50
    private static let batchTimeThreshold: TimeInterval = 0.3

    /// 扫描指定类别的文件，每 50 个或每 0.3 秒推送中间结果到 UI
    private func scanCategory(_ type: ScanCategoryType) async -> ScanCategory {
        var category = ScanCategory(categoryType: type)
        guard let paths = categoryPaths[type] else { return category }

        var totalSize: UInt64 = 0
        var fileCount = 0
        var files: [ScanFileItem] = []
        var lastBatchCount = 0
        var lastBatchTime = Date.distantPast

        for path in paths {
            if isScanCancelled { break }
            if isPathExcluded(path) { continue }

            let url = URL(fileURLWithPath: path)
            guard let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let fileURL as URL in enumerator {
                if isScanCancelled { break }

                do {
                    let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                    if resourceValues.isDirectory == true {
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

                    let newFiles = fileCount - lastBatchCount
                    let now = Date()
                    if newFiles >= Self.batchFileThreshold || now.timeIntervalSince(lastBatchTime) >= Self.batchTimeThreshold {
                        lastBatchCount = fileCount
                        lastBatchTime = now
                        let snapshot = ScanCategory(categoryType: type, totalSize: totalSize, fileCount: fileCount, files: files)
                        await MainActor.run {
                            self.scannedFileCount += newFiles
                            self.publishIntermediate(snapshot)
                        }
                    }
                } catch {
                    continue
                }
            }
        }

        let remaining = fileCount - lastBatchCount
        if remaining > 0 {
            await MainActor.run {
                self.scannedFileCount += remaining
            }
        }

        category.totalSize = totalSize
        category.fileCount = fileCount
        category.files = files
        return category
    }

    /// 扫描大文件（≥100MB），每 50 个或每 0.3 秒推送中间结果到 UI
    private func scanLargeFiles(_ type: ScanCategoryType) async -> ScanCategory {
        var category = ScanCategory(categoryType: type)
        guard let paths = categoryPaths[type] else { return category }

        let threshold: UInt64 = 100 * 1024 * 1024

        var files: [ScanFileItem] = []
        var totalSize: UInt64 = 0
        var scannedCount = 0
        var lastBatchCount = 0
        var lastBatchTime = Date.distantPast

        let skipDirectoryPrefixes = [
            "\(home)/Library",
            "\(home)/.Trash"
        ]

        for path in paths {
            if isScanCancelled { break }
            if isPathExcluded(path) { continue }

            let url = URL(fileURLWithPath: path)
            guard let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let item as URL in enumerator {
                if isScanCancelled { break }

                do {
                    let resourceValues = try item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])

                    if resourceValues.isDirectory == true {
                        if isPathExcluded(item.path) ||
                            skipDirectoryPrefixes.contains(where: { item.path.hasPrefix($0) && item.path != home }) {
                            enumerator.skipDescendants()
                        }
                        continue
                    }

                    scannedCount += 1

                    let newFilesCount = scannedCount - lastBatchCount
                    let now = Date()
                    if newFilesCount >= Self.batchFileThreshold || now.timeIntervalSince(lastBatchTime) >= Self.batchTimeThreshold {
                        lastBatchCount = scannedCount
                        lastBatchTime = now
                        let snapshot = ScanCategory(categoryType: type, totalSize: totalSize, fileCount: files.count, files: files)
                        await MainActor.run {
                            self.scannedFileCount += newFilesCount
                            self.publishIntermediate(snapshot)
                        }
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

        let remaining = scannedCount - lastBatchCount
        if remaining > 0 {
            await MainActor.run {
                self.scannedFileCount += remaining
            }
        }

        files.sort { $0.size > $1.size }

        category.totalSize = totalSize
        category.fileCount = files.count
        category.files = files
        return category
    }

    /// 将扫描中间结果发布到 scanResults 列表，过滤掉并发清理中已删除的文件
    private func publishIntermediate(_ category: ScanCategory) {
        let filteredFiles = category.files.filter { !cleanedFileURLs.contains($0.url) }
        let filteredTotalSize = filteredFiles.reduce(UInt64(0)) { $0 + $1.size }
        var filtered = category
        filtered.files = filteredFiles
        filtered.fileCount = filteredFiles.count
        filtered.totalSize = filteredTotalSize

        if let index = scanResults.firstIndex(where: { $0.categoryType == category.categoryType }) {
            scanResults[index] = filtered
        } else {
            scanResults.append(filtered)
        }
        let types = ScanCategoryType.allCases
        scanResults.sort {
            guard let a = types.firstIndex(of: $0.categoryType),
                  let b = types.firstIndex(of: $1.categoryType) else { return false }
            return a < b
        }
        totalCleanableSize = scanResults
            .filter { $0.categoryType.isCleanable }
            .reduce(0) { $0 + $1.totalSize }
    }

    /// 判断路径是否属于受保护的系统目录
    private func isProtectedPath(_ path: String) -> Bool {
        if path.hasPrefix(home) {
            return false
        }
        let systemPrefixes = ["/Library", "/System", "/private/var"]
        return systemPrefixes.contains { path.hasPrefix($0) }
    }

    /// 判断路径是否在用户排除列表中
    private func isPathExcluded(_ path: String) -> Bool {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        return excludedPaths.contains { excludedPath in
            normalizedPath == excludedPath || normalizedPath.hasPrefix(excludedPath + "/")
        }
    }

    /// 并行清理选中的类别文件和单独文件
    func cleanCategories(_ selected: Set<ScanCategoryType>, selectedFiles: Set<URL> = [], excludedPaths: [String] = []) async -> UInt64 {
        isCancelled = false
        isCleanCancelled = false
        self.excludedPaths = excludedPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path }

        let categoriesToClean = scanResults.filter { selected.contains($0.categoryType) && $0.categoryType.isCleanable }
        let categoryFileURLs = Set(categoriesToClean.flatMap { $0.files.map { $0.url } })

        var tasks: [(url: URL, size: UInt64, isTrash: Bool)] = []

        for category in categoriesToClean {
            for file in category.files {
                if file.isProtected || isPathExcluded(file.url.path) { continue }
                tasks.append((file.url, file.size, category.categoryType == .trash))
            }
        }

        for url in selectedFiles.subtracting(categoryFileURLs) {
            if isPathExcluded(url.path) || isProtectedPath(url.path) { continue }
            let parentCategory = scanResults.first { $0.files.contains { $0.url == url } }
            let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey])
            let size = UInt64(resourceValues?.fileSize ?? 0)
            tasks.append((url, size, parentCategory?.categoryType == .trash))
        }

        let totalFiles = tasks.count

        await MainActor.run {
            isCleaning = true
            cleanProgress = 0.0
        }

        let maxConcurrentCleanTasks = 12
        let cleaned = await withTaskGroup(of: (UInt64, URL).self) { group in
            var iterator = tasks.makeIterator()
            var submitted = 0

            func submitNext() {
                guard !isCleanCancelled, let task = iterator.next() else { return }
                submitted += 1
                group.addTask { [weak self] in
                    if self?.isCleanCancelled == true {
                        return (0, task.url)
                    }
                    do {
                        if task.isTrash {
                            try FileManager.default.removeItem(at: task.url)
                        } else {
                            var resultURL: NSURL?
                            try FileManager.default.trashItem(at: task.url, resultingItemURL: &resultURL)
                        }
                        return (task.size, task.url)
                    } catch {
                        return (0, task.url)
                    }
                }
            }

            for _ in 0..<min(maxConcurrentCleanTasks, totalFiles) {
                submitNext()
            }

            var cleanedSize: UInt64 = 0
            var cleanedURLs: Set<URL> = []
            var count = 0
            for await (size, url) in group {
                if size > 0 {
                    cleanedSize += size
                    cleanedURLs.insert(url)
                }
                count += 1
                let c = count
                let t = totalFiles
                await MainActor.run {
                    cleanProgress = t > 0 ? Double(c) / Double(t) : 0
                }
                if isCleanCancelled {
                    group.cancelAll()
                } else if submitted < totalFiles {
                    submitNext()
                }
            }
            return (cleanedSize, cleanedURLs)
        }

        let (cleanedSize, cleanedURLs) = cleaned

        let urls = cleanedURLs
        await MainActor.run {
            isCleaning = false
            cleanProgress = 0.0
            cleanedFileURLs.formUnion(urls)
            scanResults = scanResults.map { category in
                var updated = category
                if !isCleanCancelled {
                    updated.files.removeAll { urls.contains($0.url) }
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

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

    /// 专用 I/O 队列，清理操作的阻塞 FileManager 调用在此执行，避免占用 Swift 协程线程
    private let cleanIOQueue = DispatchQueue(label: "com.maccleaner.clean.io", qos: .userInitiated, attributes: .concurrent)

    private var home: String {
        NSHomeDirectory()
    }

    private var persistenceURL: URL {
        let dir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("MacCleaner_scanResults.json")
    }

    init() {
        // 不加载持久化的扫描结果，每次启动或进入磁盘页时重新扫描获取最新数据
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
            AppLogger.error(error, context: "Failed to save scan results", log: .disk)
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
                    // 保留已存在的截断标记（如果一个子路径触发了截断，后续路径也应视为截断）
                    var merged = category
                    if let existing = scanResults.first(where: { $0.categoryType == category.categoryType }), existing.isTruncated {
                        merged.isTruncated = true
                    }
                    if let index = scanResults.firstIndex(where: { $0.categoryType == merged.categoryType }) {
                        scanResults[index] = merged
                    } else {
                        scanResults.append(merged)
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

    /// 重新扫描指定分类（用于截断分类清理后获取最新数据）
    func rescanCategories(_ types: Set<ScanCategoryType>, excludedPaths: [String] = []) async {
        isScanCancelled = false
        self.excludedPaths = excludedPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path }

        await MainActor.run {
            scannedFileCount = 0
        }

        await withTaskGroup(of: ScanCategory.self) { group in
            for type in types {
                group.addTask { [weak self] in
                    guard let self else { return ScanCategory(categoryType: type) }
                    if self.isScanCancelled { return ScanCategory(categoryType: type) }

                    let category: ScanCategory
                    if type == .largeFiles {
                        category = await self.scanLargeFiles(type)
                    } else {
                        category = await self.scanCategory(type)
                    }
                    return category
                }
            }

            for await category in group {
                if isScanCancelled { group.cancelAll() }

                await MainActor.run {
                    // 合并已清理的文件过滤
                    let filteredFiles = category.files.filter { !cleanedFileURLs.contains($0.url) }
                    let filteredTotalSize = filteredFiles.reduce(UInt64(0)) { $0 + $1.size }
                    let finalCategory = ScanCategory(
                        categoryType: category.categoryType,
                        totalSize: filteredTotalSize,
                        fileCount: filteredFiles.count,
                        files: filteredFiles,
                        scannedAt: Date()
                    )
                    if let index = scanResults.firstIndex(where: { $0.categoryType == finalCategory.categoryType }) {
                        scanResults[index] = finalCategory
                    } else {
                        scanResults.append(finalCategory)
                    }
                    totalCleanableSize = scanResults
                        .filter { $0.categoryType.isCleanable }
                        .reduce(0) { $0 + $1.totalSize }
                }
            }
        }
    }

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
                    if newFiles >= Constants.Scan.batchFileThreshold || now.timeIntervalSince(lastBatchTime) >= Constants.Scan.batchTimeThreshold {
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
                    if newFilesCount >= Constants.Scan.batchFileThreshold || now.timeIntervalSince(lastBatchTime) >= Constants.Scan.batchTimeThreshold {
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
                    if fileSize >= Constants.Scan.largeFileThreshold {
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

    /// 将扫描中间结果发布到 scanResults 列表
    /// 注意：扫描时 cleanedFileURLs 始终为空，故不做过滤以避免 O(n) 遍历
    private func publishIntermediate(_ category: ScanCategory) {
        if let index = scanResults.firstIndex(where: { $0.categoryType == category.categoryType }) {
            scanResults[index] = category
        } else {
            scanResults.append(category)
        }
        // 分类来自 ScanCategoryType.allCases 的有序遍历，顺序已经确定，无需排序
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
    func cleanCategories(
        _ selected: Set<ScanCategoryType>,
        selectedFiles: Set<URL> = [],
        excludedFiles: Set<URL> = [],
        excludedPaths: [String] = [],
        permanentlyDelete: Bool = false
    ) async -> UInt64 {
        // 防止并发清理：如果已有清理任务在进行，直接返回
        if isCleaning {
            AppLogger.info("Clean already in progress, skipping duplicate request", log: .disk)
            return 0
        }
        isCancelled = false
        isCleanCancelled = false
        self.excludedPaths = excludedPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path }

        // 在主线程上直接从 live scanResults 构建任务列表（不拍快照）
        // 这样边扫描边清理时，刚扫完的分类文件也会包含进来
        let built = await MainActor.run { () -> (tasks: [(url: URL, size: UInt64, isTrash: Bool)], index: [URL: (file: ScanFileItem, categoryType: ScanCategoryType)]) in
            isCleaning = true
            cleanProgress = 0.0

            let categoriesToClean = scanResults.filter { selected.contains($0.categoryType) && $0.categoryType.isCleanable }

            var tasks: [(url: URL, size: UInt64, isTrash: Bool)] = []
            var categoryFileURLs: Set<URL> = []
            var fileIndex: [URL: (file: ScanFileItem, categoryType: ScanCategoryType)] = [:]

            for category in scanResults {
                for file in category.files {
                    fileIndex[file.url] = (file, category.categoryType)
                }
            }

            for category in categoriesToClean {
                for file in category.files {
                    categoryFileURLs.insert(file.url)
                    if excludedFiles.contains(file.url) || file.isProtected || isPathExcluded(file.url.path) { continue }
                    tasks.append((file.url, file.size, category.categoryType == .trash))
                }
            }

            // 单独勾选的文件（不在已选分类中）
            for url in selectedFiles.subtracting(categoryFileURLs) {
                if isPathExcluded(url.path) || isProtectedPath(url.path) { continue }
                if let indexed = fileIndex[url] {
                    if indexed.file.isProtected { continue }
                    tasks.append((url, indexed.file.size, indexed.categoryType == .trash))
                } else {
                    let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey])
                    let size = UInt64(resourceValues?.fileSize ?? 0)
                    tasks.append((url, size, false))
                }
            }

            return (tasks, fileIndex)
        }

        let tasks = built.tasks
        let totalFiles = tasks.count

        if totalFiles == 0 {
            await MainActor.run {
                isCleaning = false
                cleanProgress = 0.0
            }
            return 0
        }

        let cleaned: (UInt64, Set<URL>) = await withTaskGroup(of: (UInt64, URL).self) { group in
            // 一次性提交所有清理任务，消除 submitNext 的串行瓶颈
            for task in tasks {
                if isCleanCancelled { break }
                group.addTask { [weak self] in
                    guard let queue = self?.cleanIOQueue else { return (0, task.url) }
                    // 保留弱引用，在 I/O 执行前检查实时取消状态
                    weak var weakSelf = self
                    return await withCheckedContinuation { continuation in
                        queue.async {
                            // 在 I/O 实际执行时检查取消，而非任务创建时
                            if weakSelf?.isCleanCancelled ?? true {
                                continuation.resume(returning: (0, task.url))
                                return
                            }
                            do {
                                if task.isTrash || permanentlyDelete {
                                    try FileManager.default.removeItem(at: task.url)
                                } else {
                                    var resultURL: NSURL?
                                    try FileManager.default.trashItem(at: task.url, resultingItemURL: &resultURL)
                                }
                                continuation.resume(returning: (task.size, task.url))
                            } catch {
                                continuation.resume(returning: (0, task.url))
                            }
                        }
                    }
                }
            }

            var cleanedSize: UInt64 = 0
            var cleanedURLs: Set<URL> = []
            var count = 0
            var lastProgressUpdate = Date.distantPast
            for await (size, url) in group {
                if isCleanCancelled {
                    // 取消后不再记录结果，并终止取剩余结果
                    group.cancelAll()
                    break
                }
                if size > 0 {
                    cleanedSize += size
                    cleanedURLs.insert(url)
                }
                count += 1
                let now = Date()
                if count == totalFiles ||
                   now.timeIntervalSince(lastProgressUpdate) >= Constants.Scan.batchTimeThreshold * 0.167 {
                    lastProgressUpdate = now
                    let c = count
                    let t = totalFiles
                    await MainActor.run {
                        cleanProgress = t > 0 ? Double(c) / Double(t) : 0
                    }
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

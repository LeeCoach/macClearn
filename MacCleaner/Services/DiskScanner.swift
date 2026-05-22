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
                "\(home)/Library/Developer/Xcode/DerivedData"
            ],
            .browserCache: [
                "\(home)/Library/Caches/Google/Chrome",
                "\(home)/Library/Caches/com.apple.Safari",
                "\(home)/Library/Caches/Firefox/Profiles"
            ],
            .largeFiles: [home]
        ]
    }

    private let packageDirectoryExtensions: Set<String> = [
        "app", "appex", "bundle", "framework", "plugin", "prefPane",
        "qlgenerator", "saver", "service", "inputMethod", "ideplugin",
        "wkplugin", "mdimporter", "xcarchive", "xcworkspace",
        "xcodeproj", "playground", "photoslibrary"
    ]

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
        totalCleanableSize = cleanableSize(in: loaded)
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
            scanResults = ScanCategoryType.allCases.map { ScanCategory(categoryType: $0) }
            totalCleanableSize = 0
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
                    } else if type == .trash {
                        category = await self.scanTrashCategory()
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
                    if let index = scanResults.firstIndex(where: { $0.categoryType == category.categoryType }) {
                        scanResults[index] = category
                    } else {
                        scanResults.append(category)
                    }
                    totalCleanableSize = cleanableSize(in: scanResults)
                }
            }
        }

        await MainActor.run {
            let completedAt = Date()
            scanResults = orderedCategories(scanResults).map { category in
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
                    } else if type == .trash {
                        category = await self.scanTrashCategory()
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
                    totalCleanableSize = cleanableSize(in: scanResults)
                }
            }
        }
    }

    private func orderedCategories(_ categories: [ScanCategory]) -> [ScanCategory] {
        var byType = Dictionary(uniqueKeysWithValues: categories.map { ($0.categoryType, $0) })
        return ScanCategoryType.allCases.map { type in
            byType.removeValue(forKey: type) ?? ScanCategory(categoryType: type)
        }
    }

    private func trashRootURLs() -> [URL] {
        [URL(fileURLWithPath: "\(home)/.Trash", isDirectory: true)]
    }

    private func isIgnorableTrashItem(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return name == ".DS_Store" || Self.ignorableEmptyDirectoryItems.contains(name)
    }

    private func countTrashItemsToClean(excluding excludedURLs: Set<URL>) -> Int {
        let excludedPaths = Set(excludedURLs.map { $0.standardizedFileURL.path })
        var count = 0
        for trashRoot in trashRootURLs() {
            if isPathExcluded(trashRoot.path) { continue }
            guard fileManager.fileExists(atPath: trashRoot.path),
                  let items = try? fileManager.contentsOfDirectory(
                      at: trashRoot,
                      includingPropertiesForKeys: nil,
                      options: []
                  ) else { continue }
            for item in items {
                let url = item.standardizedFileURL
                if isIgnorableTrashItem(url) { continue }
                if excludedPaths.contains(url.path) || isPathExcluded(url.path) { continue }
                count += 1
            }
        }
        return count
    }

    private func trashItemSize(at url: URL) -> (size: UInt64, isDirectory: Bool) {
        let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .isPackageKey])
        let isDirectory = resourceValues?.isDirectory == true || resourceValues?.isPackage == true
        if isDirectory {
            return (Self.directorySize(at: url), true)
        }
        return (UInt64(resourceValues?.fileSize ?? 0), false)
    }

    /// 扫描废纸篓顶层项目（与访达废纸篓列表一致），避免深层枚举漏掉 .app 等包
    private func scanTrashCategory() async -> ScanCategory {
        var category = ScanCategory(categoryType: .trash)
        var totalSize: UInt64 = 0
        var itemCount = 0
        var files: [ScanFileItem] = []
        var lastBatchCount = 0
        var lastBatchTime = Date.distantPast

        for trashRoot in trashRootURLs() {
            if isScanCancelled { break }
            if isPathExcluded(trashRoot.path) { continue }
            guard fileManager.fileExists(atPath: trashRoot.path) else { continue }

            guard let items = try? fileManager.contentsOfDirectory(
                at: trashRoot,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .isPackageKey],
                options: []
            ) else { continue }

            for itemURL in items {
                if isScanCancelled { break }

                let url = itemURL.standardizedFileURL
                if isPathExcluded(url.path) || isIgnorableTrashItem(url) { continue }

                let (size, isDirectory) = trashItemSize(at: url)
                totalSize += size
                itemCount += 1
                files.append(ScanFileItem(url: url, size: size, isProtected: false, isDirectory: isDirectory))

                let newItems = itemCount - lastBatchCount
                let now = Date()
                if newItems >= Constants.Scan.batchFileThreshold || now.timeIntervalSince(lastBatchTime) >= Constants.Scan.batchTimeThreshold {
                    lastBatchCount = itemCount
                    lastBatchTime = now
                    let snapshot = ScanCategory(categoryType: .trash, totalSize: totalSize, fileCount: itemCount, files: files)
                    await MainActor.run {
                        self.scannedFileCount += newItems
                        self.publishIntermediate(snapshot)
                    }
                }
            }
        }

        let remaining = itemCount - lastBatchCount
        if remaining > 0 {
            await MainActor.run {
                self.scannedFileCount += remaining
            }
        }

        category.totalSize = totalSize
        category.fileCount = itemCount
        category.files = files
        return category
    }

    /// 清空废纸篓（等同访达「清倒废纸篓」），可排除用户取消勾选的项
    private func emptyTrash(excluding excludedURLs: Set<URL> = []) async -> (UInt64, Set<URL>) {
        let excludedPaths = Set(excludedURLs.map { $0.standardizedFileURL.path })
        var freed: UInt64 = 0
        var removedURLs: Set<URL> = []

        for trashRoot in trashRootURLs() {
            if isCleanCancelled { break }
            if isPathExcluded(trashRoot.path) { continue }
            guard fileManager.fileExists(atPath: trashRoot.path) else { continue }

            guard let items = try? fileManager.contentsOfDirectory(
                at: trashRoot,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .isPackageKey],
                options: []
            ) else { continue }

            for itemURL in items {
                if isCleanCancelled { break }

                let url = itemURL.standardizedFileURL
                if isIgnorableTrashItem(url) { continue }
                if excludedPaths.contains(url.path) || isPathExcluded(url.path) { continue }

                let (size, _) = trashItemSize(at: url)
                let (_, _, _, didClean) = await cleanTask((url, size, .trash), permanentlyDelete: true)
                if didClean {
                    freed += size
                    removedURLs.insert(url)
                }
            }
        }

        return (freed, removedURLs)
    }

    /// 扫描指定类别的可清理项目，每 50 个或每 0.3 秒推送中间结果到 UI
    private func scanCategory(_ type: ScanCategoryType) async -> ScanCategory {
        var category = ScanCategory(categoryType: type)
        guard let paths = categoryPaths[type] else { return category }

        var totalSize: UInt64 = 0
        var itemCount = 0
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
                            continue
                        }
                        if isProtectedPath(fileURL.path) {
                            continue
                        }
                        if type == .trash || isPackageDirectory(fileURL) {
                            let size = Self.directorySize(at: fileURL)
                            totalSize += size
                            itemCount += 1
                            files.append(ScanFileItem(url: fileURL, size: size, isProtected: false, isDirectory: true))
                            enumerator.skipDescendants()
                        } else if isDirectoryEffectivelyEmpty(fileURL) {
                            itemCount += 1
                            files.append(ScanFileItem(url: fileURL, size: 0, isProtected: false, isDirectory: true))
                        }

                        let newItems = itemCount - lastBatchCount
                        let now = Date()
                        if newItems >= Constants.Scan.batchFileThreshold || now.timeIntervalSince(lastBatchTime) >= Constants.Scan.batchTimeThreshold {
                            lastBatchCount = itemCount
                            lastBatchTime = now
                            let snapshot = ScanCategory(categoryType: type, totalSize: totalSize, fileCount: itemCount, files: files)
                            await MainActor.run {
                                self.scannedFileCount += newItems
                                self.publishIntermediate(snapshot)
                            }
                        }
                        continue
                    }
                    if isPathExcluded(fileURL.path) || isProtectedPath(fileURL.path) { continue }

                    let fileSize = UInt64(resourceValues.fileSize ?? 0)
                    totalSize += fileSize
                    itemCount += 1
                    files.append(ScanFileItem(url: fileURL, size: fileSize, isProtected: false))

                    let newFiles = itemCount - lastBatchCount
                    let now = Date()
                    if newFiles >= Constants.Scan.batchFileThreshold || now.timeIntervalSince(lastBatchTime) >= Constants.Scan.batchTimeThreshold {
                        lastBatchCount = itemCount
                        lastBatchTime = now
                        let snapshot = ScanCategory(categoryType: type, totalSize: totalSize, fileCount: itemCount, files: files)
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

        let remaining = itemCount - lastBatchCount
        if remaining > 0 {
            await MainActor.run {
                self.scannedFileCount += remaining
            }
        }

        category.totalSize = totalSize
        category.fileCount = itemCount
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
        totalCleanableSize = cleanableSize(in: scanResults)
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

    private func cleanupBoundaryPaths(for type: ScanCategoryType) -> Set<String> {
        Set((categoryPaths[type] ?? []).map { URL(fileURLWithPath: $0).standardizedFileURL.path })
    }

    private func removeEmptyParentDirectories(for cleanedCategoriesByURL: [URL: ScanCategoryType], permanentlyDelete: Bool) {
        var parentDirsByPath: [String: (url: URL, categoryType: ScanCategoryType)] = [:]
        for (url, categoryType) in cleanedCategoriesByURL {
            let boundaries = cleanupBoundaryPaths(for: categoryType)
            var current = url.deletingLastPathComponent().standardizedFileURL

            while true {
                let currentPath = current.path
                if boundaries.contains(currentPath) || !isWithinCleanupBoundary(currentPath, boundaries: boundaries) {
                    break
                }
                parentDirsByPath[currentPath] = (current, categoryType)

                let parent = current.deletingLastPathComponent().standardizedFileURL
                if parent.path == currentPath {
                    break
                }
                current = parent
            }
        }

        let sortedParents = parentDirsByPath.values.sorted {
            $0.url.pathComponents.count > $1.url.pathComponents.count
        }
        for parent in sortedParents {
            removeEmptyDirectoriesInside(
                parent.url,
                categoryType: parent.categoryType
            )
            removeEmptyDirectoryChain(
                startingAt: parent.url,
                categoryType: parent.categoryType,
                permanentlyDelete: permanentlyDelete
            )
        }
    }

    private func removeEmptyDirectoriesForCategories(_ categoryTypes: Set<ScanCategoryType>) {
        for categoryType in categoryTypes {
            for path in categoryPaths[categoryType] ?? [] {
                let root = URL(fileURLWithPath: path).standardizedFileURL
                removeEmptyDirectoriesInside(root, categoryType: categoryType)
            }
        }
    }

    private func scheduleEmptyDirectoryCleanupAfterScan(
        for cleanedCategoriesByURL: [URL: ScanCategoryType],
        permanentlyDelete: Bool
    ) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            var elapsed: UInt64 = 0
            let maxWait: UInt64 = 30_000_000_000  // 最长等待 30 秒
            while await MainActor.run(body: { self.isScanning }) {
                if self.isCleanCancelled {
                    return
                }
                if elapsed >= maxWait {
                    AppLogger.info("scheduleEmptyDirCleanup: timeout waiting for scan to finish", log: .disk)
                    return
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
                elapsed += 200_000_000
            }
            if !self.isCleanCancelled {
                self.removeEmptyParentDirectories(
                    for: cleanedCategoriesByURL,
                    permanentlyDelete: permanentlyDelete
                )
                self.removeEmptyDirectoriesForCategories(Set(cleanedCategoriesByURL.values))
            }
        }
    }

    private func removeEmptyDirectoryChain(startingAt directory: URL, categoryType: ScanCategoryType, permanentlyDelete: Bool) {
        let boundaries = cleanupBoundaryPaths(for: categoryType)
        var current = directory.standardizedFileURL

        while !isCleanCancelled {
            let currentPath = current.path
            if boundaries.contains(currentPath) || !isWithinCleanupBoundary(currentPath, boundaries: boundaries) {
                break
            }
            if isPathExcluded(currentPath) || isProtectedPath(currentPath) {
                break
            }
            guard isDirectoryEffectivelyEmpty(current) else {
                break
            }

            do {
                try fileManager.removeItem(at: current)
            } catch {
                break
            }

            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == currentPath {
                break
            }
            current = parent
        }
    }

    private func removeEmptyDirectoriesInside(_ directory: URL, categoryType: ScanCategoryType) {
        let boundaries = cleanupBoundaryPaths(for: categoryType)
        let root = directory.standardizedFileURL
        let rootPath = root.path
        let isBoundaryRoot = boundaries.contains(rootPath)
        guard (isBoundaryRoot || isWithinCleanupBoundary(rootPath, boundaries: boundaries)),
              !isPathExcluded(rootPath),
              !isProtectedPath(rootPath) else {
            return
        }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return
        }

        var directories: [URL] = []
        for case let item as URL in enumerator {
            let itemURL = item.standardizedFileURL
            let itemPath = itemURL.path
            if isPathExcluded(itemPath) || isProtectedPath(itemPath) {
                enumerator.skipDescendants()
                continue
            }
            guard (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }
            directories.append(itemURL)
        }

        for directory in directories.sorted(by: { $0.pathComponents.count > $1.pathComponents.count }) {
            guard !isCleanCancelled else { return }
            let path = directory.path
            guard !boundaries.contains(path),
                  isWithinCleanupBoundary(path, boundaries: boundaries),
                  isDirectoryEffectivelyEmpty(directory) else {
                continue
            }
            try? fileManager.removeItem(at: directory)
        }
    }

    private func isWithinCleanupBoundary(_ path: String, boundaries: Set<String>) -> Bool {
        boundaries.contains { boundary in
            path.hasPrefix(boundary + "/")
        }
    }

    private func isDirectoryEffectivelyEmpty(_ directory: URL) -> Bool {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: []
        ) else {
            return false
        }

        for item in contents {
            guard isHiddenOrIgnorableDirectoryItem(item) else {
                return false
            }
        }
        return true
    }

    private func isHiddenOrIgnorableDirectoryItem(_ item: URL) -> Bool {
        let name = item.lastPathComponent
        if name.hasPrefix(".") || Self.ignorableEmptyDirectoryItems.contains(name) {
            return true
        }
        return (try? item.resourceValues(forKeys: [.isHiddenKey]).isHidden) == true
    }

    private static let ignorableEmptyDirectoryItems: Set<String> = [
        "Icon\r"
    ]

    private func isPackageDirectory(_ url: URL) -> Bool {
        packageDirectoryExtensions.contains(url.pathExtension)
    }

    private static func directorySize(at url: URL) -> UInt64 {
        let fileManager = FileManager.default
        var totalSize: UInt64 = 0

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return 0
        }

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                  resourceValues.isDirectory != true,
                  let fileSize = resourceValues.fileSize else {
                continue
            }
            totalSize += UInt64(fileSize)
        }

        return totalSize
    }

    private func cleanableSize(in categories: [ScanCategory]) -> UInt64 {
        categories
            .filter { $0.categoryType.isCleanable }
            .reduce(0) { $0 + $1.totalSize }
    }

    private func cleanTask(
        _ task: (url: URL, size: UInt64, categoryType: ScanCategoryType),
        permanentlyDelete: Bool
    ) async -> (UInt64, URL, ScanCategoryType, Bool) {
        await withCheckedContinuation { continuation in
            cleanIOQueue.async { [weak self] in
                guard let self, !self.isCleanCancelled else {
                    continuation.resume(returning: (0, task.url, task.categoryType, false))
                    return
                }
                do {
                    let isDirectory = (try? task.url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    if isDirectory || task.categoryType == .trash || permanentlyDelete {
                        try FileManager.default.removeItem(at: task.url)
                    } else {
                        var resultURL: NSURL?
                        try FileManager.default.trashItem(at: task.url, resultingItemURL: &resultURL)
                    }
                    continuation.resume(returning: (task.size, task.url, task.categoryType, true))
                } catch {
                    // 文件已不存在（可能扫描后手动删除了），视为清理成功
                    if !FileManager.default.fileExists(atPath: task.url.path) {
                        continuation.resume(returning: (task.size, task.url, task.categoryType, true))
                        return
                    }
                    // trashItem 失败且不可回退时，跳过该文件
                    if task.categoryType == .trash || permanentlyDelete {
                        continuation.resume(returning: (0, task.url, task.categoryType, false))
                        return
                    }
                    // trashItem 失败时回退到直接删除
                    do {
                        try FileManager.default.removeItem(at: task.url)
                        AppLogger.info("cleanTask: trashItem failed, fallback to removeItem: \(task.url.lastPathComponent)", log: .disk)
                        continuation.resume(returning: (task.size, task.url, task.categoryType, true))
                    } catch {
                        continuation.resume(returning: (0, task.url, task.categoryType, false))
                    }
                }
            }
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
        let scanResultsSnapshot = await MainActor.run { () -> [ScanCategory]? in
            // 防止并发清理：如果已有清理任务在进行，直接返回
            if isCleaning {
                return nil
            }
            isCleaning = true
            cleanProgress = 0.0
            return scanResults
        }
        guard let scanResultsSnapshot else {
            AppLogger.info("Clean already in progress, skipping duplicate request", log: .disk)
            return 0
        }
        isCancelled = false
        isCleanCancelled = false
        let normalizedExcludedPaths = excludedPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        self.excludedPaths = normalizedExcludedPaths

        let isExcluded: (String) -> Bool = { path in
            let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
            return normalizedExcludedPaths.contains { excludedPath in
                normalizedPath == excludedPath || normalizedPath.hasPrefix(excludedPath + "/")
            }
        }

        let isProtected: (String) -> Bool = { [home] path in
            if path.hasPrefix(home) {
                return false
            }
            let systemPrefixes = ["/Library", "/System", "/private/var"]
            return systemPrefixes.contains { path.hasPrefix($0) }
        }

        // 大量文件时任务构建本身会很重，必须在后台完成，避免阻塞确认弹窗关闭和进度条绘制。
        let cleansTrashCategory = selected.contains(.trash)
        let categoriesToClean = scanResultsSnapshot.filter {
            selected.contains($0.categoryType) && $0.categoryType.isCleanable && $0.categoryType != .trash
        }

        var trashExcludedURLs: Set<URL> = []
        if cleansTrashCategory,
           let trashCategory = scanResultsSnapshot.first(where: { $0.categoryType == .trash }) {
            for file in trashCategory.files where excludedFiles.contains(file.url) {
                trashExcludedURLs.insert(file.url.standardizedFileURL)
            }
        }

        var tasks: [(url: URL, size: UInt64, categoryType: ScanCategoryType)] = []
        var categoryFileURLs = selectedFiles.isEmpty ? nil : Set<URL>()
        var fileIndex: [URL: (file: ScanFileItem, categoryType: ScanCategoryType)] = [:]

        if !selectedFiles.isEmpty {
            for category in scanResultsSnapshot {
                for file in category.files {
                    fileIndex[file.url.standardizedFileURL] = (file, category.categoryType)
                }
            }
        }

        for category in categoriesToClean {
            for file in category.files {
                categoryFileURLs?.insert(file.url)
                if excludedFiles.contains(file.url) || file.isProtected || isExcluded(file.url.path) { continue }
                tasks.append((file.url, file.size, category.categoryType))
            }
        }

        // 单独勾选的文件（不在已选分类中）；废纸篓分类整类清理走 emptyTrash，此处只处理单独勾选
        let trashRootPaths = Set(trashRootURLs().map { $0.standardizedFileURL.path })
        for url in selectedFiles.subtracting(categoryFileURLs ?? []) {
            let normalizedURL = url.standardizedFileURL
            if isExcluded(normalizedURL.path) || isProtected(normalizedURL.path) { continue }
            if cleansTrashCategory, trashRootPaths.contains(where: { normalizedURL.path.hasPrefix($0 + "/") || normalizedURL.deletingLastPathComponent().path == $0 }) {
                continue
            }
            if let indexed = fileIndex[normalizedURL] {
                if indexed.file.isProtected { continue }
                tasks.append((normalizedURL, indexed.file.size, indexed.categoryType))
            } else {
                let resourceValues = try? normalizedURL.resourceValues(forKeys: [.fileSizeKey])
                let size = UInt64(resourceValues?.fileSize ?? 0)
                let categoryType: ScanCategoryType = trashRootPaths.contains(where: { normalizedURL.path.hasPrefix($0 + "/") })
                    ? .trash
                    : .largeFiles
                tasks.append((normalizedURL, size, categoryType))
            }
        }

        let trashItemCount = cleansTrashCategory
            ? countTrashItemsToClean(excluding: trashExcludedURLs)
            : 0

        let totalFiles = tasks.count + trashItemCount

        if totalFiles == 0 {
            await MainActor.run {
                isCleaning = false
                cleanProgress = 0.0
            }
            return 0
        }

        let taskCount = tasks.count
        var cleanedSize: UInt64 = 0
        var cleanedURLs: Set<URL> = []
        var cleanedCategoriesByURL: [URL: ScanCategoryType] = [:]
        var completedCount = 0

        if taskCount > 0 {
            let cleaned: (UInt64, Set<URL>, [URL: ScanCategoryType]) = await withTaskGroup(of: (UInt64, URL, ScanCategoryType, Bool).self) { group in
                var iterator = tasks.makeIterator()
                var submitted = 0

                func submitNext() {
                    guard !isCleanCancelled, let task = iterator.next() else { return }
                    submitted += 1
                    group.addTask { [weak self] in
                        await self?.cleanTask(task, permanentlyDelete: permanentlyDelete) ?? (0, task.url, task.categoryType, false)
                    }
                }

                for _ in 0..<min(Constants.Scan.maxConcurrentCleanTasks, taskCount) {
                    submitNext()
                }

                var groupCleanedSize: UInt64 = 0
                var groupCleanedURLs: Set<URL> = []
                var groupCleanedCategoriesByURL: [URL: ScanCategoryType] = [:]
                var count = 0
                var lastProgressUpdate = Date.distantPast
                for await (size, url, categoryType, didClean) in group {
                    if isCleanCancelled {
                        group.cancelAll()
                        break
                    }
                    if didClean {
                        groupCleanedSize += size
                        groupCleanedURLs.insert(url)
                        groupCleanedCategoriesByURL[url] = categoryType
                    }
                    count += 1
                    let now = Date()
                    if count == taskCount || now.timeIntervalSince(lastProgressUpdate) >= 0.1 {
                        lastProgressUpdate = now
                        let progressCount = count
                        await MainActor.run {
                            cleanProgress = totalFiles > 0 ? Double(progressCount) / Double(totalFiles) : 0
                        }
                    }
                    if submitted < taskCount {
                        submitNext()
                    }
                }
                return (groupCleanedSize, groupCleanedURLs, groupCleanedCategoriesByURL)
            }

            cleanedSize += cleaned.0
            cleanedURLs.formUnion(cleaned.1)
            for (url, type) in cleaned.2 {
                cleanedCategoriesByURL[url] = type
            }
            completedCount += taskCount
        }

        if cleansTrashCategory && !isCleanCancelled {
            let (trashFreed, trashRemoved) = await emptyTrash(excluding: trashExcludedURLs)
            cleanedSize += trashFreed
            cleanedURLs.formUnion(trashRemoved)
            for url in trashRemoved {
                cleanedCategoriesByURL[url] = .trash
            }
            completedCount += trashRemoved.count
            await MainActor.run {
                cleanProgress = totalFiles > 0 ? Double(completedCount) / Double(totalFiles) : 1.0
            }
        }
        if !isCleanCancelled && !cleanedCategoriesByURL.isEmpty {
            let activeTypes = await MainActor.run { activeCategoryTypes }
            let immediateCleanup = cleanedCategoriesByURL.filter { !activeTypes.contains($0.value) }
            let deferredCleanup = cleanedCategoriesByURL.filter { activeTypes.contains($0.value) }

            if !immediateCleanup.isEmpty {
                removeEmptyParentDirectories(for: immediateCleanup, permanentlyDelete: permanentlyDelete)
            }
            if !deferredCleanup.isEmpty {
                scheduleEmptyDirectoryCleanupAfterScan(
                    for: deferredCleanup,
                    permanentlyDelete: permanentlyDelete
                )
            }
        }

        let urls = cleanedURLs
        let currentScanResults = await MainActor.run { scanResults }
        let updatedScanResults = currentScanResults.map { category in
            var updated = category
            if !isCleanCancelled {
                if category.categoryType == .trash && cleansTrashCategory {
                    updated.files.removeAll { file in
                        !trashExcludedURLs.contains(file.url.standardizedFileURL)
                    }
                } else {
                    updated.files.removeAll { urls.contains($0.url) }
                }
                updated.fileCount = updated.files.count
                updated.totalSize = updated.files.reduce(0) { $0 + $1.size }
            }
            return updated
        }
        let updatedTotalCleanableSize = cleanableSize(in: updatedScanResults)

        await MainActor.run {
            isCleaning = false
            cleanProgress = 0.0
            cleanedFileURLs.formUnion(urls)
            scanResults = updatedScanResults
            totalCleanableSize = updatedTotalCleanableSize
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

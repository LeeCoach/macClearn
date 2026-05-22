// AppUninstaller.swift - 应用卸载服务，支持扫描已安装应用、查找残留文件及卸载

import AppKit
import Combine
import Foundation

/// 应用卸载器，扫描 /Applications 下的应用、查找残留文件、执行卸载
class AppUninstaller: ObservableObject {
    @Published var installedApps: [InstalledApp] = []
    @Published var filteredApps: [InstalledApp] = []
    @Published var selectedApps: Set<URL> = []
    @Published var isScanning: Bool = false
    @Published var isUninstalling: Bool = false
    @Published var currentUninstallApp: InstalledApp?
    @Published var uninstallProgress: Double = 0.0
    @Published var completedOperationCount: Int = 0
    @Published var totalOperationCount: Int = 0
    @Published var uninstallErrorMessage: String?
    @Published var uninstallSuccessMessage: String?

    @Published var orphanResiduals: [ResidualFile] = []
    @Published var isScanningOrphans: Bool = false
    @Published var selectedOrphanResiduals: Set<URL> = []
    @Published var currentOrphanScanPath: String = ""

    private struct InstalledAppIndex {
        var bundleIDs: Set<String>
        var names: Set<String>
    }

    private struct OrphanScanRule {
        let subpath: String
        let requiresDirectory: Bool?
        let isProtected: Bool
        let allowedExtensions: Set<String>
        let requireBundleIdentifier: Bool
        let stripExtensions: [String]
    }

    private struct TrashTask {
        let url: URL
        let appID: URL?
        let residualID: URL?
        let isApp: Bool
        let appName: String?
    }

    private struct TrashTaskResult {
        let task: TrashTask
        let errorDescription: String?
    }

    private struct PrivilegedTrashError: LocalizedError {
        let message: String

        var errorDescription: String? { message }
    }

    /// 可识别的插件/服务 bundle 扩展名
    private static let pluginExtensions: Set<String> = [
        "plugin", "service", "prefPane", "qlgenerator", "saver",
        "inputMethod", "ideplugin", "wkplugin", "mdimporter", "app"
    ]

    /// 扫描常见 Applications 目录下所有应用及插件/服务
    func scanApplications() {
        guard !isScanning else { return }
        isScanning = true
        installedApps = []
        filteredApps = []
        selectedApps = []

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var apps: [InstalledApp] = []
            var seenURLs: Set<URL> = []

            for appURL in Self.discoverApplicationURLs() {
                let standardizedURL = appURL.standardizedFileURL
                guard !seenURLs.contains(standardizedURL) else { continue }
                seenURLs.insert(standardizedURL)

                if let app = Self.installedApp(at: standardizedURL) {
                    apps.append(app)
                }
            }

            // 扫描插件/服务路径
            for pluginURL in Self.discoverPluginURLs() {
                let standardizedURL = pluginURL.standardizedFileURL
                guard !seenURLs.contains(standardizedURL) else { continue }
                seenURLs.insert(standardizedURL)

                if let plugin = Self.installedApp(at: standardizedURL) {
                    apps.append(plugin)
                }
            }

            apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            DispatchQueue.main.async {
                self?.installedApps = apps
                self?.filteredApps = apps
                self?.isScanning = false
            }
        }
    }

    private static func discoverApplicationURLs() -> [URL] {
        let fm = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
            URL(fileURLWithPath: "/System/Applications")
        ]

        var urls: [URL] = []

        for root in roots {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in enumerator {
                if pluginExtensions.contains(url.pathExtension) {
                    urls.append(url)
                    enumerator.skipDescendants()
                }
            }
        }

        return urls
    }

    /// 扫描插件/服务目录，包括系统级和用户级 Library
    private static func discoverPluginURLs() -> [URL] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        let pluginRoots = [
            URL(fileURLWithPath: "/Library/Internet Plug-Ins"),
            URL(fileURLWithPath: "/Library/PreferencePanes"),
            URL(fileURLWithPath: "/Library/Spotlight"),
            URL(fileURLWithPath: "/Library/QuickLook"),
            URL(fileURLWithPath: "/Library/Screen Savers"),
            URL(fileURLWithPath: "/Library/Input Methods"),
            URL(fileURLWithPath: "/Library/Services"),
            URL(fileURLWithPath: "/Library/Printers"),
            home.appendingPathComponent("Library/Internet Plug-Ins"),
            home.appendingPathComponent("Library/PreferencePanes"),
            home.appendingPathComponent("Library/Spotlight"),
            home.appendingPathComponent("Library/QuickLook"),
            home.appendingPathComponent("Library/Screen Savers"),
            home.appendingPathComponent("Library/Services"),
            home.appendingPathComponent("Library/Input Methods"),
            home.appendingPathComponent("Library/ScriptingAdditions")
        ]

        var urls: [URL] = []

        for root in pluginRoots {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in enumerator {
                if pluginExtensions.contains(url.pathExtension) {
                    urls.append(url)
                    enumerator.skipDescendants()
                }
            }
        }

        return urls
    }

    private static func installedApp(at appURL: URL) -> InstalledApp? {
        let fm = FileManager.default
        let plistPath = appURL.appendingPathComponent("Contents/Info.plist")
        guard let plistData = try? Data(contentsOf: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] else {
            return nil
        }

        let name = plist["CFBundleName"] as? String
            ?? plist["CFBundleDisplayName"] as? String
            ?? appURL.deletingPathExtension().lastPathComponent
        let bundleID = plist["CFBundleIdentifier"] as? String ?? ""
        let version = plist["CFBundleShortVersionString"] as? String
            ?? plist["CFBundleVersion"] as? String
        let size = Self.directorySize(at: appURL)
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 48, height: 48)

        var lastAccessed: Date?
        if let attrs = try? fm.attributesOfItem(atPath: appURL.path) {
            lastAccessed = attrs[.modificationDate] as? Date
        }

        return InstalledApp(
            id: appURL,
            name: name,
            bundleID: bundleID,
            version: version,
            url: appURL,
            size: size,
            icon: icon,
            lastAccessed: lastAccessed
        )
    }

    /// 按名称或 Bundle ID 搜索应用
    func searchApps(_ query: String) {
        if query.isEmpty {
            filteredApps = installedApps
        } else {
            filteredApps = installedApps.filter {
                $0.name.localizedCaseInsensitiveContains(query) ||
                $0.bundleID.localizedCaseInsensitiveContains(query)
            }
        }
    }

    /// 扫描指定应用在 Library 下的残留文件（缓存、偏好设置、容器等）
    func scanResidualFiles(for app: InstalledApp) -> [ResidualFile] {
        let fm = FileManager.default
        let home = FileManager.default.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library")
        var residuals: [ResidualFile] = []

        // 按应用名称和 Bundle ID 在 Library 各子目录中查找残留文件
        let searchPaths: [(String, String)] = [
            ("Application Support", app.name),
            ("Application Support", app.bundleID),
            ("Preferences", "\(app.bundleID).plist"),
            ("Caches", app.bundleID),
            ("Caches", app.name),
            ("Logs", app.name),
            ("LaunchAgents", app.bundleID),
            ("LaunchAgents", app.name),
            ("Containers", app.bundleID),
            ("Group Containers", app.bundleID),
            ("Saved Application State", "\(app.bundleID).savedState"),
            ("HTTPStorages", app.bundleID),
            ("WebKit", app.bundleID)
        ]

        for (subpath, component) in searchPaths {
            let dir = library.appendingPathComponent(subpath)
            let target = dir.appendingPathComponent(component)

            if fm.fileExists(atPath: target.path) {
                let size = Self.directorySize(at: target)
                // Containers 和 Group Containers 可能包含共享数据，标记为受保护
                let isProtected = subpath == "Containers" || subpath == "Group Containers"
                residuals.append(ResidualFile(
                    id: target,
                    url: target,
                    name: "\(subpath)/\(component)",
                    size: size,
                    isProtected: isProtected
                ))
            }
        }

        // 在 LaunchAgents 目录中按前缀匹配查找相关 plist 文件
        let launchAgentsDir = library.appendingPathComponent("LaunchAgents")
        if let contents = try? fm.contentsOfDirectory(at: launchAgentsDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            for fileURL in contents {
                let filename = fileURL.lastPathComponent
                if filename.hasPrefix(app.bundleID) || filename.hasPrefix(app.name) {
                    let size = Self.directorySize(at: fileURL)
                    residuals.append(ResidualFile(
                        id: fileURL,
                        url: fileURL,
                        name: "LaunchAgents/\(filename)",
                        size: size,
                        isProtected: false
                    ))
                }
            }
        }

        // 在 Group Containers 目录中按 Bundle ID 前缀匹配
        let groupContainersDir = library.appendingPathComponent("Group Containers")
        if let contents = try? fm.contentsOfDirectory(at: groupContainersDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            for fileURL in contents {
                let filename = fileURL.lastPathComponent
                if filename.hasPrefix(app.bundleID) {
                    let size = Self.directorySize(at: fileURL)
                    residuals.append(ResidualFile(
                        id: fileURL,
                        url: fileURL,
                        name: "Group Containers/\(filename)",
                        size: size,
                        isProtected: true
                    ))
                }
            }
        }

        // 在 Saved Application State 目录中按 Bundle ID 前缀匹配
        let savedStateDir = library.appendingPathComponent("Saved Application State")
        if let contents = try? fm.contentsOfDirectory(at: savedStateDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            for fileURL in contents {
                let filename = fileURL.lastPathComponent
                if filename.hasPrefix(app.bundleID) {
                    let size = Self.directorySize(at: fileURL)
                    residuals.append(ResidualFile(
                        id: fileURL,
                        url: fileURL,
                        name: "Saved Application State/\(filename)",
                        size: size,
                        isProtected: false
                    ))
                }
            }
        }

        return residuals
    }

    /// 异步扫描单个应用残留，避免在点击卸载时阻塞界面
    func scanResidualFilesAsync(for app: InstalledApp) async -> [ResidualFile] {
        await Task.detached(priority: .userInitiated) {
            Self.findResidualFiles(for: app)
        }.value
    }

    /// 卸载单个应用及其残留文件（移入废纸篓）
    func uninstallApp(_ app: InstalledApp, residualFiles: [ResidualFile]) {
        isUninstalling = true
        currentUninstallApp = app
        uninstallProgress = 0
        completedOperationCount = 0
        uninstallErrorMessage = nil
        uninstallSuccessMessage = nil

        let tasks = residualFiles.map {
            TrashTask(url: $0.url, appID: nil, residualID: $0.id, isApp: false, appName: nil)
        } + [
            TrashTask(url: app.url, appID: app.id, residualID: nil, isApp: true, appName: app.name)
        ]
        totalOperationCount = tasks.count

        Task {
            await runTrashTasks(tasks)
        }
    }

    /// 批量卸载多个应用及其残留文件
    func batchUninstall(_ apps: [InstalledApp], residualFiles: [ResidualFile]) {
        isUninstalling = true
        currentUninstallApp = nil
        uninstallProgress = 0
        completedOperationCount = 0
        uninstallErrorMessage = nil
        uninstallSuccessMessage = nil

        let residualTasks = residualFiles.map {
            TrashTask(url: $0.url, appID: nil, residualID: $0.id, isApp: false, appName: nil)
        }
        let appTasks = apps.map {
            TrashTask(url: $0.url, appID: $0.id, residualID: nil, isApp: true, appName: $0.name)
        }
        totalOperationCount = residualTasks.count + appTasks.count

        Task {
            await runTrashTasks(residualTasks + appTasks)
        }
    }

    /// 递归计算目录的总大小
    static func directorySize(at url: URL) -> UInt64 {
        let fm = FileManager.default
        var totalSize: UInt64 = 0

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else { return 0 }

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                  let isDirectory = resourceValues.isDirectory,
                  !isDirectory,
                  let fileSize = resourceValues.fileSize else {
                continue
            }
            totalSize += UInt64(fileSize)
        }

        return totalSize
    }

    private static func itemSize(at url: URL) -> UInt64 {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if isDirectory {
            return directorySize(at: url)
        }
        return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(UInt64.init) ?? 0
    }

    private static func findResidualFiles(for app: InstalledApp) -> [ResidualFile] {
        let fm = FileManager.default
        let home = FileManager.default.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library")
        var residuals: [ResidualFile] = []

        let searchPaths: [(String, String)] = [
            ("Application Support", app.name),
            ("Application Support", app.bundleID),
            ("Preferences", "\(app.bundleID).plist"),
            ("Caches", app.bundleID),
            ("Caches", app.name),
            ("Logs", app.name),
            ("LaunchAgents", app.bundleID),
            ("LaunchAgents", app.name),
            ("Containers", app.bundleID),
            ("Group Containers", app.bundleID),
            ("Saved Application State", "\(app.bundleID).savedState"),
            ("HTTPStorages", app.bundleID),
            ("WebKit", app.bundleID)
        ]

        for (subpath, component) in searchPaths {
            let target = library.appendingPathComponent(subpath).appendingPathComponent(component)

            if fm.fileExists(atPath: target.path) {
                let size = Self.directorySize(at: target)
                let isProtected = subpath == "Containers" || subpath == "Group Containers"
                residuals.append(ResidualFile(
                    id: target,
                    url: target,
                    name: "\(subpath)/\(component)",
                    size: size,
                    isProtected: isProtected
                ))
            }
        }

        let launchAgentsDir = library.appendingPathComponent("LaunchAgents")
        if let contents = try? fm.contentsOfDirectory(at: launchAgentsDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            for fileURL in contents {
                let filename = fileURL.lastPathComponent
                if filename.hasPrefix(app.bundleID) || filename.hasPrefix(app.name) {
                    residuals.append(ResidualFile(
                        id: fileURL,
                        url: fileURL,
                        name: "LaunchAgents/\(filename)",
                        size: Self.directorySize(at: fileURL),
                        isProtected: false
                    ))
                }
            }
        }

        let groupContainersDir = library.appendingPathComponent("Group Containers")
        if let contents = try? fm.contentsOfDirectory(at: groupContainersDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            for fileURL in contents where fileURL.lastPathComponent.hasPrefix(app.bundleID) {
                residuals.append(ResidualFile(
                    id: fileURL,
                    url: fileURL,
                    name: "Group Containers/\(fileURL.lastPathComponent)",
                    size: Self.directorySize(at: fileURL),
                    isProtected: true
                ))
            }
        }

        let savedStateDir = library.appendingPathComponent("Saved Application State")
        if let contents = try? fm.contentsOfDirectory(at: savedStateDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            for fileURL in contents where fileURL.lastPathComponent.hasPrefix(app.bundleID) {
                residuals.append(ResidualFile(
                    id: fileURL,
                    url: fileURL,
                    name: "Saved Application State/\(fileURL.lastPathComponent)",
                    size: Self.directorySize(at: fileURL),
                    isProtected: false
                ))
            }
        }

        return residuals
    }

    private func runTrashTasks(_ tasks: [TrashTask]) async {
        if tasks.isEmpty {
            await MainActor.run {
                finishTrashOperation()
            }
            return
        }

        let maxConcurrentTasks = 8
        var failures: [(TrashTask, String)] = []
        var successfulTasks: [TrashTask] = []

        await withTaskGroup(of: TrashTaskResult.self) { group in
            var iterator = tasks.makeIterator()
            var submitted = 0

            func submitNext() {
                guard let task = iterator.next() else { return }
                submitted += 1
                group.addTask {
                    do {
                        try await Self.moveItemToTrash(task)
                        return TrashTaskResult(task: task, errorDescription: nil)
                    } catch {
                        AppLogger.error(error, context: "无法移除 \(task.url.path)", log: .uninstaller)
                        return TrashTaskResult(task: task, errorDescription: error.localizedDescription)
                    }
                }
            }

            for _ in 0..<min(maxConcurrentTasks, tasks.count) {
                submitNext()
            }

            for await result in group {
                await MainActor.run {
                    completedOperationCount += 1
                    uninstallProgress = Double(completedOperationCount) / Double(totalOperationCount)

                    if result.errorDescription == nil {
                        applyCompletedTrashTask(result.task)
                    }
                }

                if let errorDescription = result.errorDescription {
                    failures.append((result.task, errorDescription))
                } else {
                    successfulTasks.append(result.task)
                }

                if submitted < tasks.count {
                    submitNext()
                }
            }
        }

        let failureMessage = makeTrashFailureMessage(from: failures)
        let successMessage = makeTrashSuccessMessage(from: successfulTasks)
        await MainActor.run {
            finishTrashOperation(errorMessage: failureMessage, successMessage: successMessage)
        }
    }

    private static func moveItemToTrash(_ task: TrashTask) async throws {
        do {
            try await recycleItem(at: task.url)
        } catch {
            guard canRequestAdministratorPrivileges(for: task.url) else {
                throw error
            }

            try await moveItemToTrashWithAdministratorPrivileges(at: task.url)
        }
    }

    private static func recycleItem(at url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.main.async {
                NSWorkspace.shared.recycle([url]) { _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
        }
    }

    private static func canRequestAdministratorPrivileges(for url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return !path.hasPrefix("/System/Applications/")
    }

    private static func moveItemToTrashWithAdministratorPrivileges(at url: URL) async throws {
        let sourceURL = url.standardizedFileURL
        let trashDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true)
        let destinationURL = uniqueTrashDestination(for: sourceURL, in: trashDirectory)
        let command = [
            "/bin/mkdir -p \(shellQuoted(trashDirectory.path))",
            "/bin/mv \(shellQuoted(sourceURL.path)) \(shellQuoted(destinationURL.path))"
        ].joined(separator: " && ")
        let scriptSource = "do shell script \(appleScriptStringLiteral(command)) with administrator privileges"

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.main.async {
                var errorInfo: NSDictionary?
                let result = NSAppleScript(source: scriptSource)?.executeAndReturnError(&errorInfo)

                if result != nil {
                    continuation.resume(returning: ())
                    return
                }

                let message = (errorInfo?[NSAppleScript.errorMessage] as? String)
                    ?? "管理员授权删除失败"
                continuation.resume(throwing: PrivilegedTrashError(message: message))
            }
        }
    }

    private static func uniqueTrashDestination(for sourceURL: URL, in trashDirectory: URL) -> URL {
        let fileManager = FileManager.default
        var destination = trashDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        guard fileManager.fileExists(atPath: destination.path) else { return destination }

        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let pathExtension = sourceURL.pathExtension
        let timestamp = trashTimestampFormatter.string(from: Date())
        let suffix = UUID().uuidString.prefix(8)
        let uniqueName = pathExtension.isEmpty
            ? "\(baseName) \(timestamp)-\(suffix)"
            : "\(baseName) \(timestamp)-\(suffix).\(pathExtension)"

        destination = trashDirectory.appendingPathComponent(uniqueName)
        return destination
    }

    private static var trashTimestampFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func appleScriptStringLiteral(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private func applyCompletedTrashTask(_ task: TrashTask) {
        if task.isApp, let appID = task.appID {
            installedApps.removeAll { $0.id == appID }
            filteredApps.removeAll { $0.id == appID }
            selectedApps.remove(appID)
            if currentUninstallApp?.id == appID {
                currentUninstallApp = nil
            }
        }

        if let residualID = task.residualID {
            orphanResiduals.removeAll { $0.id == residualID }
            selectedOrphanResiduals.remove(residualID)
        }
    }

    private func finishTrashOperation(errorMessage: String? = nil, successMessage: String? = nil) {
        isUninstalling = false
        currentUninstallApp = nil
        uninstallProgress = 0
        completedOperationCount = 0
        totalOperationCount = 0
        uninstallErrorMessage = errorMessage
        uninstallSuccessMessage = successMessage
    }

    private func makeTrashFailureMessage(from failures: [(TrashTask, String)]) -> String? {
        guard !failures.isEmpty else { return nil }

        let visibleFailures = failures.prefix(5).map { task, error in
            "- \(task.url.lastPathComponent): \(error)"
        }
        let remainingCount = failures.count - visibleFailures.count
        let remainingMessage = remainingCount > 0 ? "\n...还有 \(remainingCount) 个项目失败" : ""

        return "以下项目无法移入废纸篓：\n\(visibleFailures.joined(separator: "\n"))\(remainingMessage)"
    }

    private func makeTrashSuccessMessage(from tasks: [TrashTask]) -> String? {
        guard !tasks.isEmpty else { return nil }

        let appNames = tasks.compactMap(\.appName)
        if appNames.count == 1, let appName = appNames.first {
            return "\(appName) 已卸载"
        }
        if appNames.count > 1 {
            return "已卸载 \(appNames.count) 个应用"
        }
        return "残留文件已清理"
    }

    private static func installedAppIndex(from apps: [InstalledApp]) -> InstalledAppIndex {
        InstalledAppIndex(
            bundleIDs: Set(apps.map(\.bundleID).filter { !$0.isEmpty }),
            names: Set(apps.map(\.name).filter { !$0.isEmpty })
        )
    }
    
    private static func scanInstalledAppsSync() -> [InstalledApp] {
        var apps: [InstalledApp] = []
        var seenURLs: Set<URL> = []

        for appURL in Self.discoverApplicationURLs() {
            let standardizedURL = appURL.standardizedFileURL
            guard !seenURLs.contains(standardizedURL) else { continue }
            seenURLs.insert(standardizedURL)

            if let app = Self.installedApp(at: standardizedURL) {
                apps.append(app)
            }
        }

        apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return apps
    }

    private static func bundleIdentifierCandidate(from filename: String, stripExtensions: [String]) -> String? {
        var candidate = filename

        for suffix in stripExtensions {
            let dottedSuffix = ".\(suffix)"
            if candidate.hasSuffix(dottedSuffix) {
                candidate.removeLast(dottedSuffix.count)
            }
        }

        candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty ? nil : candidate
    }

    private static func looksLikeBundleIdentifier(_ value: String) -> Bool {
        let parts = value.split(separator: ".")
        guard parts.count >= 3 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { character in
                character.isLetter || character.isNumber || character == "-" || character == "_"
            }
        }
    }

    private static func isAppleOrSystemIdentifier(_ value: String) -> Bool {
        let systemPrefixes = [
            "com.apple.",
            "com.microsoft.autoupdate",
            "com.google.keystone",
            "com.adobe.acc",
            "com.oracle.java",
            "org.cups."
        ]
        return systemPrefixes.contains { value.hasPrefix($0) }
    }

    private static func matchesInstalledApp(_ candidateIdentifier: String, index: InstalledAppIndex) -> Bool {
        index.bundleIDs.contains { bundleID in
            candidateIdentifier == bundleID ||
            candidateIdentifier.hasPrefix(bundleID + ".") ||
            bundleID.hasPrefix(candidateIdentifier + ".")
        } || index.names.contains { name in
            candidateIdentifier == name || candidateIdentifier.hasPrefix(name + ".")
        }
    }

    /// 扫描已卸载应用残留的文件（应用已卸载但在 Library 中仍有残留）
    func scanOrphanResiduals() {
        guard !isScanningOrphans else { return }
        isScanningOrphans = true
        orphanResiduals = []
        selectedOrphanResiduals = []
        currentOrphanScanPath = "~/Library"

        Task {
            await scanOrphanResidualsAsync()
        }
    }
    
    private func scanOrphanResidualsAsync() async {
        if installedApps.isEmpty {
            await MainActor.run {
                isScanning = true
            }
            let apps = await Task.detached(priority: .userInitiated) {
                Self.scanInstalledAppsSync()
            }.value
            await MainActor.run {
                installedApps = apps
                filteredApps = apps
                isScanning = false
            }
        }
        
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library")

        let installedIndex = Self.installedAppIndex(from: installedApps)

        var residuals: [ResidualFile] = []

        let scanRules: [OrphanScanRule] = [
            OrphanScanRule(
                subpath: "Caches",
                requiresDirectory: nil,
                isProtected: false,
                allowedExtensions: [],
                requireBundleIdentifier: true,
                stripExtensions: []
            ),
            OrphanScanRule(
                subpath: "Preferences",
                requiresDirectory: false,
                isProtected: false,
                allowedExtensions: ["plist"],
                requireBundleIdentifier: true,
                stripExtensions: ["plist"]
            ),
            OrphanScanRule(
                subpath: "Saved Application State",
                requiresDirectory: true,
                isProtected: false,
                allowedExtensions: ["savedState"],
                requireBundleIdentifier: true,
                stripExtensions: ["savedState"]
            ),
            OrphanScanRule(
                subpath: "HTTPStorages",
                requiresDirectory: nil,
                isProtected: false,
                allowedExtensions: [],
                requireBundleIdentifier: true,
                stripExtensions: []
            ),
            OrphanScanRule(
                subpath: "WebKit",
                requiresDirectory: true,
                isProtected: false,
                allowedExtensions: [],
                requireBundleIdentifier: true,
                stripExtensions: []
            ),
            OrphanScanRule(
                subpath: "Containers",
                requiresDirectory: true,
                isProtected: true,
                allowedExtensions: [],
                requireBundleIdentifier: true,
                stripExtensions: []
            ),
            OrphanScanRule(
                subpath: "Group Containers",
                requiresDirectory: true,
                isProtected: true,
                allowedExtensions: [],
                requireBundleIdentifier: true,
                stripExtensions: []
            )
        ]

        for rule in scanRules {
            await MainActor.run {
                self.currentOrphanScanPath = "~/Library/\(rule.subpath)"
            }
            let dir = library.appendingPathComponent(rule.subpath)
            guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles) else {
                continue
            }

            for fileURL in contents {
                let filename = fileURL.lastPathComponent

                if let requiresDirectory = rule.requiresDirectory {
                    guard let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]),
                          let isDirectory = values.isDirectory,
                          isDirectory == requiresDirectory else {
                        continue
                    }
                }

                guard let candidateIdentifier = Self.bundleIdentifierCandidate(
                    from: filename,
                    stripExtensions: rule.stripExtensions
                ) else { continue }

                if rule.requireBundleIdentifier && !Self.looksLikeBundleIdentifier(candidateIdentifier) {
                    continue
                }

                if !rule.allowedExtensions.isEmpty && !rule.allowedExtensions.contains(fileURL.pathExtension) {
                    continue
                }

                if Self.isAppleOrSystemIdentifier(candidateIdentifier) { continue }
                if Self.matchesInstalledApp(candidateIdentifier, index: installedIndex) { continue }

                let size = Self.itemSize(at: fileURL)

                if size == 0 { continue }

                residuals.append(ResidualFile(
                    id: fileURL,
                    url: fileURL,
                    name: "\(rule.subpath)/\(filename)",
                    size: size,
                    isProtected: rule.isProtected
                ))
            }
        }

        await MainActor.run {
            self.currentOrphanScanPath = "~/Library/LaunchAgents"
        }
        let launchAgentsDir = library.appendingPathComponent("LaunchAgents")
        if let contents = try? fm.contentsOfDirectory(at: launchAgentsDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            for fileURL in contents {
                let filename = fileURL.lastPathComponent
                guard fileURL.pathExtension == "plist",
                      let candidateIdentifier = Self.bundleIdentifierCandidate(from: filename, stripExtensions: ["plist"]),
                      Self.looksLikeBundleIdentifier(candidateIdentifier),
                      !Self.isAppleOrSystemIdentifier(candidateIdentifier),
                      !Self.matchesInstalledApp(candidateIdentifier, index: installedIndex) else { continue }

                let size = Self.itemSize(at: fileURL)
                if size == 0 { continue }

                residuals.append(ResidualFile(
                    id: fileURL,
                    url: fileURL,
                    name: "LaunchAgents/\(filename)",
                    size: size,
                    isProtected: false
                ))
            }
        }

        await MainActor.run {
            self.currentOrphanScanPath = "~/Library/Logs"
        }
        let logsDir = library.appendingPathComponent("Logs")
        if let contents = try? fm.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            for fileURL in contents {
                let filename = fileURL.lastPathComponent
                guard let candidateIdentifier = Self.bundleIdentifierCandidate(from: filename, stripExtensions: ["log"]),
                      Self.looksLikeBundleIdentifier(candidateIdentifier),
                      !Self.isAppleOrSystemIdentifier(candidateIdentifier),
                      !Self.matchesInstalledApp(candidateIdentifier, index: installedIndex) else { continue }

                let size = Self.itemSize(at: fileURL)
                if size == 0 { continue }

                residuals.append(ResidualFile(
                    id: fileURL,
                    url: fileURL,
                    name: "Logs/\(filename)",
                    size: size,
                    isProtected: false
                ))
            }
        }

        residuals.sort { $0.size > $1.size }
        let finalResiduals = residuals

        await MainActor.run {
            self.orphanResiduals = finalResiduals
            self.selectedOrphanResiduals = Set(finalResiduals.filter(\.isSelectedByDefault).map(\.id))
            self.isScanningOrphans = false
            self.currentOrphanScanPath = ""
        }
    }

    /// 清理选中的孤立残留文件（移入废纸篓）
    func cleanOrphanResiduals(_ residuals: [ResidualFile]) {
        isUninstalling = true
        currentUninstallApp = nil
        uninstallProgress = 0
        completedOperationCount = 0
        uninstallErrorMessage = nil
        uninstallSuccessMessage = nil

        let tasks = residuals.map {
            TrashTask(url: $0.url, appID: nil, residualID: $0.id, isApp: false, appName: nil)
        }
        totalOperationCount = tasks.count

        Task {
            await runTrashTasks(tasks)
        }
    }
}

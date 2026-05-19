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

    /// 扫描常见 Applications 目录下所有 .app 应用
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
                if url.pathExtension == "app" {
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

    /// 卸载单个应用及其残留文件（移入废纸篓）
    func uninstallApp(_ app: InstalledApp, residualFiles: [ResidualFile]) {
        isUninstalling = true
        currentUninstallApp = app

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fm = FileManager.default

            for residual in residualFiles {
                do {
                    var resultURL: NSURL?
                    try fm.trashItem(at: residual.url, resultingItemURL: &resultURL)
                } catch {
                    print("无法移除残留文件 \(residual.url.path): \(error.localizedDescription)")
                }
            }

            do {
                var resultURL: NSURL?
                try fm.trashItem(at: app.url, resultingItemURL: &resultURL)
            } catch {
                print("无法移除应用 \(app.url.path): \(error.localizedDescription)")
            }

            DispatchQueue.main.async {
                self?.installedApps.removeAll { $0.id == app.id }
                self?.filteredApps.removeAll { $0.id == app.id }
                self?.selectedApps.remove(app.id)
                self?.isUninstalling = false
                self?.currentUninstallApp = nil
            }
        }
    }

    /// 批量卸载多个应用及其残留文件
    func batchUninstall(_ apps: [InstalledApp], residualFiles: [ResidualFile]) {
        isUninstalling = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fm = FileManager.default

            for residual in residualFiles {
                do {
                    var resultURL: NSURL?
                    try fm.trashItem(at: residual.url, resultingItemURL: &resultURL)
                } catch {
                    print("无法移除残留文件 \(residual.url.path): \(error.localizedDescription)")
                }
            }

            for app in apps {
                do {
                    var resultURL: NSURL?
                    try fm.trashItem(at: app.url, resultingItemURL: &resultURL)
                } catch {
                    print("无法移除应用 \(app.url.path): \(error.localizedDescription)")
                }
            }

            DispatchQueue.main.async {
                let ids = Set(apps.map(\.id))
                self?.installedApps.removeAll { ids.contains($0.id) }
                self?.filteredApps.removeAll { ids.contains($0.id) }
                self?.selectedApps.subtract(ids)
                self?.isUninstalling = false
                self?.currentUninstallApp = nil
            }
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

    private static func installedAppIndex(from apps: [InstalledApp]) -> InstalledAppIndex {
        InstalledAppIndex(
            bundleIDs: Set(apps.map(\.bundleID).filter { !$0.isEmpty }),
            names: Set(apps.map(\.name).filter { !$0.isEmpty })
        )
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

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            let home = fm.homeDirectoryForCurrentUser
            let library = home.appendingPathComponent("Library")

            let installedIndex = Self.installedAppIndex(from: self.installedApps)

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
                DispatchQueue.main.async {
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

            DispatchQueue.main.async {
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

            DispatchQueue.main.async {
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

            DispatchQueue.main.async {
                self.orphanResiduals = residuals
                self.selectedOrphanResiduals = Set(residuals.filter(\.isSelectedByDefault).map(\.id))
                self.isScanningOrphans = false
                self.currentOrphanScanPath = ""
            }
        }
    }

    /// 清理选中的孤立残留文件（移入废纸篓）
    func cleanOrphanResiduals(_ residuals: [ResidualFile]) {
        isUninstalling = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fm = FileManager.default
            for residual in residuals {
                do {
                    var resultURL: NSURL?
                    try fm.trashItem(at: residual.url, resultingItemURL: &resultURL)
                } catch {
                    print("无法移除残留文件 \(residual.url.path): \(error.localizedDescription)")
                }
            }

            DispatchQueue.main.async {
                let cleanedIDs = Set(residuals.map(\.id))
                self?.orphanResiduals.removeAll { cleanedIDs.contains($0.id) }
                self?.selectedOrphanResiduals.subtract(cleanedIDs)
                self?.isUninstalling = false
                self?.currentUninstallApp = nil
            }
        }
    }
}

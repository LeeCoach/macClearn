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

    /// 扫描 /Applications 目录下所有 .app 应用
    func scanApplications() {
        guard !isScanning else { return }
        isScanning = true
        installedApps = []
        filteredApps = []
        selectedApps = []

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fm = FileManager.default
            let appsDir = URL(fileURLWithPath: "/Applications")
            var apps: [InstalledApp] = []

            guard let contents = try? fm.contentsOfDirectory(at: appsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
                DispatchQueue.main.async {
                    self?.isScanning = false
                }
                return
            }

            for appURL in contents {
                guard appURL.pathExtension == "app" else { continue }

                // 读取应用的 Info.plist 获取元数据
                let plistPath = appURL.appendingPathComponent("Contents/Info.plist")
                guard let plistData = try? Data(contentsOf: plistPath),
                      let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] else {
                    continue
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

                let app = InstalledApp(
                    id: appURL,
                    name: name,
                    bundleID: bundleID,
                    version: version,
                    url: appURL,
                    size: size,
                    icon: icon,
                    lastAccessed: lastAccessed
                )
                apps.append(app)
            }

            apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            DispatchQueue.main.async {
                self?.installedApps = apps
                self?.filteredApps = apps
                self?.isScanning = false
            }
        }
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
    func batchUninstall(_ apps: [InstalledApp]) {
        isUninstalling = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fm = FileManager.default

            for app in apps {
                let residuals = self?.scanResidualFiles(for: app) ?? []

                for residual in residuals {
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
}

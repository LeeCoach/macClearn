// PermissionManager.swift - 权限管理服务，检测完全磁盘访问权限并管理排除路径

import AppKit
import Foundation
import Combine

/// 权限管理器，负责检测完全磁盘访问权限、打开系统偏好设置、管理排除路径
class PermissionManager: ObservableObject {
    /// 是否已获得完全磁盘访问权限
    @Published var hasFullDiskAccess: Bool = false
    /// 是否显示权限引导提示
    @Published var showPermissionGuide: Bool = false
    /// 用户排除的路径列表
    @Published var excludedPaths: [String] = []

    private let excludedPathsKey = "MacCleaner.excludedPaths"

    init() {
        checkFullDiskAccess()
        loadExcludedPaths()
    }

    /// 检测是否拥有完全磁盘访问权限，通过实际枚举受 TCC 保护的目录来判断
    func checkFullDiskAccess() {
        let protectedPaths = [
            NSHomeDirectory() + "/Library/Safari",
            NSHomeDirectory() + "/Library/Messages",
            NSHomeDirectory() + "/Library/Mail",
            NSHomeDirectory() + "/Library/Application Support/com.apple.TCC",
            "/Library/Application Support/com.apple.TCC"
        ]
        
        hasFullDiskAccess = protectedPaths.contains(where: canEnumerateProtectedDirectory)

        if hasFullDiskAccess {
            showPermissionGuide = false
        }
    }

    func hidePermissionGuide() {
        showPermissionGuide = false
    }

    /// 用于授权的首选应用路径：已安装到「应用程序」时优先，否则为当前运行中的 .app
    var applicationURLForPermissionGrant: URL {
        let installedURL = URL(fileURLWithPath: "/Applications/MacCleaner.app")
        if FileManager.default.fileExists(atPath: installedURL.path) {
            return installedURL
        }
        return Bundle.main.bundleURL
    }

    /// 是否从「应用程序」目录启动（从 DMG 直接运行时需在设置里手动选路径或先安装）
    var isRunningFromApplications: Bool {
        Bundle.main.bundleURL.path.hasPrefix("/Applications/")
    }

    /// 尝试访问受保护路径，便于在部分系统版本上登记到 TCC（仍需用户在设置中手动点 + 添加）
    func registerFullDiskAccessRequest() {
        let probePath = NSHomeDirectory() + "/Library/Safari"
        _ = FileManager.default.isReadableFile(atPath: probePath)
    }

    /// 打开「完全磁盘访问权限」系统设置
    func openPrivacySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ]
        for urlString in urls {
            if let url = URL(string: urlString), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    /// 在 Finder 中定位 MacCleaner.app，便于用户在「完全磁盘访问」里点 + 手动添加
    func revealApplicationInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([applicationURLForPermissionGrant])
    }

    /// 添加排除路径并持久化到 UserDefaults
    func addExcludedPath(_ path: String) {
        let normalizedPath = normalized(path)
        guard !normalizedPath.isEmpty && !excludedPaths.contains(normalizedPath) else { return }
        excludedPaths.append(normalizedPath)
        saveExcludedPaths()
    }

    func removeExcludedPath(at index: Int) {
        guard index >= 0 && index < excludedPaths.count else { return }
        excludedPaths.remove(at: index)
        saveExcludedPaths()
    }

    /// 判断路径是否被排除（精确匹配或为排除路径的子路径）
    func isPathExcluded(_ path: String) -> Bool {
        let normalizedPath = normalized(path)
        return excludedPaths.contains { excludedPath in
            normalizedPath == excludedPath || normalizedPath.hasPrefix(excludedPath + "/")
        }
    }

    private func loadExcludedPaths() {
        excludedPaths = UserDefaults.standard.stringArray(forKey: excludedPathsKey) ?? []
    }

    private func saveExcludedPaths() {
        UserDefaults.standard.set(excludedPaths, forKey: excludedPathsKey)
    }

    /// 将路径标准化（解析符号链接和 "." ".."）
    private func normalized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func canEnumerateProtectedDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }

        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: path)
            return true
        } catch {
            return false
        }
    }
}

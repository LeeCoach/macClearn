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

    /// 检测是否拥有完全磁盘访问权限，通过尝试读取受 TCC 保护的目录来判断
    func checkFullDiskAccess() {
        // 尝试读取 TCC 数据库目录，该目录受完全磁盘访问权限保护
        let testPath = "/Library/Application Support/com.apple.TCC"
        let fm = FileManager.default

        if fm.fileExists(atPath: testPath) {
            if fm.isReadableFile(atPath: testPath) {
                hasFullDiskAccess = true
            } else {
                hasFullDiskAccess = false
            }
        } else {
            // 备用检测：尝试读取 Safari 目录
            let testPath2 = NSHomeDirectory() + "/Library/Safari"
            hasFullDiskAccess = fm.isReadableFile(atPath: testPath2)
        }

        if !hasFullDiskAccess {
            showPermissionGuide = true
        }
    }

    /// 打开系统偏好设置的隐私与安全性页面
    func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
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
}

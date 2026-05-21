//
// InstalledApp.swift
// MacCleaner
//
//  已安装应用的数据模型。通过解析 /Applications 下 .app 包的
//  Contents/Info.plist 获取应用元数据（名称 / Bundle ID / 版本号）。
//
//  同时支持插件/服务的 Bundle 类型（.plugin / .prefPane / .qlgenerator 等），
//  路径扩展名不是 .app 时会显示类型标签（如 "Internet Plug-In"）。
//

import AppKit

/// 已安装应用（或插件/服务）的信息。
///
/// - id: 以 url 作为 Identifiable 的稳定标识
/// - version: 可能为空（部分插件不含 CFBundleShortVersionString）
/// - icon: 通过 NSWorkspace.shared.icon(forFile:) 获取系统图标
/// - lastAccessed: 文件的 modificationDate，用于排序/展示
struct InstalledApp: Identifiable {
    let id: URL
    let name: String           // 取自 CFBundleName / CFBundleDisplayName / 文件名
    let bundleID: String       // CFBundleIdentifier
    let version: String?       // CFBundleShortVersionString 或 CFBundleVersion
    let url: URL               // .app 或 .plugin 包的完整路径
    let size: UInt64           // 递归计算的包总大小
    let icon: NSImage?         // 48×48 的应用图标
    let lastAccessed: Date?    // 文件的 modificationDate

    /// 版本 + Bundle ID 的描述文本，用于列表副标题
    func detailText(localization: LocalizationManager) -> String {
        if let version, !version.isEmpty {
            return localization.text("uninstaller.versionDetail", version, bundleID)
        }
        return bundleID
    }

    /// 格式化后的应用大小字符串（如 "123.4 MB"）
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

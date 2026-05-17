// InstalledApp.swift - 已安装应用数据模型

import AppKit

/// 已安装应用信息，用于应用卸载功能中展示应用详情
struct InstalledApp: Identifiable {
    let id: URL
    let name: String
    let bundleID: String
    let version: String?
    let url: URL
    let size: UInt64
    let icon: NSImage?
    let lastAccessed: Date?

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

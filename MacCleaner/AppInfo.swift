//
// AppInfo.swift
// MacCleaner
//
//  应用元数据配置，与 MacCleaner/Info.plist 保持同步。
//  提供运行时解析 Bundle ID 和 Display Name 的方法，
//  支持从已安装的 .app bundle 中读取、从内嵌 Info.plist 中读取，
//  最终回退到此处的静态默认值。
//
//  修改 Bundle ID 或 Display Name 时需同时更新：
//    1. MacCleaner/Info.plist 中的对应字段
//    2. 此文件中的静态常量
//

import Foundation

/// 应用元数据工具。
enum AppInfo {
    /// 与 MacCleaner/Info.plist 中 CFBundleIdentifier 保持一致
    static let bundleIdentifier = "com.maccleaner.app"
    static let name = "MacCleaner"
    static let displayName = "MacCleaner"

    /// 运行时 Bundle ID（回退链路：Bundle.main → 内嵌 Info.plist → 静态默认值）
    static var resolvedBundleIdentifier: String {
        if let value = Bundle.main.bundleIdentifier, !value.isEmpty {
            return value
        }
        if let value = Bundle.main.infoDictionary?["CFBundleIdentifier"] as? String, !value.isEmpty {
            return value
        }
        if let value = embeddedInfoPlistValue(for: "CFBundleIdentifier"), !value.isEmpty {
            return value
        }
        return bundleIdentifier
    }

    /// 运行时显示名称（回退链路同上）
    static var resolvedDisplayName: String {
        if let value = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String, !value.isEmpty {
            return value
        }
        if let value = Bundle.main.infoDictionary?["CFBundleName"] as? String, !value.isEmpty {
            return value
        }
        return displayName
    }

    /// 从内嵌 Info.plist 读取指定 key 的值
    private static func embeddedInfoPlistValue(for key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "Info", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let value = plist[key] as? String else {
            return nil
        }
        return value
    }
}

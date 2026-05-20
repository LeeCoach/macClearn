// AppInfo.swift - 应用元数据（与 Info.plist 保持一致）

import Foundation

enum AppInfo {
    /// 与 MacCleaner/Info.plist 中 CFBundleIdentifier 保持一致
    static let bundleIdentifier = "com.maccleaner.app"
    static let name = "MacCleaner"
    static let displayName = "MacCleaner"

    /// 运行时 Bundle ID：优先读取已嵌入的 Info.plist，否则回退到项目配置
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

    static var resolvedDisplayName: String {
        if let value = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String, !value.isEmpty {
            return value
        }
        if let value = Bundle.main.infoDictionary?["CFBundleName"] as? String, !value.isEmpty {
            return value
        }
        return displayName
    }

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

// Version.swift - 应用版本号唯一配置源（打包前会同步到 Info.plist）

import Foundation

enum AppVersion {
    /// 对外展示版本号（修改版本时只改这里）
    static let marketing = "1.4.0"

    /// 构建号，默认与 marketing 一致
    static let build = marketing

    /// 运行时版本：优先 Info.plist / Bundle，否则回退到配置
    static var resolvedMarketing: String {
        if let value = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           !value.isEmpty {
            return value
        }
        if let value = embeddedInfoPlistValue(for: "CFBundleShortVersionString"), !value.isEmpty {
            return value
        }
        return marketing
    }

    static var resolvedBuild: String {
        if let value = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
           !value.isEmpty {
            return value
        }
        if let value = embeddedInfoPlistValue(for: "CFBundleVersion"), !value.isEmpty {
            return value
        }
        return build
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

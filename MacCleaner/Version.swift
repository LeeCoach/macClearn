//
// Version.swift
// MacCleaner
//
//  应用版本号唯一配置源。
//  所有版本号信息集中在此文件中管理（单点修改原则）。
//
//  发布流程：
//    1. 修改 `marketing` 常量
//    2. 运行自动化脚本或手动同步到 Info.plist 的
//       CFBundleShortVersionString 和 CFBundleVersion
//    3. 打 tag 并推送触发 CI 打包
//

import Foundation

/// 版本号管理。
enum AppVersion {
    /// 对外展示版本号（**修改版本时只改这里**）
    static let marketing = "1.4.1"

    /// 构建号，默认与 marketing 一致；也可独立管理
    static let build = marketing

    /// 运行时版本号（回退链路：Bundle → 内嵌 Info.plist → 静态值）
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

    /// 运行时构建号（回退链路同上）
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

    /// 从内嵌 Info.plist 文件中读取指定 key 的字符串值
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

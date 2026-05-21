//
// ByteFormatter.swift
// MacCleaner
//
//  字节数格式化工具。将 UInt64 类型的字节数转换为人类可读的字符串。
//
//  支持标准格式（含空格）和短格式（无空格，用于侧边栏标签）。
//  采用单例模式（shared）避免重复创建。
//

import Foundation

/// 字节数格式化器。
///
/// 使用示例：
/// ```
/// ByteFormatter.shared.format(1_234_567_890)    // "1.1 GB"
/// ByteFormatter.shared.format(1024)              // "1.0 KB"
/// ByteFormatter.shared.formatShort(1024)         // "1.0KB"
/// ```
struct ByteFormatter {
    /// 全局共享实例
    static let shared = ByteFormatter()

    private let units = ["B", "KB", "MB", "GB", "TB"]

    private init() {}

    /// 标准格式，含数字与单位之间的空格。
    /// - Parameter includeSpace: 是否在数字和单位间加空格（默认 true）
    func format(_ bytes: UInt64, includeSpace: Bool = true) -> String {
        var value = Double(bytes)
        var unitIndex = 0

        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        let space = includeSpace ? " " : ""
        return String(format: "%.1f\(space)%@", value, units[unitIndex])
    }

    /// 短格式（无空格），用于侧边栏等紧凑空间。
    /// 字节数为 0 时特殊处理，不显示小数位。
    func formatShort(_ bytes: UInt64) -> String {
        var value = Double(bytes)
        var unitIndex = 0

        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return String(format: "%.0f%@", value, units[unitIndex])
        }
        return String(format: "%.1f%@", value, units[unitIndex])
    }
}

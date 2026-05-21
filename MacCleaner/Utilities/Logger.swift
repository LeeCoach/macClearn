//
// Logger.swift
// MacCleaner
//
//  统一的日志工具，基于 Apple os_log 框架。
//  按功能模块（App / Disk / Memory / Permission / Uninstaller）分类，
//  在 Console.app 中以 "MacCleaner" 为子系统名按类别过滤查看。
//

import Foundation
import os.log

// MARK: - 日志分类

extension OSLog {
    static let app = OSLog(subsystem: "com.maccleaner.app", category: "App")
    static let disk = OSLog(subsystem: "com.maccleaner.app", category: "Disk")
    static let memory = OSLog(subsystem: "com.maccleaner.app", category: "Memory")
    static let permission = OSLog(subsystem: "com.maccleaner.app", category: "Permission")
    static let uninstaller = OSLog(subsystem: "com.maccleaner.app", category: "Uninstaller")
}

// MARK: - 日志工具

/// 统一日志接口。
///
/// 日志级别从低到高：debug → info → error → fault。
/// 使用示例：
/// ```
/// AppLogger.info("Scan completed", log: .disk)
/// AppLogger.error(err, context: "Failed to clean file", log: .disk)
/// ```
struct AppLogger {

    // MARK: 通用日志

    /// 调试日志（仅开发阶段启用）
    static func debug(_ message: String, log: OSLog = .app) {
        os_log(.debug, log: log, "%{public}@", message)
    }

    /// 信息日志
    static func info(_ message: String, log: OSLog = .app) {
        os_log(.info, log: log, "%{public}@", message)
    }

    /// 错误日志（仅消息文本）
    static func error(_ message: String, log: OSLog = .app) {
        os_log(.error, log: log, "%{public}@", message)
    }

    /// 错误日志（Swift Error 对象 + 上下文描述）
    static func error(_ error: Error, context: String = "", log: OSLog = .app) {
        let message = context.isEmpty ? error.localizedDescription : "\(context): \(error.localizedDescription)"
        os_log(.error, log: log, "%{public}@", message)
    }

    /// 严重错误日志（fault 级别）
    static func fault(_ message: String, log: OSLog = .app) {
        os_log(.fault, log: log, "%{public}@", message)
    }

    // MARK: 磁盘扫描/清理专用日志

    static func scanStarted(category: String, log: OSLog = .disk) {
        os_log(.info, log: log, "Scan started: %{public}@", category)
    }

    static func scanCompleted(category: String, fileCount: Int, totalSize: UInt64, log: OSLog = .disk) {
        os_log(.info, log: log, "Scan completed: %{public}@, files: %d, size: %llu", category, fileCount, totalSize)
    }

    static func cleanupStarted(fileCount: Int, log: OSLog = .disk) {
        os_log(.info, log: log, "Cleanup started: %d files", fileCount)
    }

    static func cleanupCompleted(size: UInt64, log: OSLog = .disk) {
        os_log(.info, log: log, "Cleanup completed: freed %llu bytes", size)
    }

    // MARK: 内存清理专用日志

    static func memoryPurged(before: UInt64, after: UInt64, freed: UInt64, log: OSLog = .memory) {
        os_log(.info, log: log, "Memory purged: before=%llu, after=%llu, freed=%llu", before, after, freed)
    }
}

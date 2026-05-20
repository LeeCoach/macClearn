import Foundation
import os.log

extension OSLog {
    static let app = OSLog(subsystem: "com.maccleaner.app", category: "App")
    static let disk = OSLog(subsystem: "com.maccleaner.app", category: "Disk")
    static let memory = OSLog(subsystem: "com.maccleaner.app", category: "Memory")
    static let permission = OSLog(subsystem: "com.maccleaner.app", category: "Permission")
    static let uninstaller = OSLog(subsystem: "com.maccleaner.app", category: "Uninstaller")
}

struct AppLogger {
    static func debug(_ message: String, log: OSLog = .app) {
        os_log(.debug, log: log, "%{public}@", message)
    }
    
    static func info(_ message: String, log: OSLog = .app) {
        os_log(.info, log: log, "%{public}@", message)
    }
    
    static func error(_ message: String, log: OSLog = .app) {
        os_log(.error, log: log, "%{public}@", message)
    }
    
    static func error(_ error: Error, context: String = "", log: OSLog = .app) {
        let message = context.isEmpty ? error.localizedDescription : "\(context): \(error.localizedDescription)"
        os_log(.error, log: log, "%{public}@", message)
    }
    
    static func fault(_ message: String, log: OSLog = .app) {
        os_log(.fault, log: log, "%{public}@", message)
    }
    
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
    
    static func memoryPurged(before: UInt64, after: UInt64, freed: UInt64, log: OSLog = .memory) {
        os_log(.info, log: log, "Memory purged: before=%llu, after=%llu, freed=%llu", before, after, freed)
    }
}

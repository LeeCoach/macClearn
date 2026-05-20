import Foundation
import CoreGraphics

enum Constants {
    enum Scan {
        static let batchFileThreshold = 50
        static let batchTimeThreshold: TimeInterval = 0.3
        static let largeFileThreshold: UInt64 = 100 * 1024 * 1024
        static let maxConcurrentCleanTasks = 12
        static let displayFileLimit = 500
    }
    
    enum Memory {
        static let autoRefreshInterval: TimeInterval = 2.0
        static let purgeTimeout: TimeInterval = 10.0
        static let purgeWaitTime: TimeInterval = 1.0
        static let topProcessesCount = 10
    }
    
    enum UI {
        static let defaultWindowWidth: CGFloat = 960
        static let defaultWindowHeight: CGFloat = 640
        static let animationDuration: TimeInterval = 0.3
        static let autoScanDelay: UInt64 = 800_000_000
    }
    
    enum Settings {
        static let autoRefreshIntervalKey = "autoRefreshInterval"
        static let moveToTrashKey = "moveToTrash"
        static let languageKey = "appLanguage"
        static let defaultAutoRefreshInterval: Double = 3.0
    }
    
    enum App {
        static let bundleIdentifier = "com.maccleaner.app"
        static let appSupportDirectoryName = "MacCleaner"
        static let scanResultsFileName = "MacCleaner_scanResults.json"
    }
}

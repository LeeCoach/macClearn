// ScanResult.swift - 磁盘扫描结果相关数据模型

import Foundation

/// 扫描分类类型，定义可扫描的文件类别
enum ScanCategoryType: String, CaseIterable, Identifiable {
    case caches
    case logs
    case tempFiles
    case trash
    case xcodeCache
    case browserCache
    case largeFiles

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .caches: return "category.caches"
        case .logs: return "category.logs"
        case .tempFiles: return "category.tempFiles"
        case .trash: return "category.trash"
        case .xcodeCache: return "category.xcodeCache"
        case .browserCache: return "category.browserCache"
        case .largeFiles: return "category.largeFiles"
        }
    }

    /// 分类对应的 SF Symbol 图标名称
    var icon: String {
        switch self {
        case .caches: return "archivebox"
        case .logs: return "doc.text"
        case .tempFiles: return "thermometer"
        case .trash: return "trash"
        case .xcodeCache: return "hammer"
        case .browserCache: return "globe"
        case .largeFiles: return "doc.fill"
        }
    }

    /// 该分类是否可一键清理（大文件需用户手动确认）
    var isCleanable: Bool {
        self != .largeFiles
    }
}

/// 扫描分类，包含某类文件的总大小、文件列表及展开状态
struct ScanCategory: Identifiable {
    let id = UUID()
    let categoryType: ScanCategoryType
    let name: String
    let icon: String
    var totalSize: UInt64
    var fileCount: Int
    var files: [ScanFileItem]
    var isExpanded: Bool

    init(categoryType: ScanCategoryType, totalSize: UInt64 = 0, fileCount: Int = 0, files: [ScanFileItem] = [], isExpanded: Bool = false) {
        self.categoryType = categoryType
        self.name = categoryType.titleKey
        self.icon = categoryType.icon
        self.totalSize = totalSize
        self.fileCount = fileCount
        self.files = files
        self.isExpanded = isExpanded
    }

    /// 用于界面展示的文件列表，限制最多 500 条以避免性能问题
    var displayFiles: [ScanFileItem] {
        Array(files.prefix(500))
    }
}

/// 扫描到的单个文件项
struct ScanFileItem: Identifiable {
    let id = UUID()
    let url: URL
    let size: UInt64
    let isProtected: Bool
}

/// 将字节数格式化为人类可读的大小字符串（如 "1.5 GB"）
func formatSize(_ bytes: UInt64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = Double(bytes)
    var unitIndex = 0
    while value >= 1024 && unitIndex < units.count - 1 {
        value /= 1024
        unitIndex += 1
    }
    return String(format: "%.1f %@", value, units[unitIndex])
}

// ScanResult.swift - 磁盘扫描结果相关数据模型

import Foundation

/// 扫描分类类型，定义可扫描的文件类别
enum ScanCategoryType: String, CaseIterable, Identifiable, Codable {
    case caches
    case logs
    case tempFiles
    case trash
    case downloads
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
        case .downloads: return "category.downloads"
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
        case .downloads: return "arrow.down.circle"
        case .xcodeCache: return "hammer"
        case .browserCache: return "globe"
        case .largeFiles: return "doc.fill"
        }
    }

    /// 该分类是否可清理
    var isCleanable: Bool {
        true
    }
}

/// 扫描分类，包含某类文件的总大小、文件列表及展开状态
struct ScanCategory: Identifiable, Codable {
    var id: String { categoryType.rawValue }
    let categoryType: ScanCategoryType
    var totalSize: UInt64
    var fileCount: Int
    var files: [ScanFileItem]
    var scannedAt: Date?
    /// 扫描是否被截断（超过 maxFilesToScanPerCategory 后截断）
    var isTruncated: Bool = false

    var name: String { categoryType.titleKey }
    var icon: String { categoryType.icon }
    var isExpanded: Bool = false

    private enum CodingKeys: String, CodingKey {
        case categoryType, totalSize, fileCount, files, scannedAt, isTruncated
    }

    init(categoryType: ScanCategoryType, totalSize: UInt64 = 0, fileCount: Int = 0, files: [ScanFileItem] = [], scannedAt: Date? = nil, isTruncated: Bool = false, isExpanded: Bool = false) {
        self.categoryType = categoryType
        self.totalSize = totalSize
        self.fileCount = fileCount
        self.files = files
        self.scannedAt = scannedAt
        self.isTruncated = isTruncated
        self.isExpanded = isExpanded
    }

    /// 用于界面展示的文件列表，限制最多 500 条以避免性能问题
    var displayFiles: [ScanFileItem] {
        Array(files.prefix(500))
    }
}

/// 扫描到的单个文件项
struct ScanFileItem: Identifiable, Codable {
    var id: URL { url }
    let url: URL
    let size: UInt64
    let isProtected: Bool
    let isDirectory: Bool

    private enum CodingKeys: String, CodingKey {
        case url, size, isProtected, isDirectory
    }

    init(url: URL, size: UInt64, isProtected: Bool, isDirectory: Bool = false) {
        self.url = url
        self.size = size
        self.isProtected = isProtected
        self.isDirectory = isDirectory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(URL.self, forKey: .url)
        size = try container.decode(UInt64.self, forKey: .size)
        isProtected = try container.decode(Bool.self, forKey: .isProtected)
        isDirectory = try container.decodeIfPresent(Bool.self, forKey: .isDirectory) ?? false
    }
}

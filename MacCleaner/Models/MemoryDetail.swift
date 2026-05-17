// MemoryDetail.swift - 内存使用详情数据模型

import Foundation

/// 内存使用详情，按类别细分物理内存占用
struct MemoryDetail {
    var active: UInt64
    var inactive: UInt64
    var wired: UInt64
    var compressed: UInt64
    var free: UInt64

    /// 物理内存总量，由各分类求和得出
    var total: UInt64 {
        active + inactive + wired + compressed + free
    }
}

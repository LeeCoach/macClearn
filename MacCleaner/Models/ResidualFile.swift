// ResidualFile.swift - 应用残留文件数据模型

import Foundation

/// 应用卸载后的残留文件，用于展示和清理卸载遗留文件
struct ResidualFile: Identifiable {
    let id: URL
    let url: URL
    let name: String
    let size: UInt64
    let isProtected: Bool
}

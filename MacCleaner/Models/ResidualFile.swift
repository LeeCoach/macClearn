//
// ResidualFile.swift
// MacCleaner
//
//  应用卸载时发现的残留文件模型。用于 UninstallerView 中展示
//  卸载某个应用后在 ~/Library 各子目录中遗留的缓存/偏好设置等文件。
//
//  搜索路径覆盖（详见 AppUninstaller.scanResidualFiles）：
//    - Application Support / Caches / Preferences / Logs
//    - Containers / Group Containers（标记为受保护）
//    - LaunchAgents / Saved Application State / HTTPStorages / WebKit 等
//

import Foundation

/// 单个残留文件或目录。
///
/// - id: 以 url 作为 Identifiable 的唯一标识
/// - isProtected: Containers / Group Containers 下的文件标记为受保护，
///   默认不被勾选，提醒用户谨慎操作（这些目录可能包含共享数据）
/// - isSelectedByDefault: 非受保护文件默认勾选，方便一键清理
struct ResidualFile: Identifiable {
    let id: URL
    let url: URL        // 文件的完整路径
    let name: String    // 相对于 Library 的相对路径，如 "Caches/com.example.app"
    let size: UInt64    // 文件/目录的总大小
    let isProtected: Bool  // 是否受保护（共享数据容器）

    var isSelectedByDefault: Bool { !isProtected }
}

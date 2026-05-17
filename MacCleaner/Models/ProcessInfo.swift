// ProcessInfo.swift - 进程信息数据模型

import Foundation

/// 进程信息，用于展示运行中的进程及其内存占用
struct AppProcessInfo: Identifiable {
    var id: Int32 { pid }
    let name: String
    let pid: Int32
    let memoryMB: Double
}

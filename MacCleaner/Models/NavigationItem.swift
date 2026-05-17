// NavigationItem.swift - 侧边栏导航项定义

import SwiftUI

/// 侧边栏导航项，定义应用的主要功能页面
enum NavigationItem: String, CaseIterable, Identifiable {
    case dashboard
    case memory
    case disk
    case uninstaller

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .dashboard: return "nav.dashboard"
        case .memory: return "nav.memory"
        case .disk: return "nav.disk"
        case .uninstaller: return "nav.uninstaller"
        }
    }

    /// 导航项对应的 SF Symbol 图标名称
    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .memory: return "memorychip"
        case .disk: return "internaldrive"
        case .uninstaller: return "trash.circle"
        }
    }

    var subtitleKey: String {
        switch self {
        case .dashboard: return "nav.dashboard.subtitle"
        case .memory: return "nav.memory.subtitle"
        case .disk: return "nav.disk.subtitle"
        case .uninstaller: return "nav.uninstaller.subtitle"
        }
    }
}

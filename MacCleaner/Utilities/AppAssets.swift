//
// AppAssets.swift
// MacCleaner
//
//  应用资源加载工具。提供程序中使用的图片资源的统一加载入口。
//
//  加载链路：
//    1. 优先从 Bundle.main 中查找 SidebarIcon.png
//    2. 回退到系统应用图标 NSImage.applicationIconName
//    3. 最终回退到空白占位图（64×64）
//

import AppKit

/// 应用图片资源枚举。
///
/// 所有图片资源都应通过 AppAssets 加载，避免在业务代码中
/// 直接使用 Bundle.main.url，方便后续迁移到 Asset Catalog。
enum AppAssets {
    /// 侧边栏 Logo 图标（58×58 显示尺寸）
    static var sidebarIcon: NSImage {
        if let resourceURL = Bundle.main.url(forResource: "SidebarIcon", withExtension: "png"),
           let image = NSImage(contentsOf: resourceURL) {
            return image
        }

        // 回退：使用系统应用图标
        if let image = NSImage(named: NSImage.applicationIconName) {
            return image
        }

        // 最终回退：空白占位
        return NSImage(size: NSSize(width: 64, height: 64))
    }
}

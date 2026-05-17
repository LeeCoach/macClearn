// AppAssets.swift - 应用资源加载工具

import AppKit

enum AppAssets {
    static var sidebarIcon: NSImage {
        if let resourceURL = Bundle.main.url(forResource: "SidebarIcon", withExtension: "png"),
           let image = NSImage(contentsOf: resourceURL) {
            return image
        }

        if let image = NSImage(named: NSImage.applicationIconName) {
            return image
        }

        return NSImage(size: NSSize(width: 64, height: 64))
    }
}

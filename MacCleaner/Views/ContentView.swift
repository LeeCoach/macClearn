// ContentView.swift - 应用主界面，负责导航与子视图切换

import SwiftUI

// 主内容视图，包含侧边栏导航和各功能页面
struct ContentView: View {
    @EnvironmentObject private var localization: LocalizationManager
    @State private var selectedItem: NavigationItem = .dashboard
    @StateObject private var permissionManager = PermissionManager()
    @StateObject private var diskScanner = DiskScanner()
    @StateObject private var memoryScanner = MemoryScanner()
    @StateObject private var appUninstaller = AppUninstaller()

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedItem) {
                VStack(spacing: 10) {
                    Image(nsImage: AppAssets.sidebarIcon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 58, height: 58)
                        .shadow(color: Color.accentColor.opacity(0.18), radius: 8, y: 3)
                        .accessibilityHidden(true)

                    VStack(spacing: 2) {
                        Text("MacCleaner")
                            .font(.headline)
                            .fontWeight(.semibold)

                        Text(localization.text("app.tagline"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .listRowSeparator(.hidden)

                ForEach(NavigationItem.allCases) { item in
                    HStack {
                        Label(localization.text(item.titleKey), systemImage: item.icon)

                        Spacer()

                        // 磁盘扫描中显示进度指示器
                        if item == .disk && diskScanner.isScanning {
                            ProgressView()
                                .controlSize(.small)
                        }

                        // 磁盘项显示可清理空间大小
                        if item == .disk && !diskScanner.isScanning && diskScanner.totalCleanableSize > 0 {
                            Text(formatSize(diskScanner.totalCleanableSize))
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .monospacedDigit()
                        }
                    }
                    .tag(item)
                }
            }
            .navigationTitle("MacCleaner")
            .listStyle(.sidebar)
        } detail: {
            // 使用 ZStack 叠加各页面，通过 opacity 控制显示切换
            ZStack {
                DashboardView {
                    selectedItem = .disk
                }
                .opacity(selectedItem == .dashboard ? 1 : 0)

                MemoryView(scanner: memoryScanner)
                    .opacity(selectedItem == .memory ? 1 : 0)

                DiskView(scanner: diskScanner, isActive: selectedItem == .disk)
                    .opacity(selectedItem == .disk ? 1 : 0)

                UninstallerView(viewModel: appUninstaller)
                    .opacity(selectedItem == .uninstaller ? 1 : 0)

                // 磁盘页面缺少权限时显示权限引导遮罩
                if selectedItem == .disk && !permissionManager.hasFullDiskAccess {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()

                    PermissionGuideView(permissionManager: permissionManager)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.regularMaterial)
                }
            }
        }
        .environmentObject(permissionManager)
    }

    // 将字节数格式化为人类可读的大小字符串
    private func formatSize(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0
        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        return String(format: "%.1f%@", value, units[unitIndex])
    }
}

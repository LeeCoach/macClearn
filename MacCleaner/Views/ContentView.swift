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
    @State private var didAutoScan = false

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

                        // 磁盘项显示可清理空间大小（仅在有权限时显示）
                        if item == .disk && permissionManager.hasFullDiskAccess && !diskScanner.isScanning && diskScanner.totalCleanableSize > 0 {
                            Text(ByteFormatter.shared.format(diskScanner.totalCleanableSize, includeSpace: false))
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .monospacedDigit()
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(.orange)
                                )
                        }
                    }
                    .tag(item)
                    .listRowBackground(
                        selectedItem == item
                            ? Color.blue.opacity(0.1)
                            : Color.clear
                    )
                }
            }
            .navigationTitle("MacCleaner")
            .listStyle(.sidebar)
        } detail: {
            // 使用 ZStack 叠加各页面，通过 opacity 控制显示切换
            ZStack {
                DashboardView(diskScanner: diskScanner, memoryScanner: memoryScanner, isActive: selectedItem == .dashboard) {
                    selectedItem = .disk
                    startDiskScanIfNeeded()
                }
                .opacity(selectedItem == .dashboard ? 1 : 0)

                MemoryView(scanner: memoryScanner, isActive: selectedItem == .memory)
                    .opacity(selectedItem == .memory ? 1 : 0)

                DiskView(scanner: diskScanner, isActive: selectedItem == .disk)
                    .opacity(selectedItem == .disk ? 1 : 0)

                UninstallerView(viewModel: appUninstaller)
                    .opacity(selectedItem == .uninstaller ? 1 : 0)

                // 磁盘页面缺少权限且用户尝试操作时显示权限引导遮罩
                if selectedItem == .disk && permissionManager.showPermissionGuide {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()

                    //
                    PermissionGuideView(permissionManager: permissionManager) {
                        startDiskScanIfNeeded()
                    }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.regularMaterial)
                }
            }
        }
        .environmentObject(permissionManager)
        .task {
            if didAutoScan { return }
            didAutoScan = true
            try? await Task.sleep(nanoseconds: Constants.UI.autoScanDelay)
            if permissionManager.hasFullDiskAccess && !diskScanner.isScanning {
                await diskScanner.scanDisk(excludedPaths: permissionManager.excludedPaths)
            }
        }
    }

    private func startDiskScanIfNeeded() {
        guard permissionManager.hasFullDiskAccess else {
            permissionManager.showPermissionGuide = true
            return
        }
        guard !diskScanner.isScanning && !diskScanner.isCleaning else { return }
        Task {
            await diskScanner.scanDisk(excludedPaths: permissionManager.excludedPaths)
        }
    }
}

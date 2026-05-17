// DashboardView.swift - 仪表盘视图，展示系统状态概览与快速操作

import SwiftUI

// 仪表盘主视图，实时展示 CPU、内存、磁盘状态，提供快速清理操作
struct DashboardView: View {
    @EnvironmentObject private var localization: LocalizationManager
    @StateObject private var systemInfo = SystemInfoService()
    @State private var showEmptyTrashConfirmation = false
    // 点击"扫描磁盘"时的回调，用于切换到磁盘页面
    let onScanDisk: () -> Void

    init(onScanDisk: @escaping () -> Void = {}) {
        self.onScanDisk = onScanDisk
    }

    var body: some View {
        ZStack {
            if systemInfo.isLoading {
                loadingView
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        headerSection

                        statusCardsSection

                        cleanableSection

                        quickActionsSection

                        Spacer()
                    }
                    .padding(24)
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            systemInfo.startMonitoring()
        }
        .onDisappear {
            systemInfo.stopMonitoring()
        }
        .alert(localization.text("dashboard.emptyTrash.title"), isPresented: $showEmptyTrashConfirmation) {
            Button(localization.text("common.cancel"), role: .cancel) {}
            Button(localization.text("dashboard.emptyTrash.confirm"), role: .destructive) {
                emptyTrash()
            }
        } message: {
            Text(localization.text("dashboard.emptyTrash.message"))
        }
        .animation(.easeInOut(duration: 0.3), value: systemInfo.isLoading)
    }

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
                .scaleEffect(1.2)

            Text(localization.text("dashboard.loading"))
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(localization.text("dashboard.loading.hint"))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(localization.text("dashboard.title"))
                    .font(.title)
                    .fontWeight(.bold)
                Text(localization.text("dashboard.subtitle"))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // 系统状态卡片网格：CPU、内存、磁盘使用率、可用磁盘空间
    private var statusCardsSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16)
        ], spacing: 16) {
            StatusCard(
                title: localization.text("dashboard.cpu"),
                value: String(format: "%.1f%%", systemInfo.cpuUsage * 100),
                progress: systemInfo.cpuUsage,
                color: cpuColor,
                icon: "cpu"
            )

            StatusCard(
                title: localization.text("dashboard.memory"),
                value: "\(formatBytes(systemInfo.memoryUsed)) / \(formatBytes(systemInfo.memoryTotal))",
                progress: systemInfo.memoryUsage,
                color: memoryColor,
                icon: "memorychip"
            )

            StatusCard(
                title: localization.text("dashboard.disk"),
                value: "\(formatBytes(systemInfo.diskUsed)) / \(formatBytes(systemInfo.diskTotal))",
                progress: systemInfo.diskUsage,
                color: diskColor,
                icon: "internaldrive"
            )

            StatusCard(
                title: localization.text("dashboard.diskFree"),
                value: formatBytes(systemInfo.diskFree),
                progress: systemInfo.diskTotal > 0 ? 1.0 - systemInfo.diskUsage : 0,
                color: .green,
                icon: "externaldrive"
            )
        }
    }

    // 可清理空间估算展示
    private var cleanableSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.orange)
                Text(localization.text("dashboard.cleanable"))
                    .font(.headline)
                Spacer()
                Text(formatBytes(systemInfo.estimatedCleanable))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.orange)
                    .monospacedDigit()
            }

            Text(localization.text("dashboard.cleanable.description"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.orange.opacity(0.3), lineWidth: 1)
        )
    }

    // 快速操作按钮区域
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localization.text("dashboard.quickActions"))
                .font(.headline)

            HStack(spacing: 12) {
                QuickActionButton(
                    title: localization.text("dashboard.cleanMemory"),
                    icon: "memorychip",
                    color: .blue,
                    action: { purgeMemory() }
                )

                QuickActionButton(
                    title: localization.text("dashboard.emptyTrash"),
                    icon: "trash",
                    color: .gray,
                    action: { showEmptyTrashConfirmation = true }
                )

                QuickActionButton(
                    title: localization.text("dashboard.scanDisk"),
                    icon: "magnifyingglass",
                    color: .orange,
                    action: onScanDisk
                )
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
    }

    // CPU 使用率对应的颜色等级
    private var cpuColor: Color {
        if systemInfo.cpuUsage > 0.8 { return .red }
        if systemInfo.cpuUsage > 0.5 { return .orange }
        return .green
    }

    // 内存使用率对应的颜色等级
    private var memoryColor: Color {
        if systemInfo.memoryUsage > 0.8 { return .red }
        if systemInfo.memoryUsage > 0.6 { return .orange }
        return .blue
    }

    // 磁盘使用率对应的颜色等级
    private var diskColor: Color {
        if systemInfo.diskUsage > 0.9 { return .red }
        if systemInfo.diskUsage > 0.75 { return .orange }
        return .purple
    }

    // 调用系统 purge 命令释放内存
    private func purgeMemory() {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/purge")
            try? process.run()
            process.waitUntilExit()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                systemInfo.refresh()
            }
        }
    }

    // 清空废纸篓中的所有文件
    private func emptyTrash() {
        DispatchQueue.global(qos: .userInitiated).async {
            let trashURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")
            if let contents = try? FileManager.default.contentsOfDirectory(
                at: trashURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                for item in contents {
                    try? FileManager.default.removeItem(at: item)
                }
            }
            DispatchQueue.main.async {
                systemInfo.refresh()
            }
        }
    }

    // 将字节数格式化为人类可读的大小字符串
    private func formatBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0
        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        return String(format: "%.1f %@", value, units[unitIndex])
    }
}

// 状态卡片组件，展示单项系统指标的标题、数值和进度条
private struct StatusCard: View {
    let title: String
    let value: String
    let progress: Double
    let color: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(value)
                .font(.body)
                .fontWeight(.semibold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(color)

            Text(String(format: "%.1f%%", progress * 100))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
    }
}

// 快速操作按钮组件
private struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.1)))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

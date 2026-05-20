// MemoryView.swift - 内存清理视图，展示内存详情、进程占用与释放结果

import SwiftUI
import Combine

// 内存条目数据，用于可视化内存各区域占比
private struct MemBar: Identifiable {
    let id = UUID()
    let label: String
    let value: UInt64
    let color: Color
}

// 内存清理主视图
struct MemoryView: View {
    @EnvironmentObject private var localization: LocalizationManager
    @ObservedObject var scanner: MemoryScanner
    let isActive: Bool
    @State private var refreshTimer: AnyCancellable?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection

                if scanner.isScanning || scanner.isPurging {
                    loadingSection
                }

                if let detail = scanner.memoryDetail {
                    memoryDetailSection(detail)
                }

                if !scanner.topProcesses.isEmpty {
                    topProcessesSection
                }

                // 释放内存后展示对比结果
                if let before = scanner.beforeMemory, let after = scanner.afterMemory {
                    purgeResultSection(before: before, after: after)
                }

                Spacer()
            }
            .padding(24)
        }
        .onChange(of: isActive) { active in
            if active {
                startAutoRefresh()
            } else {
                stopAutoRefresh()
            }
        }
        .onAppear {
            if isActive {
                startAutoRefresh()
            }
        }
        .onDisappear {
            stopAutoRefresh()
        }
    }

    private func startAutoRefresh() {
        if scanner.memoryDetail == nil {
            scanner.scanMemory()
        }
        refreshTimer = Timer.publish(every: Constants.Memory.autoRefreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                scanner.refreshQuietly()
            }
    }

    private func stopAutoRefresh() {
        refreshTimer?.cancel()
        refreshTimer = nil
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "memorychip")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)
                Text(localization.text("memory.title"))
                    .font(.title)
                    .fontWeight(.bold)
                Spacer()
            }

            HStack(spacing: 12) {
                Button(action: { scanner.scanMemory() }) {
                    Label(localization.text("memory.scan"), systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .disabled(scanner.isScanning || scanner.isPurging)

                Button(action: { scanner.purgeMemory() }) {
                    Label(localization.text("memory.purge"), systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .disabled(scanner.isScanning || scanner.isPurging || scanner.memoryDetail == nil)

                if scanner.isScanning || scanner.isPurging {
                    Button(action: { scanner.cancelOperation() }) {
                        Label(localization.text("common.cancel"), systemImage: "xmark.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.regular)
                }
            }
        }
    }

    private var loadingSection: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.large)
            Text(scanner.isPurging ? localization.text("memory.purging") : localization.text("memory.scanning"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }

    // 内存详情区域，以条形图展示各内存区域占比
    private func memoryDetailSection(_ detail: MemoryDetail) -> some View {
        let total = detail.total
        let items: [MemBar] = [
            MemBar(label: localization.text("memory.active"), value: detail.active, color: .blue),
            MemBar(label: localization.text("memory.inactive"), value: detail.inactive, color: .orange),
            MemBar(label: localization.text("memory.wired"), value: detail.wired, color: .red),
            MemBar(label: localization.text("memory.compressed"), value: detail.compressed, color: .purple),
            MemBar(label: localization.text("memory.free"), value: detail.free, color: .green)
        ]

        return VStack(alignment: .leading, spacing: 16) {
            Text(localization.text("memory.details"))
                .font(.headline)

            ForEach(items) { item in
                HStack(spacing: 12) {
                    Text(item.label)
                        .frame(width: 50, alignment: .leading)
                        .font(.subheadline)

                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(item.color.opacity(0.8))
                            .frame(
                                width: total > 0
                                    ? geo.size.width * CGFloat(item.value) / CGFloat(total)
                                    : 0,
                                height: 20
                            )
                    }
                    .frame(height: 20)

                    Text(ByteFormatter.shared.format(item.value))
                        .frame(width: 80, alignment: .trailing)
                        .font(.subheadline)
                        .monospacedDigit()
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
    }

    // 内存占用最高的进程列表
    private var topProcessesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localization.text("memory.topProcesses"))
                .font(.headline)

            HStack {
                Text(localization.text("memory.processName"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("PID")
                    .frame(width: 80, alignment: .trailing)
                Text(localization.text("memory.usage"))
                    .frame(width: 100, alignment: .trailing)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Divider()

            ForEach(scanner.topProcesses) { proc in
                HStack {
                    Text(proc.name)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(proc.pid)")
                        .frame(width: 80, alignment: .trailing)
                        .monospacedDigit()
                    Text(String(format: "%.1f MB", proc.memoryMB))
                        .frame(width: 100, alignment: .trailing)
                        .monospacedDigit()
                }
                .font(.subheadline)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
    }

    // 内存释放结果对比展示
    private func purgeResultSection(before: UInt64, after: UInt64) -> some View {
        let freed = after > before ? after - before : 0

        return VStack(spacing: 12) {
            Text(localization.text("memory.result"))
                .font(.headline)

            HStack(spacing: 32) {
                VStack {
                    Text(localization.text("memory.before"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(ByteFormatter.shared.format(before))
                        .font(.title3)
                        .monospacedDigit()
                }

                Image(systemName: "arrow.right")
                    .foregroundStyle(.green)
                    .font(.title3)

                VStack {
                    Text(localization.text("memory.after"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(ByteFormatter.shared.format(after))
                        .font(.title3)
                        .monospacedDigit()
                }
            }

            if freed > 0 {
                Text(localization.text("memory.freed", ByteFormatter.shared.format(freed)))
                    .font(.headline)
                    .foregroundStyle(.green)
            } else {
                Text(localization.text("memory.noExtraFreed"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
    }
}

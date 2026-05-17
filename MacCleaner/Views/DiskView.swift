// DiskView.swift - 磁盘清理视图，提供扫描、选择分类和清理功能

import SwiftUI

// 磁盘清理主视图
struct DiskView: View {
    @ObservedObject var scanner: DiskScanner
    // 当前页面是否处于激活状态，用于触发视图刷新
    var isActive: Bool
    @EnvironmentObject private var permissionManager: PermissionManager
    @EnvironmentObject private var localization: LocalizationManager
    // 用户选中的可清理分类集合
    @State private var selectedCategories: Set<ScanCategoryType> = []
    // 展开的分类集合，控制 DisclosureGroup 的展开/折叠
    @State private var expandedCategories: Set<ScanCategoryType> = []
    @State private var freeSpaceBefore: UInt64 = 0
    @State private var freeSpaceAfter: UInt64 = 0
    @State private var showCleaningResult: Bool = false
    @State private var showCleanConfirmation: Bool = false
    @State private var showExcludedPaths: Bool = false

    // 当前是否正在扫描或清理
    private var isBusy: Bool {
        scanner.isScanning || scanner.isCleaning
    }

    // 过滤出已选中且可清理的分类
    private var selectedCleanableCategories: Set<ScanCategoryType> {
        selectedCategories.filter { $0.isCleanable }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            if scanner.isScanning {
                scanProgressBar
            }

            if scanner.isCleaning {
                cleanProgressBar
            }

            if showCleaningResult {
                cleaningResultCard
            }

            if scanner.scanResults.isEmpty && !scanner.isScanning {
                Spacer()
                emptyState
                Spacer()
            } else {
                resultList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(localization.text("disk.confirm.title"), isPresented: $showCleanConfirmation) {
            Button(localization.text("common.cancel"), role: .cancel) {}
            Button(localization.text("disk.confirm.action"), role: .destructive) {
                performClean()
            }
        } message: {
            let totalSize = scanner.scanResults
                .filter { selectedCleanableCategories.contains($0.categoryType) }
                .reduce(UInt64(0)) { $0 + $1.totalSize }
            Text(localization.text("disk.confirm.message", selectedCleanableCategories.count, formatSize(totalSize)))
        }
        .sheet(isPresented: $showExcludedPaths) {
            ExcludedPathsView(permissionManager: permissionManager)
                .frame(width: 500, height: 400)
        }
        .onChange(of: isActive) { active in
            if active && scanner.isScanning {
                DispatchQueue.main.async {
                    scanner.objectWillChange.send()
                }
            }
        }
        .id(scanner.scanResults.count > 0 || scanner.isScanning ? "disk_has_data" : "disk_empty")
    }

    // 顶部操作栏：扫描、清理、取消、排除列表、可清理空间统计
    private var headerBar: some View {
        HStack(spacing: 16) {
            Button(action: startScan) {
                Label(localization.text("disk.scan"), systemImage: "magnifyingglass")
            }
            .disabled(isBusy)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button(action: { showCleanConfirmation = true }) {
                Label(localization.text("disk.cleanSelected"), systemImage: "trash")
            }
            .disabled(isBusy || selectedCleanableCategories.isEmpty)
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.orange)

            if isBusy {
                Button(action: { scanner.cancelOperation() }) {
                    Label(localization.text("common.cancel"), systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.red)
            }

            Spacer()

            Button(action: { showExcludedPaths = true }) {
                Image(systemName: "list.bullet.rectangle")
                    .help(localization.text("disk.excludedPaths.help"))
            }
            .buttonStyle(.borderless)
            .disabled(isBusy)

            if scanner.totalCleanableSize > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(localization.text("disk.cleanableSpace"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatSize(scanner.totalCleanableSize))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
    }

    // 扫描进度条，显示当前扫描分类和路径
    private var scanProgressBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(localization.text("disk.scanning"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !scanner.currentScanningCategory.isEmpty {
                    Text("- \(localization.text(scanner.currentScanningCategory))")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
                Spacer()
                Text("\(Int(scanner.scanProgress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: scanner.scanProgress)
                .progressViewStyle(.linear)
                .tint(.accentColor)

            if !scanner.currentScanningPath.isEmpty {
                Text(scanner.currentScanningPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private var cleanProgressBar: some View {
        VStack(spacing: 4) {
            ProgressView(value: scanner.cleanProgress) {
                Text(localization.text("disk.cleaning"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .progressViewStyle(.linear)
            .tint(.green)

            Text("\(Int(scanner.cleanProgress * 100))%")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    // 清理结果卡片，对比清理前后的可用空间
    private var cleaningResultCard: some View {
        HStack(spacing: 32) {
            VStack(spacing: 4) {
                Text(localization.text("disk.before"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatSize(freeSpaceBefore))
                    .font(.title3)
                    .fontWeight(.medium)
            }

            Image(systemName: "arrow.right.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)

            VStack(spacing: 4) {
                Text(localization.text("disk.after"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatSize(freeSpaceAfter))
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundStyle(.green)
            }

            Spacer()

            VStack(spacing: 4) {
                Text(localization.text("disk.freed"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatSize(freeSpaceAfter > freeSpaceBefore ? freeSpaceAfter - freeSpaceBefore : 0))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.green)
            }
        }
        .padding(16)
        .background(.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.green.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "internaldrive")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text(localization.text("disk.title"))
                .font(.title)
                .fontWeight(.semibold)
            Text(localization.text("disk.emptyHint"))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // 扫描结果列表，按分类分组展示，支持展开/折叠
    private var resultList: some View {
        List {
            ForEach(scanner.scanResults) { category in
                if category.fileCount > 0 {
                    DisclosureGroup(isExpanded: Binding<Bool>(
                        get: { expandedCategories.contains(category.categoryType) },
                        set: { isExpanded in
                            if isExpanded {
                                expandedCategories.insert(category.categoryType)
                            } else {
                                expandedCategories.remove(category.categoryType)
                            }
                        }
                    )) {
                        ForEach(category.displayFiles) { file in
                            fileRow(file)
                        }

                        // 文件数超过 500 时截断显示
                        if category.files.count > 500 {
                            Text(localization.text("disk.moreFiles", category.files.count - 500))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 28)
                                .padding(.vertical, 4)
                        }
                    } label: {
                        categoryLabel(category)
                    }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    // 分类标签行，包含选择框、图标、名称、文件数和大小
    private func categoryLabel(_ category: ScanCategory) -> some View {
        HStack(spacing: 12) {
            if category.categoryType.isCleanable {
                Button(action: {
                    if selectedCategories.contains(category.categoryType) {
                        selectedCategories.remove(category.categoryType)
                    } else {
                        selectedCategories.insert(category.categoryType)
                    }
                }) {
                    Image(systemName: selectedCategories.contains(category.categoryType) ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .foregroundStyle(selectedCategories.contains(category.categoryType) ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
            } else {
                // 不可清理的分类仅展示查看图标
                Image(systemName: "eye")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .help(localization.text("disk.largeFiles.help"))
            }

            Image(systemName: category.icon)
                .font(.title2)
                .foregroundStyle(categoryColor(category.categoryType))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(localization.text(category.categoryType.titleKey))
                    .font(.body)
                    .fontWeight(.medium)
                Text(localization.text("common.files.count", category.fileCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if category.totalSize > 0 {
                if !category.categoryType.isCleanable {
                    Text(localization.text("disk.viewOnly"))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.12))
                        .foregroundStyle(.secondary)
                        .clipShape(Capsule())
                }

                Text(formatSize(category.totalSize))
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }

    // 单个文件行，展示文件名、路径、受保护标记和大小
    private func fileRow(_ file: ScanFileItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc")
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.url.lastPathComponent)
                    .font(.body)
                    .lineLimit(1)
                Text(file.url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if file.isProtected {
                Text(localization.text("disk.protected"))
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.red.opacity(0.15))
                    .foregroundStyle(.red)
                    .clipShape(Capsule())
            }

            Text(formatSize(file.size))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.leading, 8)
    }

    // 开始扫描磁盘
    private func startScan() {
        showCleaningResult = false
        selectedCategories.removeAll()
        expandedCategories.removeAll()
        Task {
            await scanner.scanDisk(excludedPaths: permissionManager.excludedPaths)
        }
    }

    // 执行清理操作，记录清理前后的可用空间
    private func performClean() {
        freeSpaceBefore = scanner.getFreeDiskSpace()
        showCleaningResult = false
        Task {
            let _ = await scanner.cleanCategories(selectedCleanableCategories, excludedPaths: permissionManager.excludedPaths)
            freeSpaceAfter = scanner.getFreeDiskSpace()
            selectedCategories.removeAll()
            showCleaningResult = true
        }
    }

    // 各扫描分类对应的颜色
    private func categoryColor(_ type: ScanCategoryType) -> Color {
        switch type {
        case .caches: return .blue
        case .logs: return .purple
        case .tempFiles: return .orange
        case .trash: return .gray
        case .xcodeCache: return .cyan
        case .browserCache: return .green
        case .largeFiles: return .red
        }
    }
}

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
    @State private var selectedFiles: Set<URL> = []
    @State private var excludedSelectedFiles: Set<URL> = []
    // 展开的分类集合，控制 DisclosureGroup 的展开/折叠
    @State private var expandedCategories: Set<ScanCategoryType> = []
    @State private var freeSpaceBefore: UInt64 = 0
    @State private var freeSpaceAfter: UInt64 = 0
    @State private var cleanedSize: UInt64 = 0
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

    // 总共选中的文件数（分类全选 + 单独勾选的文件）
    private var totalSelectedFileCount: Int {
        let fromCategories = scanner.scanResults
            .filter { selectedCleanableCategories.contains($0.categoryType) }
            .reduce(0) { count, category in
                count + category.files.filter { !excludedSelectedFiles.contains($0.url) }.count
            }
        let categoryURLs = Set(scanner.scanResults
            .filter { selectedCleanableCategories.contains($0.categoryType) }
            .flatMap { $0.files.map { $0.url } })
        let uniqueIndividual = selectedFiles.subtracting(categoryURLs)
        return fromCategories + uniqueIndividual.count
    }

    private var selectedCategorySummary: (count: Int, size: UInt64) {
        scanner.scanResults
            .filter { selectedCleanableCategories.contains($0.categoryType) }
            .reduce((count: 0, size: UInt64(0))) { partial, category in
                let selectedFiles = category.files.filter { !excludedSelectedFiles.contains($0.url) }
                return (
                    count: partial.count + selectedFiles.count,
                    size: partial.size + selectedFiles.reduce(UInt64(0)) { $0 + $1.size }
                )
            }
    }

    private var selectedIndividualSummary: (count: Int, size: UInt64) {
        let categoryURLs = Set(scanner.scanResults
            .filter { selectedCleanableCategories.contains($0.categoryType) }
            .flatMap { $0.files.map(\.url) })
        return scanner.scanResults
            .flatMap(\.files)
            .filter { selectedFiles.contains($0.url) && !categoryURLs.contains($0.url) }
            .reduce((count: 0, size: UInt64(0))) { partial, file in
                (count: partial.count + 1, size: partial.size + file.size)
            }
    }

    private var scanSummaryText: String? {
        guard let date = scanner.lastScanDate else { return nil }
        return localization.text("disk.lastScan", date.formatted(date: .abbreviated, time: .shortened))
    }

    private var hasVisibleResults: Bool {
        scanner.scanResults.contains { $0.fileCount > 0 }
    }

    // 是否可以执行清理
    private var canClean: Bool {
        !selectedCleanableCategories.isEmpty || !selectedFiles.isEmpty
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

            if !scanner.hasCompletedScan && scanner.scanResults.isEmpty && !scanner.isScanning {
                Spacer()
                emptyState
                Spacer()
            } else if scanner.hasCompletedScan && !scanner.isScanning && !hasVisibleResults {
                Spacer()
                cleanState
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
            let categorySummary = selectedCategorySummary
            let individualSummary = selectedIndividualSummary
            let trashCount = selectedCleanableCategories.contains(.trash)
                ? scanner.scanResults.first { $0.categoryType == .trash }?.fileCount ?? 0
                : selectedFiles.filter { parentCategoryType(for: $0) == .trash }.count
            Text(localization.text(
                "disk.confirm.messageFiles",
                categorySummary.count + individualSummary.count,
                formatSize(categorySummary.size + individualSummary.size),
                trashCount
            ))
        }
        .sheet(isPresented: $showExcludedPaths) {
            ExcludedPathsView(permissionManager: permissionManager)
                .frame(width: 500, height: 400)
        }
        .onChange(of: isActive) { active in
            if active {
                scanner.objectWillChange.send()
            }
        }
    }

    // 顶部操作栏：扫描、清理、排除列表、可清理空间统计
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
            .disabled(!canClean)
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.orange)

            Spacer()

            if let scanSummaryText {
                Text(scanSummaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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

    // 扫描进度条，实时显示文件计数
    private var scanProgressBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(localization.text("disk.scanning"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            ProgressView()
                .progressViewStyle(.linear)
                .tint(.accentColor)

            HStack(spacing: 4) {
                Image(systemName: "doc")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Text(localization.text("disk.scannedFiles", scanner.scannedFileCount))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(action: { scanner.cancelScan() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
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

            HStack(spacing: 6) {
                Text("\(Int(scanner.cleanProgress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: { scanner.cancelClean() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
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
                Text(formatSize(cleanedSize))
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

    private var cleanState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text(localization.text("disk.noResults.title"))
                .font(.title2)
                .fontWeight(.semibold)
            Text(localization.text("disk.noResults.message"))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // 扫描结果列表，按分类分组展示，支持展开/折叠。使用 ScrollView 避免 List 在扫描更新时跳动
    private var resultList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
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
                            LazyVStack(spacing: 0) {
                                ForEach(category.displayFiles) { file in
                                    fileRow(file, categoryType: category.categoryType)
                                        .padding(.horizontal, 12)
                                    Divider()
                                        .padding(.leading, 42)
                                }

                                if category.files.count > 500 {
                                    Text(localization.text("disk.moreFiles", category.files.count - 500))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.leading, 42)
                                        .padding(.vertical, 4)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        } label: {
                            categoryLabel(category)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)

                        Divider()
                    }
                }
            }
        }
    }

    // 分类标签行，包含选择框、图标、名称、文件数和大小
    private func categoryLabel(_ category: ScanCategory) -> some View {
        let isBeingCleaned = scanner.isCleaning && selectedCategories.contains(category.categoryType)

        return HStack(spacing: 12) {
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
                .disabled(isBeingCleaned)
            } else {
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
                HStack(spacing: 4) {
                    Text(localization.text(category.categoryType.titleKey))
                        .font(.body)
                        .fontWeight(.medium)
                    if scanner.activeCategoryTypes.contains(category.categoryType) {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 14, height: 14)
                        Text(localization.text("disk.scanning.category"))
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                }
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
        .opacity(isBeingCleaned ? 0.4 : 1.0)
    }

    // 单个文件行，展示选择框、文件名、路径、受保护标记、大小和定位按钮
    private func fileRow(_ file: ScanFileItem, categoryType: ScanCategoryType) -> some View {
        let isCategorySelected = selectedCleanableCategories.contains(categoryType)
        let isSelected = isCategorySelected ? !excludedSelectedFiles.contains(file.url) : selectedFiles.contains(file.url)
        let isBeingCleaned = scanner.isCleaning && isSelected

        return HStack(spacing: 8) {
            if categoryType.isCleanable {
                Button(action: {
                    if isCategorySelected {
                        if excludedSelectedFiles.contains(file.url) {
                            excludedSelectedFiles.remove(file.url)
                        } else {
                            excludedSelectedFiles.insert(file.url)
                        }
                    } else if isSelected {
                        selectedFiles.remove(file.url)
                    } else {
                        selectedFiles.insert(file.url)
                    }
                }) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 14))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(isBeingCleaned)
            }

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

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            } label: {
                Image(systemName: "arrowshape.turn.up.right.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isBeingCleaned)
            .help(localization.text("disk.revealInFinder"))
        }
        .padding(.leading, 8)
        .opacity(isBeingCleaned ? 0.4 : 1.0)
    }

    // 开始扫描磁盘
    private func startScan() {
        if !permissionManager.hasFullDiskAccess {
            permissionManager.showPermissionGuide = true
            return
        }
        showCleaningResult = false
        cleanedSize = 0
        selectedCategories.removeAll()
        selectedFiles.removeAll()
        excludedSelectedFiles.removeAll()
        expandedCategories.removeAll()
        Task {
            await scanner.scanDisk(excludedPaths: permissionManager.excludedPaths)
        }
    }

    // 执行清理操作，与扫描独立并发，不相互阻塞
    private func performClean() {
        if !permissionManager.hasFullDiskAccess {
            permissionManager.showPermissionGuide = true
            return
        }
        freeSpaceBefore = scanner.getFreeDiskSpace()
        showCleaningResult = false
        let categorySnapshots = scanner.scanResults
        let categoriesToCollect = selectedCleanableCategories
        let individualFiles = selectedFiles
        let excludedFiles = excludedSelectedFiles
        let categoriesToRemove: Set<ScanCategoryType> = []
        let excluded = permissionManager.excludedPaths
        Task.detached(priority: .userInitiated) {
            let categoryFiles = categorySnapshots
                .filter { categoriesToCollect.contains($0.categoryType) }
                .flatMap { category in
                    category.files
                        .map(\.url)
                        .filter { !excludedFiles.contains($0) }
                }
            let filesToRemove = Set(categoryFiles).union(individualFiles)
            let size = await self.scanner.cleanCategories(categoriesToRemove, selectedFiles: filesToRemove, excludedPaths: excluded)
            await MainActor.run {
                self.cleanedSize = size
                self.freeSpaceAfter = self.scanner.getFreeDiskSpace()
                self.selectedCategories.removeAll()
                self.selectedFiles.removeAll()
                self.excludedSelectedFiles.removeAll()
                self.showCleaningResult = true
            }
        }
    }

    private func parentCategoryType(for url: URL) -> ScanCategoryType? {
        scanner.scanResults.first { category in
            category.files.contains { $0.url == url }
        }?.categoryType
    }

    // 各扫描分类对应的颜色
    private func categoryColor(_ type: ScanCategoryType) -> Color {
        switch type {
        case .caches: return .blue
        case .logs: return .purple
        case .tempFiles: return .orange
        case .trash: return .gray
        case .downloads: return .brown
        case .xcodeCache: return .cyan
        case .browserCache: return .green
        case .largeFiles: return .red
        }
    }
}

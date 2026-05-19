// UninstallerView.swift - 应用卸载视图，支持搜索、单个/批量卸载及残留文件清理

import SwiftUI

enum UninstallerMode: String, CaseIterable {
    case installedApps
    case orphanResiduals
}

// 应用卸载主视图
struct UninstallerView: View {
    @ObservedObject var viewModel: AppUninstaller
    @EnvironmentObject private var localization: LocalizationManager
    @State private var searchText = ""
    @State private var showResidualSheet = false
    @State private var showBatchSheet = false
    @State private var showOrphanCleanSheet = false
    @State private var selectedAppForUninstall: InstalledApp?
    @State private var residualFiles: [ResidualFile] = []
    @State private var batchResidualFiles: [ResidualFile] = []
    @State private var selectedResidualFiles: Set<URL> = []
    @State private var selectedBatchResidualFiles: Set<URL> = []
    @State private var displayMode: UninstallerMode = .installedApps

    // 根据搜索文本过滤应用列表
    private var displayedApps: [InstalledApp] {
        if searchText.isEmpty {
            return viewModel.installedApps
        }
        return viewModel.installedApps.filter {
            fuzzyMatch(query: searchText, target: $0.name) ||
            fuzzyMatch(query: searchText, target: $0.bundleID)
        }
    }

    // 模糊匹配：支持子串匹配和字符顺序匹配
    private func fuzzyMatch(query: String, target: String) -> Bool {
        let queryLower = query.lowercased()
        let targetLower = target.lowercased()

        if targetLower.contains(queryLower) {
            return true
        }

        var queryIdx = queryLower.startIndex
        var targetIdx = targetLower.startIndex

        while queryIdx < queryLower.endIndex && targetIdx < targetLower.endIndex {
            if queryLower[queryIdx] == targetLower[targetIdx] {
                queryIdx = queryLower.index(after: queryIdx)
            }
            targetIdx = targetLower.index(after: targetIdx)
        }

        return queryIdx == queryLower.endIndex
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if displayMode == .installedApps {
                if viewModel.isScanning {
                    scanningView
                } else if viewModel.installedApps.isEmpty {
                    emptyView
                } else {
                    appList
                }

                if !viewModel.selectedApps.isEmpty {
                    batchBar
                }
            } else {
                if viewModel.isScanningOrphans {
                    scanningOrphansView
                } else if viewModel.orphanResiduals.isEmpty {
                    emptyOrphansView
                } else {
                    orphanResidualsList
                }

                if !viewModel.selectedOrphanResiduals.isEmpty && !viewModel.isScanningOrphans {
                    orphanBatchBar
                }
            }
        }
        .onAppear {
            if viewModel.installedApps.isEmpty {
                viewModel.scanApplications()
            }
        }
        .onChange(of: displayMode) { newMode in
            if newMode == .orphanResiduals && viewModel.orphanResiduals.isEmpty && !viewModel.isScanningOrphans {
                if viewModel.installedApps.isEmpty {
                    viewModel.scanApplications()
                } else {
                    viewModel.scanOrphanResiduals()
                }
            }
        }
        .sheet(isPresented: $showResidualSheet) {
            if let app = selectedAppForUninstall {
                residualSheet(for: app)
            }
        }
        .sheet(isPresented: $showBatchSheet) {
            batchResidualSheet
        }
        .sheet(isPresented: $showOrphanCleanSheet) {
            orphanCleanSheet
        }
        .overlay {
            if viewModel.isUninstalling {
                uninstallingOverlay
            }
        }
    }

    private var headerBar: some View {
        HStack {
            Text(localization.text("uninstaller.title"))
                .font(.title2)
                .fontWeight(.semibold)
            Picker("", selection: $displayMode) {
                Text(localization.text("uninstaller.mode.installed")).tag(UninstallerMode.installedApps)
                Text(localization.text("uninstaller.mode.orphan")).tag(UninstallerMode.orphanResiduals)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            Spacer()
            if displayMode == .installedApps {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(localization.text("uninstaller.search"), text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 200)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.separator, lineWidth: 1)
                }
            }

            Button {
                if displayMode == .installedApps {
                    viewModel.scanApplications()
                } else {
                    viewModel.scanOrphanResiduals()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.isScanning || viewModel.isScanningOrphans)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var scanningView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text(localization.text("uninstaller.scanning"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "app.dashed")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(localization.text("uninstaller.empty"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // 应用列表，支持多选和右键菜单
    private var appList: some View {
        List(displayedApps) { app in
            HStack(spacing: 12) {
                Button {
                    toggleSelection(for: app)
                } label: {
                    Image(systemName: viewModel.selectedApps.contains(app.id) ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .foregroundStyle(viewModel.selectedApps.contains(app.id) ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)

                if let icon = app.icon {
                    Image(nsImage: icon)
                        .frame(width: 40, height: 40)
                } else {
                    Image(systemName: "app")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .fontWeight(.medium)
                    Text(app.detailText(localization: localization))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(app.formattedSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let date = app.lastAccessed {
                        Text(dateFormatter.string(from: date))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Button {
                    let residuals = viewModel.scanResidualFiles(for: app)
                    residualFiles = residuals
                    selectedResidualFiles = Set(residuals.filter(\.isSelectedByDefault).map(\.id))
                    selectedAppForUninstall = app
                    showResidualSheet = true
                } label: {
                    Text(localization.text("uninstaller.uninstall"))
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            }
            .padding(.vertical, 4)
            .contextMenu {
                Button {
                    toggleSelection(for: app)
                } label: {
                    Text(viewModel.selectedApps.contains(app.id) ? localization.text("uninstaller.deselect") : localization.text("uninstaller.select"))
                }

                Button {
                    let residuals = viewModel.scanResidualFiles(for: app)
                    residualFiles = residuals
                    selectedResidualFiles = Set(residuals.filter(\.isSelectedByDefault).map(\.id))
                    selectedAppForUninstall = app
                    showResidualSheet = true
                } label: {
                    Text(localization.text("uninstaller.uninstallApp"))
                }
            }
        }
        .listStyle(.inset)
    }

    // 切换应用的选中状态
    private func toggleSelection(for app: InstalledApp) {
        if viewModel.selectedApps.contains(app.id) {
            viewModel.selectedApps.remove(app.id)
        } else {
            viewModel.selectedApps.insert(app.id)
        }
    }

    // 底部批量操作栏
    private var batchBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text(localization.text("uninstaller.selected", viewModel.selectedApps.count))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    let apps = viewModel.installedApps.filter { viewModel.selectedApps.contains($0.id) }
                    var allResiduals: [ResidualFile] = []
                    for app in apps {
                        allResiduals.append(contentsOf: viewModel.scanResidualFiles(for: app))
                    }
                    batchResidualFiles = allResiduals
                    selectedBatchResidualFiles = Set(allResiduals.filter(\.isSelectedByDefault).map(\.id))
                    showBatchSheet = true
                } label: {
                    Text(localization.text("uninstaller.batch"))
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

                Button {
                    viewModel.selectedApps.removeAll()
                } label: {
                    Text(localization.text("uninstaller.deselect"))
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // 单个应用卸载确认弹窗，展示残留文件列表
    private func residualSheet(for app: InstalledApp) -> some View {
        VStack(spacing: 16) {
            Text(localization.text("uninstaller.uninstallTitle", app.name))
                .font(.headline)

            if residualFiles.isEmpty {
                Text(localization.text("uninstaller.noResiduals"))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    residualSelectionHeader(
                        files: residualFiles,
                        selectedIDs: $selectedResidualFiles
                    )

                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(residualFiles) { file in
                                residualFileSelectionRow(file, selectedIDs: $selectedResidualFiles)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }

            HStack {
                Button(localization.text("common.cancel")) {
                    showResidualSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button(localization.text("uninstaller.confirm"), role: .destructive) {
                    let selectedResiduals = residualFiles.filter { selectedResidualFiles.contains($0.id) }
                    viewModel.uninstallApp(app, residualFiles: selectedResiduals)
                    showResidualSheet = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 450)
    }

    // 批量卸载确认弹窗，展示所有选中应用的残留文件
    private var batchResidualSheet: some View {
        VStack(spacing: 16) {
            Text(localization.text("uninstaller.batchTitle", viewModel.selectedApps.count))
                .font(.headline)

            if batchResidualFiles.isEmpty {
                Text(localization.text("uninstaller.noResiduals"))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    residualSelectionHeader(
                        files: batchResidualFiles,
                        selectedIDs: $selectedBatchResidualFiles
                    )

                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(batchResidualFiles) { file in
                                residualFileSelectionRow(file, selectedIDs: $selectedBatchResidualFiles)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }

            HStack {
                Button(localization.text("common.cancel")) {
                    showBatchSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button(localization.text("uninstaller.confirmBatch"), role: .destructive) {
                    let apps = viewModel.installedApps.filter { viewModel.selectedApps.contains($0.id) }
                    let selectedResiduals = batchResidualFiles.filter { selectedBatchResidualFiles.contains($0.id) }
                    viewModel.batchUninstall(apps, residualFiles: selectedResiduals)
                    showBatchSheet = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 450)
    }

    private func residualSelectionHeader(files: [ResidualFile], selectedIDs: Binding<Set<URL>>) -> some View {
        HStack {
            Text(localization.text("uninstaller.residualsIntro"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            let allSelected = !files.isEmpty && selectedIDs.wrappedValue.count == files.count
            Button {
                if allSelected {
                    selectedIDs.wrappedValue.removeAll()
                } else {
                    selectedIDs.wrappedValue = Set(files.map(\.id))
                }
            } label: {
                Label(
                    allSelected ? localization.text("uninstaller.deselectAllResiduals") : localization.text("uninstaller.selectAllResiduals"),
                    systemImage: allSelected ? "checkmark.square.fill" : "square"
                )
            }
            .buttonStyle(.plain)
            .disabled(files.isEmpty)
        }
    }

    private func residualFileSelectionRow(_ file: ResidualFile, selectedIDs: Binding<Set<URL>>) -> some View {
        HStack {
            Button {
                if selectedIDs.wrappedValue.contains(file.id) {
                    selectedIDs.wrappedValue.remove(file.id)
                } else {
                    selectedIDs.wrappedValue.insert(file.id)
                }
            } label: {
                Image(systemName: selectedIDs.wrappedValue.contains(file.id) ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(selectedIDs.wrappedValue.contains(file.id) ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)

            Image(systemName: file.isProtected ? "lock.fill" : "doc")
                .foregroundStyle(file.isProtected ? .orange : .secondary)
                .frame(width: 16)
            Text(file.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // 卸载/清理进行中的遮罩层
    private var uninstallingOverlay: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)
                if let app = viewModel.currentUninstallApp {
                    Text(localization.text("uninstaller.uninstallingApp", app.name))
                        .font(.subheadline)
                } else if displayMode == .orphanResiduals {
                    Text(localization.text("uninstaller.cleaning"))
                        .font(.subheadline)
                } else {
                    Text(localization.text("uninstaller.uninstalling"))
                        .font(.subheadline)
                }
            }
            .padding(24)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var scanningOrphansView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text(localization.text("uninstaller.scanningOrphans"))
                .foregroundStyle(.secondary)
            if !viewModel.currentOrphanScanPath.isEmpty {
                Text(localization.text("uninstaller.scanningPath", viewModel.currentOrphanScanPath))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospaced()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyOrphansView: some View {
        VStack(spacing: 12) {
            Image(systemName: "trash.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(localization.text("uninstaller.orphansEmpty"))
                .foregroundStyle(.secondary)
            Button {
                viewModel.scanOrphanResiduals()
            } label: {
                Text(localization.text("uninstaller.scanOrphans"))
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isScanningOrphans)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // 孤立残留文件列表
    private var orphanResidualsList: some View {
        List(viewModel.orphanResiduals) { file in
            HStack(spacing: 12) {
                Button {
                    if viewModel.selectedOrphanResiduals.contains(file.id) {
                        viewModel.selectedOrphanResiduals.remove(file.id)
                    } else {
                        viewModel.selectedOrphanResiduals.insert(file.id)
                    }
                } label: {
                    Image(systemName: viewModel.selectedOrphanResiduals.contains(file.id) ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .foregroundStyle(viewModel.selectedOrphanResiduals.contains(file.id) ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)

                Image(systemName: file.isProtected ? "lock.fill" : "doc")
                    .foregroundStyle(file.isProtected ? .orange : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .fontWeight(.medium)
                    Text(localization.text("uninstaller.orphanHint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    viewModel.selectedOrphanResiduals = [file.id]
                    showOrphanCleanSheet = true
                } label: {
                    Text(localization.text("uninstaller.clean"))
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
            }
            .padding(.vertical, 4)
        }
        .listStyle(.inset)
    }

    // 孤立残留底部批量操作栏
    private var orphanBatchBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                let totalSize = viewModel.orphanResiduals
                    .filter { viewModel.selectedOrphanResiduals.contains($0.id) }
                    .reduce(0) { $0 + $1.size }
                Text(localization.text("uninstaller.orphansSelected", viewModel.selectedOrphanResiduals.count, ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showOrphanCleanSheet = true
                } label: {
                    Text(localization.text("uninstaller.cleanSelected"))
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                Button {
                    viewModel.selectedOrphanResiduals.removeAll()
                } label: {
                    Text(localization.text("uninstaller.deselect"))
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // 孤立残留清理确认弹窗
    private var orphanCleanSheet: some View {
        VStack(spacing: 16) {
            Text(localization.text("uninstaller.orphanCleanTitle"))
                .font(.headline)

            let selected = viewModel.orphanResiduals.filter { viewModel.selectedOrphanResiduals.contains($0.id) }
            let totalSize = selected.reduce(0) { $0 + $1.size }

            VStack(alignment: .leading, spacing: 8) {
                Text(localization.text("uninstaller.orphanCleanMessage", selected.count, ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(selected) { file in
                            HStack {
                                Image(systemName: file.isProtected ? "lock.fill" : "doc")
                                    .foregroundStyle(file.isProtected ? .orange : .secondary)
                                    .frame(width: 16)
                                Text(file.name)
                                    .font(.caption)
                                Spacer()
                                Text(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
            }

            HStack {
                Button(localization.text("common.cancel")) {
                    showOrphanCleanSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button(localization.text("uninstaller.clean"), role: .destructive) {
                    viewModel.cleanOrphanResiduals(selected)
                    showOrphanCleanSheet = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 450)
    }

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }
}

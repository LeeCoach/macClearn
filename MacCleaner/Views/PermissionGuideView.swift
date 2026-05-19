// PermissionGuideView.swift - 权限引导视图，引导用户授予完全磁盘访问权限；排除路径管理视图

import AppKit
import SwiftUI

// 完全磁盘访问权限引导视图，提供操作步骤和权限检测
struct PermissionGuideView: View {
    @ObservedObject var permissionManager: PermissionManager
    @EnvironmentObject private var localization: LocalizationManager

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Spacer()
                Button(action: {
                    permissionManager.hidePermissionGuide()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color(NSColor.controlBackgroundColor)))
                }
                .buttonStyle(.plain)
                .help(localization.text("common.close"))
            }

            Image(systemName: "lock.shield")
                .font(.system(size: 56))
                .foregroundStyle(.orange)

            VStack(spacing: 8) {
                Text(localization.text("permission.title"))
                    .font(.title2)
                    .fontWeight(.bold)

                Text(localization.text("permission.message"))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                stepRow(number: 1, text: localization.text("permission.step1"))
                stepRow(number: 2, text: localization.text("permission.step2"))
                stepRow(number: 3, text: localization.text("permission.step3"))
                stepRow(number: 4, text: localization.text("permission.step4"))
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))

            HStack(spacing: 16) {
                Button(action: {
                    permissionManager.openPrivacySettings()
                }) {
                    Label(localization.text("permission.openSettings"), systemImage: "gear")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: {
                    permissionManager.checkFullDiskAccess()
                }) {
                    Label(localization.text("permission.recheck"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            if permissionManager.hasFullDiskAccess {
                Label(localization.text("permission.granted"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            }
        }
        .padding(32)
        .frame(maxWidth: 500)
    }

    // 步骤行组件，展示编号圆圈和步骤说明
    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }
}

// 排除路径管理视图，用于添加和移除扫描排除路径
struct ExcludedPathsView: View {
    @ObservedObject var permissionManager: PermissionManager
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localization: LocalizationManager
    @State private var newPath = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localization.text("excluded.title"))
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(localization.text("excluded.description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color(NSColor.controlBackgroundColor)))
                }
                .buttonStyle(.plain)
                .help(localization.text("common.close"))
            }

            Group {
                if permissionManager.excludedPaths.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 30))
                            .foregroundStyle(.secondary)

                        Text(localization.text("excluded.empty"))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 150)
                } else {
                    List {
                        ForEach(permissionManager.excludedPaths, id: \.self) { path in
                            HStack(spacing: 10) {
                                Image(systemName: "folder")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18)
                                Text(path)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button(action: {
                                    if let index = permissionManager.excludedPaths.firstIndex(of: path) {
                                        permissionManager.removeExcludedPath(at: index)
                                    }
                                }) {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 150)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))

            HStack {
                TextField(localization.text("excluded.placeholder"), text: $newPath)
                    .textFieldStyle(.roundedBorder)

                Button(localization.text("excluded.chooseFolder")) {
                    chooseFolder()
                }

                Button(localization.text("common.add")) {
                    guard !newPath.isEmpty else { return }
                    permissionManager.addExcludedPath(newPath)
                    newPath = ""
                }
                .disabled(newPath.isEmpty)
            }
        }
        .padding(20)
    }

    // 打开文件夹选择面板，将选中的路径添加到排除列表
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = localization.text("common.choose")

        if panel.runModal() == .OK, let url = panel.url {
            permissionManager.addExcludedPath(url.path)
            newPath = ""
        }
    }
}

// MacCleanerApp.swift - 应用入口与全局配置

import SwiftUI

// 应用代理，处理应用生命周期事件
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {}
}

// 应用主入口，定义主窗口和设置界面
@main
struct MacCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var localization = LocalizationManager()

    var body: some Scene {
        WindowGroup("MacCleaner") {
            ContentView()
                .environmentObject(localization)
        }
        .defaultSize(width: Constants.UI.defaultWindowWidth, height: Constants.UI.defaultWindowHeight)

        Settings {
            SettingsView()
                .environmentObject(localization)
        }
    }
}

// 设置界面，包含通用设置和应用信息
struct SettingsView: View {
    @EnvironmentObject private var localization: LocalizationManager
    // 自动刷新间隔（秒）
    @AppStorage("autoRefreshInterval") var autoRefreshInterval: Double = 3.0
    // 是否将删除的文件移至废纸篓而非永久删除
    @AppStorage("moveToTrash") var moveToTrash: Bool = true

    var body: some View {
        TabView {
            Form {
                Text(localization.text("settings.general"))
                    .font(.headline)

                Picker(localization.text("settings.language"), selection: $localization.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }

                Picker(localization.text("settings.autoRefreshInterval"), selection: $autoRefreshInterval) {
                    Text(localization.text("settings.seconds.3")).tag(3.0)
                    Text(localization.text("settings.seconds.5")).tag(5.0)
                    Text(localization.text("settings.seconds.10")).tag(10.0)
                    Text(localization.text("settings.seconds.30")).tag(30.0)
                }

                Toggle(localization.text("settings.moveToTrash"), isOn: $moveToTrash)
                    .help(localization.text("settings.moveToTrash.help"))
            }
            .padding(20)
            .tabItem {
                Label(localization.text("settings.general.tab"), systemImage: "gear")
            }

            VStack(spacing: 16) {
                Image(nsImage: AppAssets.sidebarIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                Text("MacCleaner")
                    .font(.title)
                    .fontWeight(.bold)
                Text(localization.text("app.tagline"))
                    .foregroundStyle(.secondary)
                Text(localization.text("settings.version", AppVersion.resolvedMarketing))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(localization.text("settings.bundleId", AppInfo.resolvedBundleIdentifier))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tabItem {
                Label(localization.text("settings.about.tab"), systemImage: "info.circle")
            }
        }
        .frame(width: 400, height: 250)
    }
}

# MacCleaner

<p align="center">
  <strong>Lightweight native macOS cleanup utility</strong><br>
  <strong>轻量级 macOS 原生清理工具</strong>
</p>

<p align="center">
  <a href="https://github.com/LeeCoach/macClearn/releases/latest">Download / 下载</a> ·
  <a href="#english">English</a> · <a href="#简体中文">简体中文</a>
</p>

<p align="center">
  <a href="https://github.com/LeeCoach/macClearn/releases/latest"><img src="https://img.shields.io/badge/macOS-13%2B-blue?style=flat-square&logo=apple" alt="macOS 13+"></a>
  <a href="https://github.com/LeeCoach/macClearn/releases/latest"><img src="https://img.shields.io/github/v/release/LeeCoach/macClearn?style=flat-square" alt="Latest release"></a>
</p>

---

## English

### Download

| Item | Link |
|------|------|
| **Latest release** | https://github.com/LeeCoach/macClearn/releases/latest |
| **Installer (DMG)** | [MacCleaner-1.3.0.dmg](https://github.com/LeeCoach/macClearn/releases/download/v1.3.0/MacCleaner-1.3.0.dmg) (~1.0 MB) |
| **All releases** | https://github.com/LeeCoach/macClearn/releases |

> DMG installers are built automatically by GitHub Actions when a version tag (e.g. `v1.3.0`) is pushed. See [Release workflow](#release-workflow).  
> Each DMG contains **MacCleaner.app** and an **Applications** shortcut for drag-and-drop installation.

### Install

1. Download **MacCleaner-1.3.0.dmg** (~1.0 MB) from [Releases](https://github.com/LeeCoach/macClearn/releases/tag/v1.3.0) (or use **Latest** above).
2. Open the DMG, then drag **MacCleaner** into the **Applications** folder shown in the window.
3. Launch MacCleaner from Applications. If macOS shows an unidentified-developer warning, open **System Settings → Privacy & Security** and choose **Open Anyway**.
4. For disk cleanup, grant **Full Disk Access** when prompted (see [Permissions](#permissions) below).

### “App is damaged” after download?

macOS **Gatekeeper** may block unsigned or un-notarized apps downloaded from the internet. The DMG is usually **not** corrupted.

**Fix (pick one):**

```bash
# Remove quarantine flag (adjust path if needed)
xattr -cr ~/Downloads/MacCleaner-1.3.0.dmg
xattr -cr /Applications/MacCleaner.app
```

- **System Settings → Privacy & Security → Open Anyway** (after first launch attempt), or  
- **Right-click** MacCleaner → **Open** the first time.

For distribution without this warning, configure **Developer ID signing + notarization** in GitHub Actions secrets (see [Release workflow](#release-workflow)).

### Overview

**MacCleaner** is a native macOS application built with **Swift** and **SwiftUI**. It helps you monitor system health, free up disk space, release memory pressure, and uninstall applications along with common leftover files—all from a simple sidebar interface.

No third-party dependencies. Minimum system requirement: **macOS 13 (Ventura)**.

### Features

| Module | Description |
|--------|-------------|
| **Dashboard** | Real-time CPU, memory, and disk usage; estimated cleanable space; quick actions (purge memory, empty Trash, jump to disk scan). |
| **Memory** | Memory breakdown (active / inactive / wired / compressed / free); top processes by RAM; one-click `purge` with before/after comparison. |
| **Disk** | Scan caches, logs, temp files, Trash, Xcode data, browser caches, and large files (≥100 MB). Category-based cleanup with confirmation; exclusion list; large files are view-only to reduce accidental deletion. |
| **Uninstaller** | List apps in `/Applications` with icon, size, version, and bundle ID; scan user Library leftovers; single or batch uninstall (moves items to Trash). |

### In-app languages

The UI supports **English**, **Simplified Chinese (中文)**, and **Traditional Chinese (繁體中文)**. Change it under **MacCleaner → Settings → General → Language**.

### Permissions

Disk scanning and deep cleanup require **Full Disk Access**:

1. Open **System Settings → Privacy & Security → Full Disk Access**
2. Enable **MacCleaner**
3. Restart the app and tap **Re-check** on the permission guide if shown

Memory cleanup and app uninstall work without Full Disk Access, but disk scan results may be incomplete.

### Build & run

**Requirements:** Xcode 15+ (or Swift 5.8+ toolchain), macOS 13+

```bash
# Clone or enter the project directory
cd macClearn

# Debug build
swift build

# Run from terminal
swift run MacCleaner

# Release build
swift build -c release
# Binary: .build/release/MacCleaner
```

**Open in Xcode:** open the repository folder in Xcode (Swift Package). Scheme name: `MacCleaner`.

Local packaging (same as CI):

```bash
chmod +x scripts/package-dmg.sh
./scripts/package-dmg.sh
# Output: dist/MacCleaner-<version>.dmg (includes .app and Applications shortcut)
```

### Settings

| Option | Description |
|--------|-------------|
| Language | UI language (EN / 中文 / 繁體中文) |
| Auto-refresh interval | Dashboard polling interval (3 / 5 / 10 / 30 s) |
| Move deleted files to Trash | Prefer Trash over permanent delete when applicable |

### Project structure

```
macClearn/
├── Package.swift              # Swift Package manifest
├── scripts/package-dmg.sh     # Local DMG packaging
├── .github/workflows/build.yml  # Tag-triggered CI release
├── MacCleaner/
│   ├── Version.swift          # Marketing version (keep in sync with Info.plist)
│   ├── App/                   # @main entry, Settings
│   ├── Views/                 # SwiftUI screens
│   ├── Services/              # Scanning, system info, permissions
│   ├── Models/                # Data models & localization
│   ├── Utilities/             # Assets helpers
│   └── Resources/             # App icon asset catalog
└── dist/                      # Release artifacts (.dmg, .app)
```

### Safety notes

- Cleanable files are generally moved to **Trash** (except emptying Trash category).
- **Protected** system paths and user **exclusion list** entries are skipped during scan/clean.
- **Large files** are listed for review only—not bulk-deleted by category.
- Uninstalling apps is irreversible once Trash is emptied; review the residual file list before confirming.

### Tech stack

- Swift 5.8+, SwiftUI, Swift Package Manager
- Platform APIs: `FileManager`, `Process`, Mach VM statistics, `host_statistics64`

### Version

**1.3.0** · Bundle ID: `com.maccleaner.app`

### Release workflow

Pushing a **semver tag** triggers [`.github/workflows/build.yml`](.github/workflows/build.yml) to build, package `MacCleaner-<version>.dmg`, and publish a GitHub Release.

```bash
# 1. Bump version in MacCleaner/Info.plist and MacCleaner/Version.swift
# 2. Commit and push to main
git add MacCleaner/Info.plist MacCleaner/Version.swift README.md
git commit -m "chore: release 1.3.0"
git push origin main

# 3. Create and push tag (must match Info.plist version, prefix with v)
git tag v1.3.0
git push origin v1.3.0
```

After the workflow succeeds, download the DMG from **Releases**. Tag name and `CFBundleShortVersionString` should stay in sync.

**CI signing:** Without GitHub Secrets, the workflow uses **ad-hoc signing** (same as `./scripts/package-dmg.sh`) and still publishes the Release. Optional secrets (`DEVELOPER_ID_APPLICATION`, `APPLE_ID`, etc.) enable Developer ID signing and notarization for Gatekeeper-friendly downloads.

---

## 简体中文

### 下载安装包

| 项目 | 链接 |
|------|------|
| **最新版本** | https://github.com/LeeCoach/macClearn/releases/latest |
| **安装包（DMG）** | [MacCleaner-1.3.0.dmg](https://github.com/LeeCoach/macClearn/releases/download/v1.3.0/MacCleaner-1.3.0.dmg)（约 1.0 MB） |
| **全部版本** | https://github.com/LeeCoach/macClearn/releases |

> 推送版本 tag（如 `v1.3.0`）后，GitHub Actions 会自动构建 DMG 并发布到 Releases。详见 [发布流程](#发布流程)。  
> 安装包内含 **MacCleaner.app** 与 **应用程序（Applications）** 快捷方式，支持拖放安装。

### 安装步骤

1. 从 [Releases](https://github.com/LeeCoach/macClearn/releases/tag/v1.3.0) 下载 **MacCleaner-1.3.0.dmg**（约 1.0 MB，或使用上方的 **Latest**）。
2. 打开镜像，将 **MacCleaner** 拖入窗口中的 **应用程序** 文件夹。
3. 从启动台或应用程序文件夹打开 MacCleaner。若提示「无法验证开发者」，请到 **系统设置 → 隐私与安全性** 选择 **仍要打开**。
4. 使用磁盘清理前，按提示授予 **完全磁盘访问权限**（见下方 [权限说明](#权限说明)）。

### 下载后提示「已损坏」？

多为 macOS **Gatekeeper** 拦截未公证应用，**不是**安装包损坏。

**解决方法（任选其一）：**

```bash
# 清除隔离属性（路径按实际下载位置修改）
xattr -cr ~/Downloads/MacCleaner-1.3.0.dmg
xattr -cr /Applications/MacCleaner.app
```

- **系统设置 → 隐私与安全性 → 仍要打开**（首次尝试打开后出现），或  
- **右键** MacCleaner → **打开**（首次需确认）。

若需用户下载后无此提示，请在 GitHub Actions 中配置 **Developer ID 签名与公证**（见 [发布流程](#发布流程)）。

### 项目简介

**MacCleaner** 是一款使用 **Swift + SwiftUI** 开发的 macOS 原生清理工具。通过侧边栏即可查看系统状态、释放内存、扫描并清理磁盘垃圾，以及卸载应用并清理常见残留文件。

无第三方依赖，最低系统要求：**macOS 13（Ventura）**。

### 功能模块

| 模块 | 说明 |
|------|------|
| **仪表盘** | 实时 CPU、内存、磁盘占用；可清理空间预估；快捷操作（释放内存、清空废纸篓、跳转磁盘扫描）。 |
| **内存清理** | 内存分项（活跃 / 非活跃 / 连线 / 压缩 / 可用）；占用最高的进程列表；一键执行 `purge` 并对比释放前后。 |
| **磁盘清理** | 扫描缓存、日志、临时文件、废纸篓、Xcode 数据、浏览器缓存及大文件（≥100 MB）；按分类勾选清理并确认；支持排除列表；大文件仅展示、不参与一键清理，降低误删风险。 |
| **应用卸载** | 列举 `/Applications` 下应用（图标、大小、版本号、Bundle ID）；扫描用户 Library 残留；支持单个或批量卸载（移至废纸篓）。 |

### 界面语言

应用内支持 **English**、**简体中文**、**繁體中文**。可在 **MacCleaner → 设置 → 通用 → 语言** 中切换。

### 权限说明

磁盘深度扫描与清理需要 **完全磁盘访问权限**：

1. 打开 **系统设置 → 隐私与安全性 → 完全磁盘访问权限**
2. 启用 **MacCleaner**
3. 重启应用；若仍提示未授权，在引导页点击 **重新检测**

内存清理与应用卸载在未授权时仍可使用，但磁盘扫描结果可能不完整。

### 构建与运行

**环境要求：** Xcode 15+（或 Swift 5.8+ 工具链）、macOS 13+

```bash
# 进入项目目录
cd macClearn

# 调试构建
swift build

# 命令行运行
swift run MacCleaner

# 发布构建
swift build -c release
# 可执行文件：.build/release/MacCleaner
```

**使用 Xcode：** 用 Xcode 打开项目根目录（Swift Package），Scheme 名称为 `MacCleaner`。

本地打包（与 CI 相同）：

```bash
chmod +x scripts/package-dmg.sh
./scripts/package-dmg.sh
# 输出：dist/MacCleaner-<版本号>.dmg（内含 .app 与「应用程序」快捷方式）
```

### 设置项

| 选项 | 说明 |
|------|------|
| 语言 | 界面语言（EN / 中文 / 繁體中文） |
| 自动刷新间隔 | 仪表盘刷新周期（3 / 5 / 10 / 30 秒） |
| 删除时移至废纸篓 | 清理时优先移入废纸篓而非直接删除 |

### 项目结构

```
macClearn/
├── Package.swift              # Swift Package 配置
├── scripts/package-dmg.sh     # 本地 DMG 打包脚本
├── .github/workflows/build.yml  # 推送 tag 后自动发布
├── MacCleaner/
│   ├── Version.swift          # 版本号（与 Info.plist 保持一致）
│   ├── App/                   # 应用入口与设置
│   ├── Views/                 # SwiftUI 界面
│   ├── Services/              # 扫描、系统信息、权限
│   ├── Models/                # 数据模型与多语言
│   ├── Utilities/             # 资源辅助
│   └── Resources/             # 应用图标等资源
└── dist/                      # 发布产物（.dmg、.app）
```

### 使用与安全提示

- 可清理文件默认会移入 **废纸篓**（清空废纸篓分类除外）。
- 会跳过 **受保护** 系统路径及用户 **排除列表** 中的路径。
- **大文件** 仅供查看，不会随分类一键删除。
- 卸载应用后若清空废纸篓将无法恢复，请在确认前核对残留文件列表。

### 技术栈

- Swift 5.8+、SwiftUI、Swift Package Manager
- 系统能力：`FileManager`、`Process`、Mach 内存统计、`host_statistics64`

### 版本信息

**1.3.0** · Bundle ID：`com.maccleaner.app`

### 发布流程

向仓库推送 **semver 标签** 后，[`.github/workflows/build.yml`](.github/workflows/build.yml) 会自动编译、打包 `MacCleaner-<版本号>.dmg`，并创建 GitHub Release。

```bash
# 1. 更新 MacCleaner/Info.plist 与 MacCleaner/Version.swift 中的版本号
# 2. 提交并推送到 main
git add MacCleaner/Info.plist MacCleaner/Version.swift README.md
git commit -m "chore: release 1.3.0"
git push origin main

# 3. 创建并推送 tag（须与 Info.plist 一致，前缀 v）
git tag v1.3.0
git push origin v1.3.0
```

工作流完成后，在 **Releases** 页面下载 DMG。tag 名称应与 `CFBundleShortVersionString` 保持一致。

**CI 签名：** 未配置 GitHub Secrets 时，工作流使用 **ad-hoc 签名**（与 `./scripts/package-dmg.sh` 一致），仍会发布 Release。配置 `DEVELOPER_ID_APPLICATION`、`APPLE_ID` 等可选 Secret 后可启用 Developer ID 签名与公证，减少用户端的 Gatekeeper 提示。

---

## License

This project is provided as-is for personal and educational use. Add a license file if you plan to distribute it publicly.

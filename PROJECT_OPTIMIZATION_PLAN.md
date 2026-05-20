
# MacCleaner 项目优化方案

## 1. 项目概述

**MacCleaner** 是一个使用 Swift + SwiftUI 构建的原生 macOS 清理工具。项目整体结构清晰，代码质量良好，但仍有优化空间。

### 项目当前状态
- ✅ 功能完整：仪表盘、内存清理、磁盘清理、应用卸载
- ✅ 多语言支持：英文、简体中文、繁体中文
- ✅ 无第三方依赖
- ✅ 使用了 Swift 并发和现代 SwiftUI 特性
- ⚠️ 存在代码重复和一些可改进的架构设计

---

## 2. 主要问题识别

### 2.1 高优先级问题

#### 问题 A：代码重复 - 字节格式化函数
**影响文件：**
- `ContentView.swift:110-118` - `formatSize`
- `MemoryScanner.swift:223-234` - `formatBytes`
- `DashboardView.swift:310-319` - `formatBytes`

**问题描述：** 三个文件中有基本相同的字节格式化实现。
**风险：** 代码维护成本高，功能升级需要修改多处。
**建议：** 提取为统一的工具类。

---

#### 问题 B：LocalizationManager 职责过重
**影响文件：** `LocalizationManager.swift`

**问题描述：** 该类同时负责：
1. 语言设置管理
2. 文本资源查找
3. 大量硬编码的字符串资源（500+ 行）

**风险：** 文件过大，字符串资源与代码耦合。
**建议：** 使用 `.strings` 文件或 `.lproj` 文件夹管理本地化资源。

---

#### 问题 C：DiskScanner 类过大
**影响文件：** `DiskScanner.swift`（520 行）

**问题描述：** 此类承担了太多职责：
- 扫描调度
- 文件系统操作
- 结果持久化
- 进度跟踪

**风险：** 难以测试和维护，违反单一职责原则。
**建议：** 按功能拆分为多个协作类。

---

### 2.2 中优先级问题

#### 问题 D：缺少依赖注入
**影响文件：** 多处

**问题描述：** View 层直接实例化 Service 层对象（如 `ContentView` 中创建 `PermissionManager`, `DiskScanner` 等）。
**风险：** 难以进行单元测试，组件耦合度高。
**建议：** 引入简单的依赖注入模式。

---

#### 问题 E：错误处理不完善
**影响文件：** `DiskScanner.swift`, `MemoryScanner.swift` 等

**问题描述：** 错误常被静默吞掉（`try?`），没有向用户展示详细错误信息。
**风险：** 调试困难，用户体验不佳。
**建议：** 建立统一的错误处理和报告机制。

---

#### 问题 F：缺少日志系统
**影响文件：** 全局

**问题描述：** 使用 `print()` 进行调试输出，没有结构化日志。
**建议：** 使用 `OSLog` 或自定义轻量级日志系统。

---

### 2.3 低优先级问题

#### 问题 G：缺少单元测试
**影响文件：** 项目中没有测试目录

**建议：** 为核心逻辑添加单元测试。

---

#### 问题 H：魔法数字和字符串
**影响文件：** 多处

**建议：** 提取为常量定义。

---

## 3. 可执行优化方案

### Phase 1: 高优先级优化（核心改进）

#### Task 1.1: 创建统一的 ByteFormatter 工具类

**目标文件：** 创建 `MacCleaner/Utilities/ByteFormatter.swift`

**实施计划：**
```swift
// ByteFormatter.swift
import Foundation

struct ByteFormatter {
    static let shared = ByteFormatter()
    
    private let units = ["B", "KB", "MB", "GB", "TB"]
    
    func format(_ bytes: UInt64, includeSpace: Bool = true) -> String {
        var value = Double(bytes)
        var unitIndex = 0
        
        while value >= 1024 &amp;&amp; unitIndex &lt; units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        
        let space = includeSpace ? " " : ""
        return String(format: "%.1f\(space)%@", value, units[unitIndex])
    }
}
```

**迁移步骤：**
1. 创建新文件
2. 替换三个重复实现
3. 验证功能一致性

---

#### Task 1.2: 重构 LocalizationManager - 第一步（保持兼容）

**短期方案（最小改动）：**
- 保持现有 API 不变
- 将字符串资源提取到单独的扩展文件
- 为未来迁移到 `.strings` 做准备

**文件结构：**
```
MacCleaner/
  Models/
    LocalizationManager.swift        // 核心逻辑
    Localization+Keys.swift          // 键定义（可选）
    Localization+Strings.swift       // 字符串资源
```

---

#### Task 1.3: 拆分 DiskScanner 类

**拆分方案：**

1. **ScanCategoryProvider** - 提供扫描类别配置
2. **FileScanner** - 负责单个类别的文件扫描
3. **ScanResultStore** - 负责结果持久化
4. **CleanupExecutor** - 负责执行清理操作
5. **DiskScanner** (简化版) - 协调整个流程

---

### Phase 2: 中优先级优化（架构改进）

#### Task 2.1: 引入依赖注入容器

**目标：** 解耦组件，便于测试

**实施方案：**
```swift
// MacCleaner/App/DependencyContainer.swift
class DependencyContainer {
    static let shared = DependencyContainer()
    
    private init() {}
    
    // Services
    lazy var diskScanner: DiskScanner = DiskScanner()
    lazy var memoryScanner: MemoryScanner = MemoryScanner()
    lazy var permissionManager: PermissionManager = PermissionManager()
    lazy var appUninstaller: AppUninstaller = AppUninstaller()
    lazy var localization: LocalizationManager = LocalizationManager()
    lazy var systemInfo: SystemInfoService = SystemInfoService()
}
```

---

#### Task 2.2: 建立统一错误处理机制

**目标文件：** 创建 `MacCleaner/Utilities/ErrorHandling.swift`

**实施方案：**
```swift
enum AppError: LocalizedError {
    case scanFailed(String)
    case cleanupFailed(String)
    case permissionDenied
    case fileOperationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .scanFailed(let reason): return "Scan failed: \(reason)"
        // ... 其他 case
        }
    }
}

class ErrorReporter: ObservableObject {
    @Published var currentError: AppError?
    @Published var showErrorAlert = false
    
    func report(_ error: AppError) {
        currentError = error
        showErrorAlert = true
    }
}
```

---

#### Task 2.3: 实现结构化日志

**目标文件：** 创建 `MacCleaner/Utilities/Logger.swift`

**实施方案：**
```swift
import os.log

extension OSLog {
    static let app = OSLog(subsystem: "com.leecoach.maccleaner", category: "App")
    static let disk = OSLog(subsystem: "com.leecoach.maccleaner", category: "Disk")
    static let memory = OSLog(subsystem: "com.leecoach.maccleaner", category: "Memory")
}

struct AppLogger {
    static func debug(_ message: String, log: OSLog = .app) {
        os_log(.debug, log: log, "%@", message)
    }
    
    static func info(_ message: String, log: OSLog = .app) {
        os_log(.info, log: log, "%@", message)
    }
    
    static func error(_ message: String, log: OSLog = .app) {
        os_log(.error, log: log, "%@", message)
    }
}
```

---

### Phase 3: 低优先级优化（质量提升）

#### Task 3.1: 添加单元测试

**目标目录：** 创建 `Tests/` 目录

**测试范围：**
- ByteFormatter 格式化测试
- LocalizationManager 文本查找测试
- DiskScanner 路径排除逻辑测试
- 等等...

---

#### Task 3.2: 提取魔法常量

**目标文件：** 创建 `MacCleaner/Utilities/Constants.swift`

**示例：**
```swift
enum Constants {
    enum Scan {
        static let batchFileThreshold = 50
        static let batchTimeThreshold: TimeInterval = 0.3
        static let largeFileThreshold: UInt64 = 100 * 1024 * 1024 // 100MB
    }
    
    enum Cleanup {
        static let maxConcurrentTasks = 12
    }
    
    enum UI {
        static let defaultWindowWidth: CGFloat = 960
        static let defaultWindowHeight: CGFloat = 640
        static let animationDuration: TimeInterval = 0.3
    }
}
```

---

## 4. 优化实施建议

### 推荐执行顺序

1. **Phase 1 (高优先级)** - 先解决最明显的问题，收益最大
   - Task 1.1 (ByteFormatter) - 最简单，立即可见效果
   - Task 1.2 (LocalizationManager 重构第一步)
   - Task 1.3 (DiskScanner 拆分) - 较大改动，建议单独进行

2. **Phase 2 (中优先级)** - 架构改进，提升可维护性
   - Task 2.1 (依赖注入)
   - Task 2.2 (错误处理)
   - Task 2.3 (日志系统)

3. **Phase 3 (低优先级)** - 锦上添花
   - Task 3.1 (单元测试)
   - Task 3.2 (常量提取)

---

## 5. 风险评估

| 任务 | 风险等级 | 说明 |
|------|---------|------|
| Task 1.1 | 低 | 纯工具类，影响范围小 |
| Task 1.2 | 低 | 保持 API 不变，内部重构 |
| Task 1.3 | 中 | 核心类拆分，需要充分测试 |
| Task 2.1 | 低 | 渐进式改造 |
| Task 2.2 | 中 | 需要配合 UI 改动 |
| Task 2.3 | 低 | 新增功能，不影响现有逻辑 |
| Task 3.1 | 低 | 纯新增测试 |
| Task 3.2 | 低 | 纯重构 |

---

## 6. 总结

该项目整体质量良好，通过上述优化可以：
- 📉 减少约 30% 的重复代码
- 🧪 提高可测试性
- 📚 改善代码可维护性
- 🐛 提升错误处理和用户体验

建议优先实施 Phase 1 的高优先级优化，这些改动风险低、收益大。

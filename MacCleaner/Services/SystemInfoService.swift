// SystemInfoService.swift - 系统信息监控服务，提供内存、磁盘、CPU 使用率及可清理空间估算

import Foundation
import Combine

/// 系统信息监控服务，定时采集内存、磁盘、CPU 等系统指标
class SystemInfoService: ObservableObject {
    @Published var memoryUsage: Double = 0
    @Published var memoryTotal: UInt64 = 0
    @Published var memoryUsed: UInt64 = 0
    @Published var diskUsage: Double = 0
    @Published var diskTotal: UInt64 = 0
    @Published var diskUsed: UInt64 = 0
    @Published var diskFree: UInt64 = 0
    @Published var cpuUsage: Double = 0
    /// 预估可清理的总大小
    @Published var estimatedCleanable: UInt64 = 0
    @Published var isLoading: Bool = true

    private var timer: Timer?

    /// 启动定时监控，每 3 秒刷新一次
    func startMonitoring() {
        isLoading = true
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    /// 刷新所有系统指标
    func refresh() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.readMemoryInfo()
            self.readDiskInfo()
            self.readCPUUsage()
            self.estimateCleanable()

            DispatchQueue.main.async {
                self.isLoading = false
            }
        }
    }

    /// 通过 mach 调用读取虚拟内存统计信息
    private func readMemoryInfo() {
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        // 将 vm_statistics64 指针重绑定为 integer_t 指针以匹配 host_statistics64 的参数类型
        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return }

        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(vmStats.active_count) * pageSize
        let inactive = UInt64(vmStats.inactive_count) * pageSize
        let wired = UInt64(vmStats.wire_count) * pageSize
        let compressed = UInt64(vmStats.compressor_page_count) * pageSize
        let free = UInt64(vmStats.free_count) * pageSize

        // 已使用内存 = 活跃 + 固定 + 压缩（不包含非活跃，因为非活跃可被回收）
        let total = active + inactive + wired + compressed + free
        let used = active + wired + compressed

        DispatchQueue.main.async {
            self.memoryTotal = total
            self.memoryUsed = used
            self.memoryUsage = total > 0 ? Double(used) / Double(total) : 0
        }
    }

    /// 通过文件系统属性读取磁盘使用情况
    private func readDiskInfo() {
        let fm = FileManager.default
        do {
            let attributes = try fm.attributesOfFileSystem(forPath: "/")
            let total = attributes[.systemSize] as? UInt64 ?? 0
            let free = attributes[.systemFreeSize] as? UInt64 ?? 0
            let used = total > free ? total - free : 0

            DispatchQueue.main.async {
                self.diskTotal = total
                self.diskFree = free
                self.diskUsed = used
                self.diskUsage = total > 0 ? Double(used) / Double(total) : 0
            }
        } catch {}
    }

    /// 通过 top 命令获取 CPU 使用率
    private func readCPUUsage() {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/top")
        // -l 1: 只采样一次; -n 0: 不显示进程; -s 0: 无延迟
        process.arguments = ["-l", "1", "-n", "0", "-s", "0"]
        process.standardOutput = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard let output = String(data: data, encoding: .utf8) else { return }

            for line in output.components(separatedBy: "\n") {
                if line.contains("CPU usage:") {
                    // 正则匹配 "CPU usage: X.X% user, Y.Y% sys, Z.Z% idle" 格式
                    let pattern = #"CPU usage:\s+([\d.]+)%\s+user,\s+([\d.]+)%\s+sys,\s+([\d.]+)%\s+idle"#
                    if let regex = try? NSRegularExpression(pattern: pattern),
                       let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                        if let userRange = Range(match.range(at: 1), in: line),
                           let sysRange = Range(match.range(at: 2), in: line),
                           let user = Double(line[userRange]),
                           let sys = Double(line[sysRange]) {
                            DispatchQueue.main.async {
                                self.cpuUsage = (user + sys) / 100.0
                            }
                        }
                    }
                    break
                }
            }
        } catch {}
    }

    /// 估算可清理的缓存、日志、临时文件等总大小
    private func estimateCleanable() {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        var total: UInt64 = 0

        // 常见可清理目录：缓存、日志、临时文件、废纸篓、Xcode 衍生数据、浏览器缓存
        let paths = [
            "\(home)/Library/Caches",
            "\(home)/Library/Logs",
            "/tmp",
            "\(home)/.Trash",
            "\(home)/Library/Developer/Xcode/DerivedData",
            "\(home)/Library/Caches/Google/Chrome",
            "\(home)/Library/Caches/com.apple.Safari",
            "\(home)/Library/Caches/Firefox/Profiles"
        ]

        for path in paths {
            let url = URL(fileURLWithPath: path)
            guard let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let fileURL as URL in enumerator {
                do {
                    let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                    if resourceValues.isDirectory == true { continue }
                    total += UInt64(resourceValues.fileSize ?? 0)
                } catch {
                    continue
                }
            }
        }

        DispatchQueue.main.async {
            self.estimatedCleanable = total
        }
    }

    deinit {
        timer?.invalidate()
    }
}

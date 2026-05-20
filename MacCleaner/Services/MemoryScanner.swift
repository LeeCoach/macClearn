// MemoryScanner.swift - 内存扫描与清理服务，提供内存详情、进程排行及内存释放功能

import Foundation
import Combine

/// 内存扫描器，支持扫描内存详情、获取占用最高的进程、释放内存
class MemoryScanner: ObservableObject {
    /// 内存详细信息（活跃、非活跃、固定、压缩、空闲）
    @Published var memoryDetail: MemoryDetail?
    /// 内存占用最高的前 N 个进程
    @Published var topProcesses: [AppProcessInfo] = []
    @Published var isScanning = false
    @Published var isPurging = false
    /// 释放前的空闲内存
    @Published var beforeMemory: UInt64?
    /// 释放后的空闲内存
    @Published var afterMemory: UInt64?

    private var purgeProcess: Process?
    private var scanWorkItem: DispatchWorkItem?
    private var isCancelled = false

    /// 扫描内存详情和占用最高的进程
    func scanMemory() {
        guard !isScanning else { return }
        isScanning = true
        isCancelled = false

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.isCancelled else { return }
            let detail = self.readMemoryDetail()

            guard !self.isCancelled else { return }
            let processes = self.readTopProcesses()

            guard !self.isCancelled else { return }
            DispatchQueue.main.async {
                self.memoryDetail = detail
                self.topProcesses = processes
                self.isScanning = false
            }
        }
        scanWorkItem = workItem
        DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
    }

    /// 调用系统 purge 命令释放内存，并记录释放前后的空闲内存变化
    func purgeMemory() {
        guard !isPurging else { return }
        isPurging = true
        isCancelled = false
        beforeMemory = memoryDetail?.free
        afterMemory = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let before = self.readMemoryDetail()
            let beforeFree = before?.free ?? 0

            // 调用 /usr/bin/purge 强制清空磁盘缓存，释放内存（带超时保护）
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/purge")
            self.purgeProcess = process

            let semaphore = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in semaphore.signal() }

            do {
                try process.run()
                // purge 有时会卡住（在某些 macOS 版本或权限不足时），设置 10 秒超时
                if semaphore.wait(timeout: .now() + 10) == .timedOut {
                    process.terminate()
                }
            } catch {
                // 进程启动失败，无需等待
            }

            self.purgeProcess = nil

            guard !self.isCancelled else {
                DispatchQueue.main.async {
                    self.isPurging = false
                }
                return
            }

            // 等待 1 秒让系统完成内存回收
            Thread.sleep(forTimeInterval: 1.0)

            guard !self.isCancelled else {
                DispatchQueue.main.async {
                    self.isPurging = false
                }
                return
            }

            let after = self.readMemoryDetail()
            let afterFree = after?.free ?? 0
            let processes = self.readTopProcesses()

            DispatchQueue.main.async {
                self.beforeMemory = beforeFree
                self.afterMemory = afterFree
                self.memoryDetail = after
                self.topProcesses = processes
                self.isPurging = false
                self.purgeProcess = nil
            }
        }
    }

    /// 取消正在进行的扫描或释放操作
    func cancelOperation() {
        isCancelled = true
        scanWorkItem?.cancel()
        scanWorkItem = nil
        purgeProcess?.terminate()
        purgeProcess = nil

        DispatchQueue.main.async { [weak self] in
            self?.isScanning = false
            self?.isPurging = false
        }
    }

    /// 通过 mach 调用读取虚拟内存各分区的详细大小
    private func readMemoryDetail() -> MemoryDetail? {
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        let pageSize = UInt64(vm_kernel_page_size)

        return MemoryDetail(
            active: UInt64(vmStats.active_count) * pageSize,
            inactive: UInt64(vmStats.inactive_count) * pageSize,
            wired: UInt64(vmStats.wire_count) * pageSize,
            compressed: UInt64(vmStats.compressor_page_count) * pageSize,
            free: UInt64(vmStats.free_count) * pageSize
        )
    }

    /// 静默刷新内存数据，不触发 loading 状态，供自动刷新使用
    func refreshQuietly() {
        guard !isScanning && !isPurging else { return }
        isCancelled = false

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.isCancelled else { return }
            let detail = self.readMemoryDetail()

            guard !self.isCancelled else { return }
            let processes = self.readTopProcesses()

            guard !self.isCancelled else { return }
            DispatchQueue.main.async {
                self.memoryDetail = detail
                self.topProcesses = processes
            }
        }
        scanWorkItem = workItem
        DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
    }

    /// 通过 ps aux 命令获取内存占用最高的前 10 个进程
    private func readTopProcesses() -> [AppProcessInfo] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["aux"]
        process.standardOutput = pipe
        let devNull = FileHandle(forUpdatingAtPath: "/dev/null")
        process.standardError = devNull

        do {
            try process.run()

            var outputData = Data()
            let readSemaphore = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .userInteractive).async {
                outputData = pipe.fileHandleForReading.readDataToEndOfFile()
                readSemaphore.signal()
            }

            process.waitUntilExit()
            _ = readSemaphore.wait(timeout: .now() + 5)

            guard let output = String(data: outputData, encoding: .utf8) else { return [] }

            var processes: [AppProcessInfo] = []
            let lines = output.components(separatedBy: "\n")

            // 跳过表头行，解析 ps aux 输出
            for line in lines.dropFirst() {
                let fields = line.split(separator: " ", omittingEmptySubsequences: true)
                guard fields.count >= 11 else { continue }

                guard let pid = Int32(fields[1]) else { continue }
                // RSS（常驻内存）单位为 KB，需转换为 MB
                guard let rss = Double(fields[5]) else { continue }
                let command = fields.dropFirst(10).map(String.init).joined(separator: " ")
                let name = URL(fileURLWithPath: command).lastPathComponent

                let memoryMB = rss / 1024.0
                processes.append(AppProcessInfo(name: name, pid: pid, memoryMB: memoryMB))
            }

            processes.sort { $0.memoryMB > $1.memoryMB }
            return Array(processes.prefix(10))
        } catch {
            return []
        }
    }
}

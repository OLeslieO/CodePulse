import Foundation
import AppKit
import CoreGraphics
import Darwin
import SignalCore

private final class InterruptionFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var interrupted = false
    func cancel() { lock.lock(); interrupted = true; lock.unlock() }
    var cancelled: Bool {
        lock.lock(); defer { lock.unlock() }; return interrupted
    }
}

public enum LEDHardwareTest {
    public static func run(log: (String) -> Void) throws {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "local.codex-signal.app").isEmpty else {
            throw SignalError.io("请先退出 Codex Signal，再运行 led-test，避免同时控灯")
        }
        let flag = InterruptionFlag()
        let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
        let oldInterrupt = signal(SIGINT, SIG_IGN)
        let oldTerminate = signal(SIGTERM, SIG_IGN)
        interrupt.setEventHandler { flag.cancel() }; terminate.setEventHandler { flag.cancel() }
        interrupt.resume(); terminate.resume()
        defer {
            interrupt.cancel(); terminate.cancel()
            signal(SIGINT, oldInterrupt); signal(SIGTERM, oldTerminate)
        }
        let driver = LEDDriver()
        var released = false
        let initialCaps = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
        log("Caps Lock 逻辑状态（开始）：\(initialCaps ? "ON" : "OFF")")
        defer {
            if !released {
                driver.release()
                log(driver.status)
            }
            let finalCaps = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
            log("Caps Lock 逻辑状态（结束）：\(finalCaps ? "ON" : "OFF")")
        }
        try driver.connect()
        log("设备：\(driver.deviceName ?? "Apple 内置键盘")")
        log("初始 LED 报告值：\(driver.readValue().map(String.init) ?? "不可读")（不等于肉眼验证）")

        func check() throws {
            if flag.cancelled { throw SignalError.io("自检已中断，正在释放 LED") }
            guard CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift) == initialCaps else {
                throw SignalError.io("检测到 Caps Lock 逻辑状态变化，已停止测试；若按过按键，请重测")
            }
        }
        func hold(_ value: Bool, seconds: Double) throws {
            try check(); try driver.set(value, force: true)
            let deadline = ProcessInfo.processInfo.systemUptime + seconds
            while ProcessInfo.processInfo.systemUptime < deadline {
                try check(); Thread.sleep(forTimeInterval: 0.05)
            }
        }
        log("现在开始：熄灭 2 秒 → 常亮 3 秒 → 快闪 4 秒 → 熄灭 2 秒")
        log("阶段 1：熄灭")
        try hold(false, seconds: 2)
        log("阶段 2：常亮")
        try hold(true, seconds: 3)
        log("亮灯后的 LED 报告值：\(driver.readValue().map(String.init) ?? "不可读")")
        log("阶段 3：快闪，每 250 ms 翻转一次")
        for step in 0..<16 { try hold(step % 2 == 0, seconds: 0.25) }
        log("阶段 4：熄灭")
        try hold(false, seconds: 2)
        try check()
        let restored = driver.release()
        released = true
        log(driver.status)
        guard restored else { throw SignalError.io("测试序列完成，但恢复系统灯状态失败；请人工检查") }
        try check()
        log("PASS：19 次序列写入及恢复写入成功，采样中未发现 Caps Lock 逻辑状态变化。物理灯效仍需人工确认。")
    }
}

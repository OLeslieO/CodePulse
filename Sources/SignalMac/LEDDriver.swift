import Foundation
import IOKit.hid
import CoreGraphics
import SignalCore

public final class LEDDriver {
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var element: IOHIDElement?
    private var lastValue: Bool?
    public private(set) var status = "LED 未启用"
    public private(set) var deviceName: String?

    public init() {}

    public func connect() throws {
        if device != nil { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                                       kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        var builtInCount = 0
        for candidate in devices {
            guard (IOHIDDeviceGetProperty(candidate, "Built-In" as CFString) as? NSNumber)?.boolValue == true else { continue }
            builtInCount += 1
            guard let elements = IOHIDDeviceCopyMatchingElements(candidate, nil, 0) as? [IOHIDElement] else { continue }
            if let led = elements.first(where: {
                IOHIDElementGetUsagePage($0) == UInt32(kHIDPage_LEDs) &&
                IOHIDElementGetUsage($0) == UInt32(kHIDUsage_LED_CapsLock) &&
                IOHIDElementGetType($0) == kIOHIDElementTypeOutput
            }) {
                let opened = IOHIDDeviceOpen(candidate, IOOptionBits(kIOHIDOptionsTypeNone))
                guard opened == kIOReturnSuccess else {
                    status = "无法打开内置键盘 LED：\(opened) / \(String(format: "0x%08x", UInt32(bitPattern: opened)))"
                    if opened == kIOReturnNotPermitted {
                        status += "；请检查实际运行程序的输入监控授权及运行环境的沙箱限制"
                    }
                    throw SignalError.io(status)
                }
                self.manager = manager
                device = candidate; element = led
                deviceName = IOHIDDeviceGetProperty(candidate, kIOHIDProductKey as CFString) as? String
                status = "内置键盘 LED 已连接"; return
            }
        }
        status = "未找到可直接写入的内置 Caps Lock LED（枚举键盘 \(devices.count)，内置键盘 \(builtInCount)）"
        throw SignalError.io(status)
    }

    public func set(_ on: Bool, force: Bool = false) throws {
        try connect()
        guard force || lastValue != on, let device, let element else { return }
        let value = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, element, 0, on ? 1 : 0)
        let result = IOHIDDeviceSetValue(device, element, value)
        guard result == kIOReturnSuccess else {
            status = "LED 写入失败：\(result) / \(String(format: "0x%08x", UInt32(bitPattern: result)))"
            throw SignalError.io(status)
        }
        lastValue = on
    }

    public func readValue() -> Int? {
        guard let device, let element else { return nil }
        let value = UnsafeMutablePointer<Unmanaged<IOHIDValue>>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard IOHIDDeviceGetValue(device, element, value) == kIOReturnSuccess else { return nil }
        return IOHIDValueGetIntegerValue(value.pointee.takeUnretainedValue())
    }

    @discardableResult public func release() -> Bool {
        var restored = true
        if let device, let element {
            let caps = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
            let value = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, element, 0, caps ? 1 : 0)
            let result = IOHIDDeviceSetValue(device, element, value)
            restored = result == kIOReturnSuccess
            status = result == kIOReturnSuccess ? "已释放 LED，恢复系统状态" : "LED 释放写入失败：\(result)"
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        device = nil; element = nil; lastValue = nil
        deviceName = nil
        manager = nil
        return restored
    }
    deinit { release() }
}

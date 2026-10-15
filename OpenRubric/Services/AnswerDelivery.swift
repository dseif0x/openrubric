import AppKit
import IOKit
import IOKit.graphics
import IOKit.hid
import CoreGraphics
import SwiftUI

/// Delivers answers through hardware and UI channels.
final class AnswerDelivery: ObservableObject {
    static let shared = AnswerDelivery()

    private var currentTask: Task<Void, Never>?
    private var savedScreenBrightness: Double?
    private var hidManager: IOHIDManager?

    // MARK: - Menu bar state (CBT mode)

    class MenuBarIconState: ObservableObject {
        static let shared = MenuBarIconState()
        @Published var currentAnswer: [Int]?
        @Published var isWorking: Bool = false
        @Published var statusText: String = ""
        @Published var lastError: String?

        @MainActor
        func showAnswer(_ answers: [Int]) {
            currentAnswer = answers
            isWorking = false
        }

        @MainActor
        func clear() {
            currentAnswer = nil
            isWorking = false
            statusText = ""
        }
    }

    // MARK: - Public

    func deliver(_ answers: [Int], mode: ExamMode) {
        NSLog("[OpenRubric] Deliver answers \(answers) via \(mode.rawValue)")
        currentTask?.cancel()
        currentTask = Task { @MainActor in
            switch mode {
            case .cbt:
                MenuBarIconState.shared.showAnswer(answers)
            case .capsLock:
                await blinkCapsLock(answers)
            case .keyboardBacklight:
                await pulseBacklight(answers)
            case .flash:
                await flashScreen(answers)
            case .remote:
                break // Remote mode streams into the overlay window
            }
        }
    }

    @MainActor
    func setWorking(_ text: String) {
        MenuBarIconState.shared.isWorking = true
        MenuBarIconState.shared.statusText = text
        MenuBarIconState.shared.lastError = nil
    }

    @MainActor
    func setError(_ message: String) {
        MenuBarIconState.shared.isWorking = false
        MenuBarIconState.shared.lastError = message
    }

    func reset() {
        currentTask?.cancel()
        Task { @MainActor in
            MenuBarIconState.shared.clear()
            restoreScreenBrightness()
        }
    }

    // MARK: - Caps Lock LED via IOHID

    private func setupHIDManager() -> IOHIDManager? {
        if let m = hidManager { return m }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        let result = IOHIDManagerOpen(manager, 0)
        guard result == kIOReturnSuccess else {
            // kIOReturnNotPermitted (0xe00002e2) here means Input Monitoring hasn't been
            // granted — the system logs "TCC deny IOHIDDeviceOpen" alongside this.
            NSLog("[OpenRubric] IOHIDManagerOpen failed (0x\(String(result, radix: 16))) — grant Input Monitoring in Settings → Privacy & Security")
            return nil
        }
        hidManager = manager
        return manager
    }

    private func setCapsLockLED(_ on: Bool) {
        guard let manager = setupHIDManager() else { return }

        // Match keyboard devices (Generic Desktop page, usage 6 = Keyboard)
        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        guard let deviceSet = IOHIDManagerCopyDevices(manager) else { return }
        for device in deviceSet as! Set<IOHIDDevice> {
            guard let elements = IOHIDDeviceCopyMatchingElements(device, nil, 0) as? [IOHIDElement] else { continue }
            for element in elements {
                // LED page (0x08), Caps Lock usage (0x02)
                if IOHIDElementGetUsagePage(element) == kHIDPage_LEDs && IOHIDElementGetUsage(element) == kHIDUsage_LED_CapsLock {
                    let value = IOHIDValueCreateWithIntegerValue(
                        kCFAllocatorDefault, element, 0, on ? 1 : 0
                    )
                    IOHIDDeviceSetValue(device, element, value)
                }
            }
        }
    }

    private func blinkCapsLock(_ answers: [Int]) async {
        NSLog("[OpenRubric] Caps Lock blink starting for \(answers)")
        for answer in answers {
            for _ in 0..<max(answer, 1) {
                guard !Task.isCancelled else { return }
                setCapsLockLED(true)
                try? await Task.sleep(nanoseconds: 400_000_000)
                setCapsLockLED(false)
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    // MARK: - Keyboard backlight via IOKit registry

    private func setKeyboardBacklight(_ level: Double) {
        // AppleHSBacklight service controls the keyboard backlight on MacBooks
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleHSBacklight")
        )
        guard service != 0 else {
            NSLog("[OpenRubric] Keyboard backlight: AppleHSBacklight service not found (not available on Apple Silicon)")
            return
        }
        defer { IOObjectRelease(service) }

        // Read the max from IORegistry to scale properly
        var maxLevel: UInt32 = 0xFFF
        if let maxProp = IORegistryEntryCreateCFProperty(
            service, "MaxBrightness" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? UInt32 {
            maxLevel = maxProp == 0 ? 0xFFF : maxProp
        }

        let target = UInt32(Double(maxLevel) * min(max(level, 0), 1))
        IORegistryEntrySetCFProperty(service, "BrightnessLevel" as CFString, target as CFNumber)
    }

    private func pulseBacklight(_ answers: [Int]) async {
        NSLog("[OpenRubric] Keyboard backlight pulse starting for \(answers)")
        for answer in answers {
            for _ in 0..<max(answer, 1) {
                guard !Task.isCancelled else { return }
                setKeyboardBacklight(1.0)
                try? await Task.sleep(nanoseconds: 300_000_000)
                setKeyboardBacklight(0.05)
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        setKeyboardBacklight(0.3)
    }

    // MARK: - Screen brightness via IOKit display

    // IODisplayConnect (the legacy path below) does not exist on Apple Silicon, so we prefer
    // the private DisplayServices framework, which controls the built-in display's brightness
    // on both Intel and Apple Silicon. It's loaded lazily via dlopen so a missing framework
    // degrades gracefully rather than breaking launch.
    private typealias DSBrightnessSetter = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias DSBrightnessGetter = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32

    private static let displayServices: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    private func displayServicesSetBrightness(_ level: Float) -> Bool {
        guard let handle = Self.displayServices,
              let sym = dlsym(handle, "DisplayServicesSetBrightness") else { return false }
        let fn = unsafeBitCast(sym, to: DSBrightnessSetter.self)
        return fn(CGMainDisplayID(), level) == 0
    }

    private func displayServicesGetBrightness() -> Float? {
        guard let handle = Self.displayServices,
              let sym = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        let fn = unsafeBitCast(sym, to: DSBrightnessGetter.self)
        var level: Float = 0
        return fn(CGMainDisplayID(), &level) == 0 ? level : nil
    }

    private func getScreenBrightness() -> Double {
        if let level = displayServicesGetBrightness() { return Double(level) }

        var iterator: io_iterator_t = 0
        IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator)
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            var level: Float = 0.7
            if IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &level) == kIOReturnSuccess {
                return Double(level)
            }
        }
        NSLog("[OpenRubric] Screen brightness: no readable brightness API, assuming 0.7")
        return 0.7
    }

    private func setScreenBrightness(_ level: Double) {
        let clamped = Float(min(max(level, 0), 1))
        if displayServicesSetBrightness(clamped) { return }

        var iterator: io_iterator_t = 0
        IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator)
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        var applied = false
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            IODisplaySetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, clamped)
            applied = true
        }
        if !applied {
            NSLog("[OpenRubric] Screen brightness: no writable display service found")
        }
    }

    private func flashScreen(_ answers: [Int]) async {
        NSLog("[OpenRubric] Screen flash starting for \(answers)")
        let saved = getScreenBrightness()
        savedScreenBrightness = saved
        // Always restore brightness, even if the task is cancelled mid-flash (e.g. a new
        // trigger), so the screen is never left dimmed.
        defer {
            setScreenBrightness(saved)
            savedScreenBrightness = nil
        }
        for answer in answers {
            for _ in 0..<max(answer, 1) {
                guard !Task.isCancelled else { return }
                setScreenBrightness(1.0)
                try? await Task.sleep(nanoseconds: 300_000_000)
                setScreenBrightness(max(saved - 0.4, 0.0))
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func restoreScreenBrightness() {
        if let saved = savedScreenBrightness {
            setScreenBrightness(saved)
            savedScreenBrightness = nil
        }
    }
}

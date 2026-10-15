import SwiftUI

@main
struct OpenRubricApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var settings = SettingsStore.shared
    @StateObject private var captureCoordinator = CaptureCoordinator.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let _ = HotkeyManager.shared
        let _ = OverlayController.shared

        if SettingsStore.shared.hideDockIcon {
            NSApp.setActivationPolicy(.accessory)
        }

        if !SettingsStore.shared.onboardingCompleted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                OpenRubricWindows.shared.showOnboarding()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        OpenRubricWindows.shared.showSettings()
        return true
    }
}

/// Manages on-demand windows (settings, onboarding).
final class OpenRubricWindows {
    static let shared = OpenRubricWindows()
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?

    /// Opens (or re-focuses) the settings window. Uses a hand-rolled NSWindow instead of
    /// the SwiftUI `Settings` scene so we can (a) bring it to the front in a menu-bar
    /// (.accessory) app and (b) give it a transparent, full-size-content title bar that
    /// matches ContentView's dark full-bleed layout.
    func showSettings() {
        NSApp.activate(ignoringOtherApps: true)

        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "OpenRubric Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1)
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ContentView())
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
    }

    func showOnboarding() {
        guard onboardingWindow == nil else {
            onboardingWindow?.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to OpenRubric"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OnboardingView())
        window.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        onboardingWindow = window
    }

    func closeOnboarding() {
        onboardingWindow?.orderOut(nil)
        onboardingWindow = nil
        SettingsStore.shared.onboardingCompleted = true
    }
}

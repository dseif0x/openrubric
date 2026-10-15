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
            Image(systemName: settings.currentMode.systemImage)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            ContentView()
        }
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

/// Manages on-demand windows (onboarding, answer overlay).
final class OpenRubricWindows {
    static let shared = OpenRubricWindows()
    private var onboardingWindow: NSWindow?

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

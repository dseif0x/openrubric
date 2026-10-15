import SwiftUI

struct ContentView: View {
    @StateObject private var settings = SettingsStore.shared
    @State private var selectedTab: SettingsTab = .provider

    enum SettingsTab: String, CaseIterable, Identifiable {
        case provider = "Provider"
        case mode = "Mode"
        case general = "General"
        case permissions = "Permissions"

        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .provider: "cpu"
            case .mode: "laptopcomputer"
            case .general: "gearshape"
            case .permissions: "lock.shield"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(alignment: .leading, spacing: 0) {
                Text("OpenRubric")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.top, 44)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)

                Text("Local · No account · Your API key")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)

                VStack(spacing: 4) {
                    ForEach(SettingsTab.allCases) { tab in
                        SidebarButton(
                            title: tab.rawValue,
                            symbol: tab.symbol,
                            isSelected: selectedTab == tab
                        ) {
                            selectedTab = tab
                        }
                    }
                }
                .padding(.horizontal, 8)

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("100% local · No telemetry")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
            .frame(width: 200)
            .background(Color(red: 0.13, green: 0.13, blue: 0.14))

            // Content
            Group {
                switch selectedTab {
                case .provider: ProviderConfigView()
                case .mode: ModePickerView()
                case .general: GeneralSettingsView()
                case .permissions: PermissionsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.10, green: 0.10, blue: 0.11))
        }
        .frame(minWidth: 780, minHeight: 540)
        .preferredColorScheme(.dark)
    }
}

struct SidebarButton: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white.opacity(isSelected || isHovered ? 1 : 0.75))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.white.opacity(0.10) : (isHovered ? Color.white.opacity(0.06) : .clear))
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @StateObject private var settings = SettingsStore.shared

    var body: some View {
        SettingsScroll("General") {
            SettingsCard {
                HStack {
                    IconLabel("app.badge", "App version", "Build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")")
                    Spacer()
                }
                .padding(14)
            }

            SectionHeader("Behavior")
                .padding(.top, 24)

            SettingsCard {
                Toggle(isOn: $settings.hideDockIcon) {
                    IconLabel("dock.rectangle", "Hide dock icon", "Runs entirely in the menu bar")
                }
                .toggleStyle(.switch)
                .padding(14)
            }

            SectionHeader("Shortcut")
                .padding(.top, 24)

            SettingsCard {
                HStack {
                    IconLabel("keyboard", "Trigger shortcut", "Point at a question and press to solve")
                    Spacer()
                    ShortcutRecorderView()
                }
                .padding(14)
            }
        }
    }
}

struct ShortcutRecorderView: View {
    @StateObject private var settings = SettingsStore.shared
    @State private var isRecording = false

    var body: some View {
        Group {
            if isRecording {
                Text("Press keys…")
                    .font(.system(size: 12))
                    .foregroundStyle(.yellow)
                    .onAppear { HotkeyManager.shared.unregisterForRecording = true }
                    .onDisappear { HotkeyManager.shared.unregisterForRecording = false }
            } else {
                Button(settings.shortcutString) {
                    isRecording = true
                }
                .buttonStyle(QuietButtonStyle())
            }
        }
        .background(ShortcutRecorder(events: { event in
            guard isRecording else { return nil }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !mods.isEmpty, event.keyCode != 0 else { return nil }

            let keyStr = KeyToString(event.keyCode)
            let combo = "\(ModsToString(mods))\(keyStr)"
            settings.shortcutString = combo
            HotkeyManager.shared.updateShortcut(fromString: combo)
            isRecording = false
            return event
        }))
    }

    private func ModsToString(_ mods: NSEvent.ModifierFlags) -> String {
        var s = ""
        if mods.contains(.command) { s += "⌘" }
        if mods.contains(.option) { s += "⌥" }
        if mods.contains(.shift) { s += "⇧" }
        if mods.contains(.control) { s += "⌃" }
        return s
    }

    private func KeyToString(_ keyCode: UInt16) -> String {
        let map: [UInt16: String] = [
            36: "⏎", 48: "␣", 49: "␣", 53: "⎋",
            18: "1", 19: "2", 20: "3", 21: "4", 22: "5", 23: "6", 24: "7", 25: "8", 26: "9",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        ]
        return map[keyCode] ?? "Key\(keyCode)"
    }
}

/// Captures raw key events while active.
struct ShortcutRecorder: NSViewRepresentable {
    let events: (NSEvent) -> NSEvent?

    func makeNSView(context: Context) -> NSView {
        let view = ShortcutRecorderViewHelper()
        view.eventHandler = events
        DispatchQueue.main.async { view.becomeFirstResponder() }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let helper = nsView as? ShortcutRecorderViewHelper {
            helper.eventHandler = events
        }
    }

    class ShortcutRecorderViewHelper: NSView {
        var eventHandler: ((NSEvent) -> NSEvent?)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            if let handler = eventHandler {
                _ = handler(event)
            }
        }
    }
}

// MARK: - Permissions

struct PermissionsView: View {
    @State private var screenGranted = false
    @State private var accessibilityGranted = false

    var body: some View {
        SettingsScroll("Permissions") {
            SettingsCard {
                VStack(spacing: 0) {
                    PermissionRow(
                        symbol: "rectangle.inset.filled.and.person.filled",
                        title: "Screen Recording",
                        subtitle: "Required to read the question under the pointer.",
                        granted: $screenGranted,
                        openPanel: "ScreenCapture"
                    )
                    Divider().overlay(Color.white.opacity(0.06))
                    PermissionRow(
                        symbol: "accessibility",
                        title: "Accessibility",
                        subtitle: "Required for global keyboard shortcuts.",
                        granted: $accessibilityGranted,
                        openPanel: "Accessibility"
                    )
                }
            }

            SectionHeader("Privacy")
                .padding(.top, 24)

            SettingsCard {
                HStack {
                    IconLabel("lock.shield", "Capture scope", "Only the display containing the pointer is captured.")
                    Spacer()
                }
                .padding(14)
            }

            SettingsCard {
                HStack {
                    IconLabel("eye.slash", "No telemetry", "This app makes exactly one network connection: your configured provider endpoint. Nothing else.")
                    Spacer()
                }
                .padding(14)
            }
            .padding(.top, 12)
        }
        .onAppear {
            checkPermissions()
        }
    }

    private func checkPermissions() {
        screenGranted = CGPreflightScreenCaptureAccess()
        accessibilityGranted = AXIsProcessTrusted()
    }
}

struct PermissionRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    @Binding var granted: Bool
    let openPanel: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer(minLength: 12)
            if granted {
                Label("Allowed", systemImage: "checkmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
            } else {
                Button("Open Settings") {
                    if openPanel == "ScreenCapture" {
                        CGRequestScreenCaptureAccess()
                    } else {
                        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                        NSWorkspace.shared.open(url)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if openPanel == "ScreenCapture" {
                            granted = CGPreflightScreenCaptureAccess()
                        } else {
                            granted = AXIsProcessTrusted()
                        }
                    }
                }
                .buttonStyle(QuietButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 68)
    }
}

// MARK: - Shared components

struct SettingsScroll<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 28)
                content
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.top, 40)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )
    }
}

struct SectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.bottom, 10)
    }
}

struct IconLabel: View {
    let symbol: String
    let title: String
    let subtitle: String

    init(_ symbol: String, _ title: String, _ subtitle: String = "") {
        self.symbol = symbol
        self.title = String(title.split(separator: "\n").first ?? "")
        self.subtitle = subtitle
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .frame(width: 20)
                .foregroundStyle(.white.opacity(0.7))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        QuietButtonBody(configuration: configuration)
    }
}

struct QuietButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.6 : 0.9))
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(Color.white.opacity(bgOpacity))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .onHover { h in isHovered = h }
    }

    private var bgOpacity: Double {
        if configuration.isPressed { return 0.06 }
        if isHovered && isEnabled { return 0.16 }
        return 0.10
    }
}

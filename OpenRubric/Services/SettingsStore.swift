import SwiftUI
import Combine

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard

    @Published var providerBaseURL: String {
        didSet { defaults.set(providerBaseURL, forKey: "provider.baseURL") }
    }
    @Published var apiKey: String {
        didSet { defaults.set(apiKey, forKey: "provider.apiKey") }
    }
    @Published var modelName: String {
        didSet { defaults.set(modelName, forKey: "provider.model") }
    }
    @Published var currentMode: ExamMode {
        didSet { defaults.set(currentMode.rawValue, forKey: "mode.current") }
    }
    @Published var shortcutString: String {
        didSet { defaults.set(shortcutString, forKey: "shortcut.main") }
    }
    @Published var hideDockIcon: Bool {
        didSet {
            defaults.set(hideDockIcon, forKey: "app.hideDock")
            NSApp.setActivationPolicy(hideDockIcon ? .accessory : .regular)
        }
    }
    @Published var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: "app.onboarded") }
    }
    @Published var captureWarmup: Bool {
        didSet { defaults.set(captureWarmup, forKey: "capture.warmup") }
    }

    init() {
        providerBaseURL = defaults.string(forKey: "provider.baseURL") ?? "https://api.openai.com/v1"
        apiKey = defaults.string(forKey: "provider.apiKey") ?? ""
        modelName = defaults.string(forKey: "provider.model") ?? "gpt-4o"
        let modeRaw = defaults.string(forKey: "mode.current") ?? ExamMode.remote.rawValue
        currentMode = ExamMode(rawValue: modeRaw) ?? .remote
        shortcutString = defaults.string(forKey: "shortcut.main") ?? "⌥⏎"
        hideDockIcon = defaults.bool(forKey: "app.hideDock")
        onboardingCompleted = defaults.bool(forKey: "app.onboarded")
        captureWarmup = defaults.bool(forKey: "capture.warmup")
    }

    var isConfigured: Bool {
        !apiKey.isEmpty && !providerBaseURL.isEmpty && !modelName.isEmpty
    }
}

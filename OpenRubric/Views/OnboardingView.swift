import SwiftUI
import IOKit.hid

struct OnboardingView: View {
    @State private var step = 0
    @StateObject private var settings = SettingsStore.shared
    @State private var testStatus: String = ""

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $step) {
                // Step 0: Welcome
                VStack(spacing: 20) {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .padding(.top, 40)

                    Text("OpenRubric")
                        .font(.system(size: 28, weight: .bold))

                    Text("Your local AI exam assistant.\nNo account. No tracking. Your keys, your models.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Spacer()

                    Button("Get Started →") { withAnimation { step = 1 } }
                        .buttonStyle(OnboardButtonStyle())
                        .padding(.bottom, 32)
                }
                .tag(0)

                // Step 1: Provider setup
                VStack(alignment: .leading, spacing: 18) {
                    Text("Connect your AI provider")
                        .font(.system(size: 20, weight: .semibold))
                        .padding(.top, 32)

                    Text("Any OpenAI-compatible endpoint with vision support.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 12) {
                        LabeledField(label: "Base URL", placeholder: "https://api.openai.com/v1", text: $settings.providerBaseURL)
                        LabeledField(label: "API Key", placeholder: "sk-…", text: $settings.apiKey, secure: true)
                        LabeledField(label: "Model", placeholder: "gpt-4o", text: $settings.modelName)
                    }

                    if !testStatus.isEmpty {
                        Text(testStatus)
                            .font(.system(size: 11))
                            .foregroundStyle(testStatus.hasPrefix("✓") ? .green : .orange)
                    }

                    Spacer()

                    HStack {
                        Button("← Back") { withAnimation { step = 0 } }
                            .buttonStyle(OnboardBackButtonStyle())
                        Spacer()
                        Button("Test & Continue →") {
                            Task {
                                testStatus = "Testing…"
                                do {
                                    let r = try await AIService.shared.testConnection()
                                    testStatus = "✓ \(r)"
                                    try? await Task.sleep(nanoseconds: 500_000_000)
                                    await MainActor.run { withAnimation { step = 2 } }
                                } catch {
                                    testStatus = "⚠ \(error.localizedDescription)"
                                }
                            }
                        }
                        .buttonStyle(OnboardButtonStyle())
                    }
                    .padding(.bottom, 32)
                }
                .padding(.horizontal, 40)
                .tag(1)

                // Step 2: Permissions
                VStack(alignment: .leading, spacing: 18) {
                    Text("Grant permissions")
                        .font(.system(size: 20, weight: .semibold))
                        .padding(.top, 32)

                    OnboardPermissionRow(
                        symbol: "camera.viewfinder",
                        title: "Screen Recording",
                        subtitle: "Required to read the question under your cursor."
                    ) {
                        CGRequestScreenCaptureAccess()
                    }

                    OnboardPermissionRow(
                        symbol: "keyboard",
                        title: "Input Monitoring",
                        subtitle: "Optional — only for Caps Lock LED answer delivery."
                    ) {
                        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                            NSWorkspace.shared.open(url)
                        }
                    }

                    Spacer()

                    HStack {
                        Button("← Back") { withAnimation { step = 1 } }
                            .buttonStyle(OnboardBackButtonStyle())
                        Spacer()
                        Button("Finish →") {
                            settings.onboardingCompleted = true
                            OpenRubricWindows.shared.closeOnboarding()
                        }
                        .buttonStyle(OnboardButtonStyle())
                    }
                    .padding(.bottom, 32)
                }
                .padding(.horizontal, 40)
                .tag(2)
            }
            .tabViewStyle(.automatic)
            .frame(width: 520, height: 580)
        }
        .preferredColorScheme(.dark)
    }
}

struct LabeledField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var secure: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Group {
                if secure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 13, design: .monospaced))
        }
    }
}

struct OnboardPermissionRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    let action: () -> Void

    @State private var granted = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button(granted ? "Granted ✓" : "Grant") { action(); checkState() }
                .buttonStyle(OnboardSmallButtonStyle())
                .disabled(granted)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.07)))
        .onAppear { checkState() }
    }

    private func checkState() {
        if title == "Screen Recording" {
            granted = CGPreflightScreenCaptureAccess()
        } else if title == "Input Monitoring" {
            granted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        }
    }
}

struct OnboardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color(red: 0.04, green: 0.52, blue: 1).opacity(configuration.isPressed ? 0.7 : 1))
            )
    }
}

struct OnboardBackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .frame(height: 38)
    }
}

struct OnboardSmallButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

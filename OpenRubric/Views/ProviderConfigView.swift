import SwiftUI

struct ProviderConfigView: View {
    @StateObject private var settings = SettingsStore.shared
    @State private var testStatus: TestStatus = .idle
    @State private var showKey = false

    enum TestStatus: Equatable {
        case idle
        case testing
        case success(String)
        case failure(String)
    }

    var body: some View {
        SettingsScroll("AI Provider") {
            SectionHeader("OpenAI-compatible endpoint")
            SettingsCard {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Base URL")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                        TextField("https://api.openai.com/v1", text: $settings.providerBaseURL)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, design: .monospaced))
                            .padding(.horizontal, 10)
                            .frame(height: 34)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(Color.white.opacity(0.08))
                            )
                        Text("Any OpenAI-compatible /v1 endpoint. Examples: api.openai.com/v1, api.anthropic.com/v1 (with proxy), openrouter.ai/api/v1, localhost:11434/v1 (Ollama)")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.35))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("API Key")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                        HStack(spacing: 8) {
                            Group {
                                if showKey {
                                    TextField("sk-…", text: $settings.apiKey)
                                } else {
                                    SecureField("sk-…", text: $settings.apiKey)
                                }
                            }
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, design: .monospaced))
                            .padding(.horizontal, 10)
                            .frame(height: 34)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 7))

                            Button {
                                showKey.toggle()
                            } label: {
                                Image(systemName: showKey ? "eye.slash" : "eye")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(QuietButtonStyle())
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Model")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                        TextField("gpt-4o", text: $settings.modelName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, design: .monospaced))
                            .padding(.horizontal, 10)
                            .frame(height: 34)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 7))

                        Text("Must support vision (image input). Examples: gpt-4o, gpt-4o-mini, claude-3-5-sonnet, gemini-2.0-flash, llava, qwen2-vl")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.35))
                    }

                    HStack(spacing: 12) {
                        Button("Test Connection") {
                            testConnection()
                        }
                        .buttonStyle(QuietButtonStyle())

                        switch testStatus {
                        case .idle:
                            EmptyView()
                        case .testing:
                            ProgressView()
                                .controlSize(.small)
                                .frame(height: 30)
                        case .success(let msg):
                            Label(msg, systemImage: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.green)
                        case .failure(let msg):
                            Label(msg, systemImage: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(16)
            }

            SectionHeader("How it works")
                .padding(.top, 24)

            SettingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    InfoRow("1", "Point at a question on screen with your mouse")
                    InfoRow("2", "Press your global shortcut (default ⌥⏎)")
                    InfoRow("3", "The display under your pointer is captured")
                    InfoRow("4", "A pink marker is drawn at your pointer and the screenshot is sent to YOUR provider")
                    InfoMark("The model reads the question from the image and returns the answer")
                }
                .padding(16)
            }

            SectionHeader("Privacy")
                .padding(.top, 24)

            SettingsCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("• No account, no login, no telemetry")
                    Text("• Your API key stays in your local Keychain-adjacent storage (UserDefaults, sandboxed)")
                    Text("• The ONLY network call is to the endpoint above")
                    Text("• Screenshots are never stored — held in memory only, discarded after the request")
                }
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .padding(16)
            }
        }
    }

    private func testConnection() {
        testStatus = .testing
        Task {
            do {
                let result = try await AIService.shared.testConnection()
                await MainActor.run {
                    testStatus = .success(result)
                }
            } catch {
                await MainActor.run {
                    testStatus = .failure(error.localizedDescription)
                }
            }
        }
    }
}

struct InfoRow: View {
    let n: String
    let text: String
    init(_ n: String, _ text: String) {
        self.n = n
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.white.opacity(0.12)))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

struct InfoMark: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 11))
                .foregroundStyle(.purple)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

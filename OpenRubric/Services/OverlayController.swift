import AppKit
import SwiftUI
import Combine

/// Invisible overlay window for remote mode — excluded from screen captures.
/// Uses NSWindow.Level and sharingType to avoid appearing in recordings/shares.
final class OverlayController: ObservableObject {
    static let shared = OverlayController()

    private var overlayWindow: NSPanel?
    @Published var isShowing: Bool = false
    @Published var answerText: String = ""
    @Published var isStreaming: Bool = false
    @Published var errorMessage: String?

    // MARK: - Show / Hide

    func show() {
        DispatchQueue.main.async {
            if self.overlayWindow == nil {
                self.createWindow()
            }
            self.overlayWindow?.alphaValue = 0
            self.overlayWindow?.orderFrontRegardless()
            self.isShowing = true

            // Fade in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                self.overlayWindow?.animator().alphaValue = 0.96
            })
        }
    }

    func hide() {
        DispatchQueue.main.async {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                self.overlayWindow?.animator().alphaValue = 0
            }, completionHandler: {
                self.overlayWindow?.orderOut(nil)
                self.isShowing = false
            })
        }
    }

    func updateStream(_ text: String) {
        DispatchQueue.main.async {
            self.answerText = text
        }
    }

    func streamFinished() {
        DispatchQueue.main.async {
            self.isStreaming = false
        }
    }

    func showError(_ message: String) {
        DispatchQueue.main.async {
            self.errorMessage = message
            self.isStreaming = false
            self.show()
        }
    }

    // MARK: - Window creation

    private func createWindow() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 220),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
        // Critical: this makes the window invisible to screen recording
        panel.sharingType = .none
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.hasShadow = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.title = "Answer"
        panel.animationBehavior = .utilityWindow

        let rootView = NSHostingView(rootView: AnswerOverlayContent(
            controller: self
        ))
        panel.contentView = rootView

        // Position: bottom-right of the main display, with margin
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let size = NSSize(width: 400, height: 220)
            let origin = NSPoint(
                x: screenFrame.maxX - size.width - 24,
                y: screenFrame.minY + 24
            )
            panel.setFrame(NSRect(origin: origin, size: size), display: true)
        }

        overlayWindow = panel
    }

    /// Toggle overlay visibility (can be bound to a secondary shortcut).
    func toggle() {
        if isShowing { hide() } else { show() }
    }
}

// MARK: - SwiftUI overlay content

struct AnswerOverlayContent: View {
    @ObservedObject var controller: OverlayController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                Text("Answer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button {
                    controller.hide()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()
                .overlay(Color.white.opacity(0.08))

            ScrollView {
                Text(controller.answerText.isEmpty && controller.isStreaming ? "Solving…" : controller.answerText)
                    .font(.system(size: 14, weight: .medium, design: .default))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            if let err = controller.errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 20))
                        .foregroundStyle(.yellow)
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.15)))
                .padding(10)
            }
        }
    }
}

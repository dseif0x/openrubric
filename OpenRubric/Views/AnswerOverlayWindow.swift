import SwiftUI

// The answer overlay is hosted inside OverlayController's NSPanel.
// This file provides the window-managed wrapper if the app needs
// a secondary persistent overlay for CBT-mode answers.

struct AnswerOverlayWindow: View {
    @StateObject private var iconState = AnswerDelivery.MenuBarIconState.shared

    var body: some View {
        VStack(spacing: 12) {
            if iconState.isWorking {
                ProgressView()
                    .controlSize(.large)
                Text(iconState.statusText)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
            } else if let answers = iconState.currentAnswer {
                HStack(spacing: 8) {
                    ForEach(answers, id: \.self) { a in
                        Text("\(a)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    }
                }
                Text("Answer")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(24)
    }
}

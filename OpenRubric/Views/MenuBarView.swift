import SwiftUI

/// The menu bar status item itself. In In-person (CBT) mode the icon reflects the live
/// result — a progress indicator while solving and the answer number(s) once delivered —
/// instead of only showing them as text inside the opened menu. Other modes keep the
/// static mode icon (their answers are delivered through hardware/overlay channels).
struct MenuBarLabel: View {
    @StateObject private var settings = SettingsStore.shared
    @StateObject private var iconState = AnswerDelivery.MenuBarIconState.shared

    var body: some View {
        if settings.currentMode == .cbt {
            if iconState.isWorking {
                Image(systemName: "hourglass")
            } else if let answers = iconState.currentAnswer, !answers.isEmpty {
                Text(answers.map(String.init).joined(separator: ","))
            } else {
                Image(systemName: settings.currentMode.systemImage)
            }
        } else {
            Image(systemName: settings.currentMode.systemImage)
        }
    }
}

struct MenuBarView: View {
    @StateObject private var settings = SettingsStore.shared
    @StateObject private var iconState = AnswerDelivery.MenuBarIconState.shared
    @StateObject private var overlay = OverlayController.shared

    var body: some View {
        Group {
            if iconState.isWorking {
                Text("⏳ \(iconState.statusText)")
            } else if let answers = iconState.currentAnswer {
                Text("✅ Answer: \(answers.map(String.init).joined(separator: ", "))")
            } else if let err = iconState.lastError {
                Text("⚠️ \(err.prefix(60))")
            } else {
                Text("Ready")
            }
        }

        Divider()

        Picker("Mode", selection: $settings.currentMode) {
            ForEach(ExamMode.allCases) { mode in
                Text(mode.displayName()).tag(mode)
            }
        }
        .pickerStyle(.inline)

        Divider()

        Button("Trigger now") {
            CaptureCoordinator.shared.triggerCaptureAndSolve()
        }
        .keyboardShortcut("s", modifiers: .command)

        Button("Toggle answer overlay") {
            OverlayController.shared.toggle()
        }

        Divider()

        Button("Settings…") {
            OpenRubricWindows.shared.showSettings()
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}

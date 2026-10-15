import SwiftUI

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

        Text("Mode: \(settings.currentMode.displayName())")
        ForEach(ExamMode.allCases) { mode in
            Button(mode.displayName()) {
                settings.currentMode = mode
            }
        }

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

extension OpenRubricWindows {
    func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14.0, *) {
            // Settings scene opens via ⌘,
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}

import SwiftUI

enum ExamMode: String, CaseIterable, Identifiable, Codable {
    case remote
    case cbt
    case capsLock
    case keyboardBacklight
    case flash

    var id: String { rawValue }

    var isMultipleChoice: Bool {
        switch self {
        case .cbt, .capsLock, .keyboardBacklight, .flash:
            return true
        case .remote:
            return false
        }
    }

    var systemImage: String {
        switch self {
        case .remote: return "rectangle.on.rectangle"
        case .cbt: return "menubar.rectangle"
        case .capsLock: return "capslock"
        case .keyboardBacklight: return "keyboard"
        case .flash: return "sun.max"
        }
    }

    func displayName(loc: Bool = true) -> String {
        switch self {
        case .remote: return loc ? "Remote exam" : "Remote exam"
        case .cbt: return loc ? "In-person exam" : "In-person exam"
        case .capsLock: return "Caps Lock LED (Beta)"
        case .keyboardBacklight: return "Keyboard backlight (Beta)"
        case .flash: return "Screen flash (Beta)"
        }
    }

    func displayDescription() -> String {
        switch self {
        case .remote:
            return "Answers appear in an invisible window excluded from screen recording."
        case .cbt:
            return "Multiple-choice answers appear as a small menu bar icon."
        case .capsLock:
            return "The Caps Lock LED blinks to indicate the answer number."
        case .keyboardBacklight:
            return "The keyboard backlight pulses to indicate the answer number."
        case .flash:
            return "The screen brightness pulses to indicate the answer number."
        }
    }
}

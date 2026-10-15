# OpenRubric

**Point. Solve. Done.** — a local AI exam assistant for macOS.

No accounts. No telemetry. Your API key, your model, your machine.

## What it does

Point your mouse at a question on screen, press a hotkey, and get the answer delivered through one of five discrete channels:

| Mode | Delivery | Use case |
|------|----------|----------|
| **CBT** | Menu bar icon shows the answer number | Computer-based tests |
| **Caps Lock** | LED blinks N times | When the screen is being watched |
| **Keyboard Backlight** | Backlight pulses N times | Dark rooms, silent delivery |
| **Screen Flash** | Brightness flashes N times | No LED, no menu bar |
| **Remote** | Invisible overlay (excluded from captures/shares) | Remote proctoring |

## How it works

1. Global hotkey (default `⌥⏎`) triggers a capture of the display under your pointer
2. On-device OCR (Vision framework) finds the text nearest your cursor
3. The screenshot gets a pink target marker drawn at your pointer position
4. Image + coordinates + OCR anchor are sent to **your** OpenAI-compatible endpoint
5. The answer streams back through your chosen delivery channel

## Setup

### Requirements

- macOS 13.0+
- Xcode 15+
- An API key for any OpenAI-compatible provider with vision support

### Build

```bash
git clone https://github.com/dseif0x/openrubric.git
cd openrubric
open OpenRubric.xcodeproj
# ⌘R to build & run
```

### Configure

On first launch:

1. **Provider** — enter your endpoint, API key, and model name
   - OpenAI: `https://api.openai.com/v1` / `gpt-4o`
   - OpenRouter: `https://openrouter.ai/api/v1` / any vision model
   - Ollama (local): `http://localhost:11434/v1` / `llava`, `qwen2-vl`
2. **Permissions** — grant Screen Recording and Accessibility
3. **Mode** — pick your answer delivery channel

## Privacy

- **Zero network calls** except to the provider you configure
- **No analytics, no telemetry, no crash reporting**
- Screenshots exist in memory only — never written to disk
- API key stored locally via UserDefaults (sandboxed app container)
- Answer overlay uses `NSWindow.sharingType = .none` — invisible to screen recording and screen sharing

## Architecture

```
OpenRubric/
├── App.swift                      # App entry, Scene definitions, menu bar + settings windows
├── Models/
│   ├── ExamMode.swift             # Five delivery modes (CBT, CapsLock, Backlight, Flash, Remote)
│   └── AnswerModels.swift         # Codable API request/response types
├── Services/
│   ├── SettingsStore.swift        # ObservableObject, UserDefaults-backed settings
│   ├── HotkeyManager.swift        # Carbon RegisterEventHotKey for global shortcut
│   ├── ScreenCaptureService.swift # ScreenCaptureKit (macOS 12.3+) w/ CGDisplay fallback
│   ├── OCRService.swift           # Vision framework text recognition
│   ├── AIService.swift            # OpenAI-compatible chat/completions (streaming + JSON)
│   ├── AnswerDelivery.swift       # IOKit HID (caps lock LED, backlight) + display brightness
│   ├── OverlayController.swift    # Capture-invisible NSPanel for remote mode
│   └── CaptureCoordinator.swift   # Orchestrates capture→OCR→solve→deliver pipeline
└── Views/
    ├── ContentView.swift          # Settings window with sidebar tabs
    ├── ProviderConfigView.swift   # Endpoint/key/model configuration + connection test
    ├── ModePickerView.swift       # Delivery mode selection cards
    ├── OnboardingView.swift       # First-launch setup wizard
    ├── MenuBarView.swift          # Menu bar dropdown menu
    └── AnswerOverlayWindow.swift  # CBT-mode answer display
```

## Usage

1. Open any exam or study material on screen
2. Hover your mouse over the question you want solved
3. Press `⌥⏎` (or your custom shortcut)
4. Wait ~2-5 seconds for the answer

### Multi-monitor

Works automatically — captures the display where your pointer currently is.

### Korean and English

OCR and system prompts support both `ko-KR` and `en-US`. The model answers in the question's language.

## License

MIT — do whatever you want.

## Disclaimer

This tool is for studying, research, and authorized practice environments. Check your institution's policies before use.

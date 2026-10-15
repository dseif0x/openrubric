import SwiftUI

struct ModePickerView: View {
    @StateObject private var settings = SettingsStore.shared

    var body: some View {
        SettingsScroll("Mode") {
            SettingsCard {
                HStack(spacing: 13) {
                    Image(systemName: "cursorarrow")
                        .font(.system(size: 17))
                        .frame(width: 18)
                    IconLabel("", "Point at a question and press \(settings.shortcutString)",
                              "The answer appears using the selected display method below.")
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(height: 72)
            }

            VStack(spacing: 12) {
                ForEach(ExamMode.allCases) { mode in
                    ModeCard(
                        mode: mode,
                        isSelected: settings.currentMode == mode
                    ) {
                        settings.currentMode = mode
                    }
                }
            }
            .padding(.top, 13)
        }
    }
}

struct ModeCard: View {
    let mode: ExamMode
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.displayName())
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(mode.displayDescription())
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1))
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.white.opacity(0.07) : (isHovered ? Color.white.opacity(0.04) : Color.white.opacity(0.02)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color(red: 0.04, green: 0.52, blue: 1).opacity(0.5) : Color.white.opacity(0.06), lineWidth: 1)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { h in isHovered = h }
    }
}

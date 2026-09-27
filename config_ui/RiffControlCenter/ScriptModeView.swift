import SwiftUI

struct ScriptModeView: View {
    @EnvironmentObject var settings: SettingsManager

    let modes = [
        ("english_mixed", "English Mixed", "Recommended"),
        ("english_translated", "English Translated", ""),
        ("original_mixed", "Original Mixed", "")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Script Mode")
                .font(RiffType.h2)
                .foregroundColor(RiffTheme.ink)
            Text("Choose how Riff handles multilingual dictation and code-switching (like Hinglish, Spanglish, Benglish).")
                .font(RiffType.bodySM)
                .foregroundColor(RiffTheme.inkMuted)
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(modes.enumerated()), id: \.element.0) { index, mode in
                    ScriptModeCard(
                        index: String(format: "%02d", index + 1),
                        mode: mode.0,
                        title: mode.1,
                        badge: mode.2,
                        isSelected: settings.config.script_mode.active_mode == mode.0,
                        action: {
                            settings.config.script_mode.active_mode = mode.0
                            settings.saveConfig()
                        }
                    )
                }
            }
            Spacer()
        }
        .padding(RiffTheme.space6)
        .background(RiffTheme.surface000)
    }
}

struct ScriptModeCard: View {
    var index: String = "01"
    let mode: String
    let title: String
    let badge: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(index)
                        .font(RiffType.mono(12))
                        .foregroundColor(isSelected ? RiffTheme.amberInk : RiffTheme.inkFaint)
                    Spacer()
                    if !badge.isEmpty {
                        RiffTag(text: badge, kind: .amber)
                    }
                }
                Text(title)
                    .font(RiffType.sans(14, weight: .semibold))
                    .foregroundColor(RiffTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(RiffScriptCopy.description(mode))
                    .font(RiffType.bodySM)
                    .foregroundColor(RiffTheme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("EXAMPLE")
                    .font(RiffType.label)
                    .tracking(1.1)
                    .foregroundColor(RiffTheme.inkFaint)
                    .padding(.top, 4)
                Text(RiffScriptCopy.example(mode))
                    .font(RiffType.num)
                    .foregroundColor(RiffTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? RiffTheme.amberWash : RiffTheme.surface100)
            .overlay(
                RoundedRectangle(cornerRadius: RiffTheme.radiusSM)
                    .stroke(isSelected ? RiffTheme.amberInk : RiffTheme.line, lineWidth: 1)
            )
            .cornerRadius(RiffTheme.radiusSM)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

import SwiftUI

struct ScriptAndStyleView: View {
    @EnvironmentObject var settings: SettingsManager
    @State private var wpmDraft = ""
    @FocusState private var wpmFocused: Bool

    let modes = [
        ("english_mixed", "English Mixed", "Recommended"),
        ("english_translated", "English Translated", ""),
        ("original_mixed", "Original Mixed", "")
    ]
    let styles = ["casual", "clean", "formal", "riff"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dictation")
                        .font(RiffType.h2)
                        .foregroundColor(RiffTheme.ink)
                    Text("Casual types the raw transcript. The other styles rewrite it.")
                        .font(RiffType.bodySM)
                        .foregroundColor(RiffTheme.inkMuted)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Script mode")
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
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Transcription style")
                        .font(RiffType.h2)
                        .foregroundColor(RiffTheme.ink)
                    Text("Casual pastes Whisper as-is. Clean, Formal, and Riff still run a Groq rewrite.")
                        .font(RiffType.bodySM)
                        .foregroundColor(RiffTheme.inkMuted)
                    HStack(spacing: 12) {
                        ForEach(styles, id: \.self) { style in
                            StyleCard(
                                style: style,
                                isSelected: settings.config.style.active_style == style,
                                action: {
                                    settings.config.style.active_style = style
                                    settings.saveConfig()
                                }
                            )
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Typing speed")
                        .font(RiffType.h2)
                        .foregroundColor(RiffTheme.ink)
                    Text("Used only for Time saved: words ÷ this WPM − minutes spoken. Default 40.")
                        .font(RiffType.bodySM)
                        .foregroundColor(RiffTheme.inkMuted)
                    HStack(spacing: 8) {
                        TextField("40", text: $wpmDraft)
                        .textFieldStyle(.plain)
                        .font(RiffType.num)
                        .foregroundColor(RiffTheme.ink)
                        .frame(width: 64, height: 32)
                        .padding(.horizontal, 8)
                        .background(RiffTheme.surface200)
                        .overlay(RoundedRectangle(cornerRadius: RiffTheme.radiusXS).stroke(RiffTheme.lineStrong, lineWidth: 1))
                        .focused($wpmFocused)
                        .onSubmit { commitWPM() }
                        .onChange(of: wpmFocused) { focused in
                            if !focused { commitWPM() }
                        }
                        .onAppear { wpmDraft = String(settings.config.metrics?.typing_wpm ?? 40) }
                        Text("WPM").font(RiffType.num).foregroundColor(RiffTheme.inkMuted)
                    }
                }
            }
            .padding(RiffTheme.space6)
        }
        .background(RiffTheme.surface000)
    }

    private func commitWPM() {
        let parsed = Int(wpmDraft.filter(\.isNumber)) ?? settings.config.metrics?.typing_wpm ?? 40
        let wpm = max(10, min(parsed, 200))
        wpmDraft = String(wpm)
        if settings.config.metrics == nil {
            settings.config.metrics = MetricsConfig(typing_wpm: wpm)
        } else {
            settings.config.metrics?.typing_wpm = wpm
        }
        settings.saveConfig()
        settings.loadStats()
    }
}

struct MetricsView: View {
    let metrics: MetricsConfig
    var body: some View { RiffStatStrip(metrics: metrics) }
}

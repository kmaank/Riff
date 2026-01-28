import SwiftUI

struct ScriptAndStyleView: View {
    @EnvironmentObject var settings: SettingsManager

    let modes = [
        ("english_mixed", "English Mixed", "Recommended"),
        ("english_translated", "English Translated", ""),
        ("original_mixed", "Original Mixed", "")
    ]

    let styles = ["clean", "formal", "casual", "riff"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                // Script Mode Section
                VStack(alignment: .leading, spacing: 20) {
                    Text("Script Mode")
                        .font(.title2)
                        .bold()

                    Text("Choose how Riff handles multilingual dictation and code-switching (like Hinglish, Spanglish, Benglish).")
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                        ForEach(modes, id: \.0) { mode in
                            ScriptModeCard(
                                mode: mode.0,
                                title: mode.1,
                                badge: mode.2,
                                isSelected: settings.config.script_mode.active_mode == mode.0,
                                action: {
                                    var newConfig = settings.config
                                    newConfig.script_mode.active_mode = mode.0
                                    settings.config = newConfig
                                    settings.saveConfig()
                                }
                            )
                        }
                    }
                }

                Divider()

                // Style Section
                VStack(alignment: .leading, spacing: 20) {
                    Text("Transcription Style")
                        .font(.title2)
                        .bold()

                    Text("Choose the default personality for your Riffs.")
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 15) {
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

                Spacer()
            }
            .padding(30)
        }
    }
}

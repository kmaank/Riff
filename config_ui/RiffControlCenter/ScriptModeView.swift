import SwiftUI

struct ScriptModeView: View {
    @EnvironmentObject var settings: SettingsManager

    let modes = [
        ("english_mixed", "English Mixed", "Recommended"),
        ("english_translated", "English Translated", ""),
        ("original_mixed", "Original Mixed", "")
    ]

    var body: some View {
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
            .padding(.top)

            Spacer()
        }
        .padding(30)
    }
}

struct ScriptModeCard: View {
    let mode: String
    let title: String
    let badge: String
    let isSelected: Bool
    let action: () -> Void

    var icon: String {
        switch mode {
        case "english_mixed": return "textformat.abc"
        case "english_translated": return "character.book.closed"
        case "original_mixed": return "globe"
        default: return "textformat"
        }
    }

    var color: Color {
        switch mode {
        case "english_mixed": return .green
        case "english_translated": return .blue
        case "original_mixed": return .purple
        default: return .gray
        }
    }

    var example: String {
        switch mode {
        case "english_mixed":
            return "Mujhe lagta hai we should meet"
        case "english_translated":
            return "I think we should meet"
        case "original_mixed":
            return "मुझे लगता है we should meet"
        default:
            return ""
        }
    }

    var description: String {
        switch mode {
        case "english_mixed":
            return "Keeps vernacular, romanizes non-English. Perfect for code-switching."
        case "english_translated":
            return "Translates everything to English. Clean, universal output."
        case "original_mixed":
            return "Auto-detects language and uses original script (Devanagari, etc.)."
        default:
            return ""
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundStyle(isSelected ? .white : color)

                    Spacer()

                    if !badge.isEmpty {
                        Text(badge)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(isSelected ? .white.opacity(0.3) : color.opacity(0.15))
                            .foregroundStyle(isSelected ? .white : color)
                            .cornerRadius(4)
                    }
                }

                Text(title)
                    .font(.headline)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                    .background(isSelected ? .white.opacity(0.3) : .gray.opacity(0.2))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Example:")
                        .font(.caption2)
                        .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)

                    Text(example)
                        .font(.caption)
                        .italic()
                        .foregroundStyle(isSelected ? .white : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(15)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? color : Color.gray.opacity(0.08))
                    .shadow(color: .black.opacity(isSelected ? 0.2 : 0.05), radius: isSelected ? 8 : 2, x: 0, y: isSelected ? 4 : 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? color.opacity(0.0) : Color.gray.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

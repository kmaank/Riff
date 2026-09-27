import SwiftUI

struct StyleView: View {
    @EnvironmentObject var settings: SettingsManager
    let styles = ["casual", "clean", "formal", "riff"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transcription Style")
                .font(RiffType.h2)
                .foregroundColor(RiffTheme.ink)
            Text("Casual is fastest (no rewrite). Clean tidies. Formal is email-ready. Riff answers you.")
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
            Spacer()
        }
        .padding(RiffTheme.space6)
        .background(RiffTheme.surface000)
    }
}

struct StyleCard: View {
    let style: String
    let isSelected: Bool
    var isLocked: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(style.capitalized)
                    .font(RiffType.sans(14, weight: .semibold))
                    .foregroundColor(isSelected ? RiffTheme.onAmber : RiffTheme.inkMuted)
                Text(RiffStyleCopy.promise(style))
                    .font(RiffType.caption)
                    .foregroundColor(isSelected ? RiffTheme.onAmber.opacity(0.8) : RiffTheme.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 84)
            .background(isSelected ? RiffTheme.amber : RiffTheme.surface100)
            .overlay(
                RoundedRectangle(cornerRadius: RiffTheme.radiusSM)
                    .stroke(isSelected ? RiffTheme.amber : RiffTheme.line, lineWidth: 1)
            )
            .cornerRadius(RiffTheme.radiusSM)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .disabled(isLocked)
    }
}

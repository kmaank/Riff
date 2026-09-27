import SwiftUI

struct HelpView: View {
    @EnvironmentObject var settings: SettingsManager

    private var keycap: String {
        RiffHotkey.keycap(settings.config.hotkey.combination)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("How to riff")
                    .font(RiffType.h1)
                    .foregroundColor(RiffTheme.ink)
                HStack(spacing: 8) {
                    Text("Hold")
                        .font(RiffType.body)
                        .foregroundColor(RiffTheme.inkMuted)
                    RiffKeyCap(text: keycap)
                    Text("speak, release. Riff types into whatever you're looking at.")
                        .font(RiffType.body)
                        .foregroundColor(RiffTheme.inkMuted)
                }
                VStack(alignment: .leading, spacing: 12) {
                    tip("1. Hold and speak", "Keep talking until you're done. A small timer appears near the top of the screen.")
                    tip("2. Release", "Casual pastes what Whisper heard. Clean, Formal, and Riff take a moment to rewrite.")
                    tip("3. Riff pastes", "The words land in the text field you clicked. If nothing is selected, click a field first.")
                    tip("Latch", "Hold Shift with your key to lock recording. Press the key again when you're done.")
                    tip("Open Home", "Riff has no Dock icon. Click the Riff icon in the menu bar, then Open Home.")
                }
            }
            .padding(RiffTheme.space6)
        }
        .background(RiffTheme.surface000)
    }

    private func tip(_ title: String, _ bodyText: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(RiffType.h2)
                .foregroundColor(RiffTheme.ink)
            Text(bodyText)
                .font(RiffType.bodySM)
                .foregroundColor(RiffTheme.inkMuted)
        }
    }
}

struct HelpSection: View {
    let icon: String
    let title: String
    let bodyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(RiffType.h2).foregroundColor(RiffTheme.ink)
            Text(.init(bodyText)).font(RiffType.bodySM).foregroundColor(RiffTheme.inkMuted)
        }
    }
}

struct TipRow: View {
    let text: String
    var body: some View {
        Text(.init(text))
            .font(RiffType.bodySM)
            .foregroundColor(RiffTheme.inkMuted)
    }
}

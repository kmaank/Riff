import SwiftUI

struct KeysView: View {
    @EnvironmentObject var settings: SettingsManager

    let availableKeys: [(String, String)] = [
        ("Left Control", "ctrl_l"),
        ("Right Control", "ctrl_r"),
        ("Left Option", "alt_l"),
        ("Right Option", "alt_r"),
        ("Left Command", "cmd_l"),
        ("Right Command", "cmd_r"),
        ("F1", "f1"), ("F2", "f2"), ("F3", "f3"), ("F4", "f4"),
        ("F5", "f5"), ("F6", "f6"), ("F7", "f7"), ("F8", "f8"),
        ("F9", "f9"), ("F10", "f10"), ("F11", "f11"), ("F12", "f12")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Shortcuts")
                        .font(RiffType.h2)
                        .foregroundColor(RiffTheme.ink)
                    Text("Press and hold this key to speak. You can change it without restarting Riff.")
                        .font(RiffType.bodySM)
                        .foregroundColor(RiffTheme.inkMuted)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("PUSH-TO-TALK")
                        .font(RiffType.label)
                        .tracking(1.1)
                        .foregroundColor(RiffTheme.inkFaint)
                    Picker("", selection: $settings.config.hotkey.combination) {
                        ForEach(availableKeys, id: \.1) { name, value in
                            Text(name).tag(value)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                    .onChange(of: settings.config.hotkey.combination) { _ in
                        settings.saveConfig()
                    }
                    HStack(spacing: 8) {
                        Text("Hold")
                            .font(RiffType.bodySM)
                            .foregroundColor(RiffTheme.inkMuted)
                        RiffKeyCap(text: RiffHotkey.keycap(settings.config.hotkey.combination))
                        Text("and speak.")
                            .font(RiffType.bodySM)
                            .foregroundColor(RiffTheme.inkMuted)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RiffTheme.surface100)
                .overlay(RoundedRectangle(cornerRadius: RiffTheme.radiusSM).stroke(RiffTheme.line, lineWidth: 1))
                .cornerRadius(RiffTheme.radiusSM)

                VStack(alignment: .leading, spacing: 10) {
                    Text("LATCH")
                        .font(RiffType.label)
                        .tracking(1.1)
                        .foregroundColor(RiffTheme.inkFaint)
                    HStack(spacing: 8) {
                        RiffKeyCap(text: "SHIFT")
                        Text("+")
                            .foregroundColor(RiffTheme.inkMuted)
                        RiffKeyCap(text: RiffHotkey.keycap(settings.config.hotkey.combination))
                    }
                    Text("Hold Shift with your key to lock recording on. Press \(RiffHotkey.keycap(settings.config.hotkey.combination)) again to stop.")
                        .font(RiffType.bodySM)
                        .foregroundColor(RiffTheme.inkMuted)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RiffTheme.surface100)
                .overlay(RoundedRectangle(cornerRadius: RiffTheme.radiusSM).stroke(RiffTheme.line, lineWidth: 1))
                .cornerRadius(RiffTheme.radiusSM)
            }
            .padding(RiffTheme.space6)
        }
        .background(RiffTheme.surface000)
    }
}

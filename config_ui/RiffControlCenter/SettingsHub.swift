import SwiftUI
import AppKit

struct SettingsHub: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var runtime: RiffRuntimeStatus
    @Binding var tab: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings")
                    .font(RiffType.h1)
                    .foregroundColor(RiffTheme.ink)
                RiffTabBar(
                    tabs: [
                        ("dictation", "Dictation"),
                        ("shortcuts", "Shortcuts"),
                        ("dictionary", "Dictionary"),
                        ("permissions", "Permissions"),
                        ("account", "Account")
                    ],
                    selection: $tab,
                    problemIDs: runtime.missingPermissionCount > 0 ? ["permissions"] : []
                )
            }
            .padding(.horizontal, RiffTheme.space6)
            .padding(.top, RiffTheme.space5)

            Group {
                switch tab {
                case "shortcuts": KeysView()
                case "dictionary": DictionaryPlaceholderView()
                case "permissions": PermissionsSettingsView()
                case "account": AccountView()
                default: ScriptAndStyleView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(RiffTheme.surface000)
    }
}

struct DictionaryPlaceholderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Dictionary")
                .font(RiffType.h2)
                .foregroundColor(RiffTheme.ink)
            Text("Words and snippets will apply before any style rewrite.")
                .font(RiffType.bodySM)
                .foregroundColor(RiffTheme.inkMuted)
            RiffEmptyState(
                icon: "textformat",
                title: "Words come next.",
                detail: "This tab will learn names and shortcuts."
            )
            Spacer()
        }
        .padding(RiffTheme.space6)
    }
}

struct PermissionsSettingsView: View {
    @EnvironmentObject var runtime: RiffRuntimeStatus

    private var rows: [(id: String, title: String, why: String, granted: Bool)] {
        [
            ("microphone", "Microphone", "So Riff can hear you. Turn on the row named Riff.", runtime.microphoneGranted),
            ("accessibility", "Accessibility", "So Riff can paste into the focused field. Turn on the row named Riff.", runtime.permissions.accessibility),
            ("input_monitoring", "Input Monitoring", "So Riff notices when you hold the key. Turn on the row named Riff.", runtime.permissions.input_monitoring)
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if runtime.applyingPermissions {
                    RiffBanner(
                        title: "Riff is applying permissions",
                        detail: "This window stays open. The menu-bar app is restarting so the grant takes effect.",
                        actionTitle: "Recheck",
                        action: { runtime.refresh() }
                    )
                } else if runtime.reporterStale {
                    RiffBanner(
                        title: "Riff is not reporting permissions",
                        detail: "Open the menu-bar Riff app. This window cannot see Microphone until that process is running.",
                        actionTitle: "Recheck",
                        action: { runtime.refresh() }
                    )
                } else if runtime.missingPermissionCount > 0 {
                    RiffBanner(
                        title: runtime.missingPermissionCount == 1
                            ? "\(runtime.missingPermissionNames[0]) is off"
                            : "\(runtime.missingPermissionCount) permissions missing",
                        detail: "In System Settings, turn on the row named Riff. This window stays here.",
                        actionTitle: openTitle(for: runtime.missingPermissionNames.first ?? ""),
                        action: { openSettings(for: runtime.missingPermissionNames.first ?? "Microphone") }
                    )
                }

                VStack(spacing: 0) {
                    ForEach(rows, id: \.id) { row in
                        PermissionRowView(
                            title: row.title,
                            why: row.why,
                            granted: row.granted,
                            action: { openSettings(for: row.title) }
                        )
                        if row.id != rows.last?.id {
                            Rectangle().fill(RiffTheme.line).frame(height: 1)
                        }
                    }
                }
                .background(RiffTheme.surface100)
                .overlay(
                    RoundedRectangle(cornerRadius: RiffTheme.radiusSM)
                        .stroke(RiffTheme.line, lineWidth: 1)
                )
                .cornerRadius(RiffTheme.radiusSM)
            }
            .padding(RiffTheme.space6)
        }
        .onAppear { runtime.refresh() }
    }

    private func openTitle(for name: String) -> String {
        name.isEmpty ? "Open settings" : "Open \(name)"
    }

    private func openSettings(for title: String) {
        let urlString: String
        switch title {
        case "Microphone":
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case "Input Monitoring":
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        default:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }
        SettingsSession.notePermissionGrant()
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

struct PermissionRowView: View {
    let title: String
    let why: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: title == "Microphone" ? "mic" : (title == "Accessibility" ? "hand.raised" : "keyboard"))
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(RiffTheme.inkMuted)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(RiffType.sans(14, weight: .semibold))
                    .foregroundColor(RiffTheme.ink)
                Text(why)
                    .font(RiffType.bodySM)
                    .foregroundColor(RiffTheme.inkMuted)
            }
            Spacer()
            RiffTag(text: granted ? "Granted" : "Missing", kind: granted ? .gain : .loss, showArrow: true)
            RiffButton(
                title: granted ? "Manage" : "Open settings",
                kind: granted ? .secondary : .primary,
                action: action
            )
        }
        .padding(16)
    }
}

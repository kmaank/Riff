import SwiftUI

struct HomeView: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var runtime: RiffRuntimeStatus
    @EnvironmentObject var authManager: SwiftAuthManager
    var onOpenPermissions: () -> Void
    var onOpenAccount: () -> Void = {}
    var onOpenHistory: () -> Void = {}

    private var keycap: String { RiffHotkey.keycap(settings.config.hotkey.combination) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if runtime.applyingPermissions {
                    RiffBanner(
                        title: "Riff is applying permissions",
                        detail: "This window stays open while the menu-bar app restarts.",
                        actionTitle: "Fix permissions",
                        action: onOpenPermissions
                    )
                } else if runtime.reporterStale {
                    RiffBanner(
                        title: "Riff is not reporting",
                        detail: "Open the menu-bar Riff app. This window cannot see Microphone or the hotkey until that process is running.",
                        actionTitle: "Fix permissions",
                        action: onOpenPermissions
                    )
                } else if runtime.permissionBannerVisible {
                    RiffBanner(
                        title: runtime.missingPermissionCount == 1
                            ? "\(runtime.missingPermissionNames[0]) is off"
                            : "\(runtime.missingPermissionCount) permissions missing",
                        detail: "Turn on the row named Riff in System Settings. This window stays open.",
                        actionTitle: "Fix permissions",
                        action: onOpenPermissions
                    )
                } else if runtime.provider.waiting > 0 {
                    RiffBanner(
                        title: runtime.provider.waiting == 1 ? "1 riff waiting" : "\(runtime.provider.waiting) riffs waiting",
                        detail: runtime.provider.label,
                        actionTitle: "Open account",
                        action: onOpenAccount
                    )
                } else if ["rate_limited", "offline", "key_rejected"].contains(runtime.provider.state) {
                    RiffBanner(
                        title: runtime.provider.state == "key_rejected" ? "Groq key rejected" : runtime.provider.label,
                        detail: runtime.provider.state == "key_rejected"
                            ? "Paste a valid key on the Account tab."
                            : "Your audio is saved. Riff will type the queue when this clears.",
                        actionTitle: "Account",
                        action: onOpenAccount
                    )
                }

                hero

                if let stats = settings.stats {
                    TimeSavedCard(stats: stats)
                } else if let metrics = settings.config.metrics, metrics.total_riffs > 0 {
                    RiffStatStrip(metrics: metrics)
                }

                controls

                HStack(alignment: .top, spacing: 16) {
                    recent
                    if let stats = settings.stats {
                        StreakStrip(stats: stats)
                            .frame(width: 260)
                    }
                }
            }
            .padding(.horizontal, RiffTheme.space6)
            .padding(.vertical, RiffTheme.space5)
        }
        .background(RiffTheme.surface000)
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                RiffTag(
                    text: runtime.canDictate ? "Ready" : (runtime.applyingPermissions || runtime.reporterStale ? "Waiting" : "Blocked"),
                    kind: runtime.canDictate ? .gain : .loss
                )
                HStack(spacing: 8) {
                    Text("Hold")
                        .font(RiffType.h1)
                        .foregroundColor(RiffTheme.ink)
                    RiffKeyCap(text: keycap)
                    Text("and speak.")
                        .font(RiffType.h1)
                        .foregroundColor(RiffTheme.ink)
                }
                Text("Text types into the window you are in. Hold Shift + \(keycap) to lock recording on.")
                    .font(RiffType.bodySM)
                    .foregroundColor(RiffTheme.inkMuted)
                Text("Riff stays in the menu bar. Click the icon to open this window — there is no Dock icon.")
                    .font(RiffType.caption)
                    .foregroundColor(RiffTheme.inkFaint)
            }
            Spacer()
            Image(systemName: "mic")
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(RiffTheme.amberInk)
                .frame(width: 48, height: 48)
                .background(RiffTheme.amberWash)
                .cornerRadius(RiffTheme.radiusSM)
        }
    }

    private var controls: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("STYLE")
                    .font(RiffType.label)
                    .tracking(1.1)
                    .foregroundColor(RiffTheme.inkFaint)
                RiffSegmentedControl(
                    options: [
                        ("clean", "Clean"),
                        ("formal", "Formal"),
                        ("casual", "Casual"),
                        ("riff", "Riff")
                    ],
                    selection: Binding(
                        get: { settings.config.style.active_style },
                        set: { value in
                            settings.config.style.active_style = value
                            settings.saveConfig()
                        }
                    )
                )
                Text(settings.config.style.active_style == "casual"
                     ? "Casual types the raw transcript. Other styles rewrite it."
                     : RiffStyleCopy.promise(settings.config.style.active_style))
                    .font(RiffType.bodySM)
                    .foregroundColor(RiffTheme.inkMuted)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("SCRIPT")
                    .font(RiffType.label)
                    .tracking(1.1)
                    .foregroundColor(RiffTheme.inkFaint)
                RiffSegmentedControl(
                    options: [
                        ("english_mixed", "English Mixed"),
                        ("english_translated", "English"),
                        ("original_mixed", "Original")
                    ],
                    selection: Binding(
                        get: { settings.config.script_mode.active_mode },
                        set: { value in
                            settings.config.script_mode.active_mode = value
                            settings.saveConfig()
                        }
                    )
                )
            }
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent riffs")
                    .font(RiffType.h2)
                    .foregroundColor(RiffTheme.ink)
                Spacer()
                if !settings.history.isEmpty {
                    Button(action: onOpenHistory) {
                        HStack(spacing: 4) {
                            Text("View all")
                            Image(systemName: "arrow.right")
                        }
                        .font(RiffType.bodySM)
                        .foregroundColor(RiffTheme.link)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if settings.history.isEmpty {
                RiffEmptyState(
                    icon: "mic",
                    title: "No riffs yet.",
                    detail: "Hold",
                    keycap: keycap
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(settings.history.prefix(2))) { entry in
                        HistoryRow(
                            entry: entry,
                            compact: true,
                            onDelete: {
                                settings.deleteHistory(timestamp: entry.timestamp)
                                Task { await authManager.deleteCloudHistory(timestamp: entry.timestamp) }
                            }
                        )
                    }
                }
                .background(RiffTheme.surface100)
                .overlay(
                    RoundedRectangle(cornerRadius: RiffTheme.radiusSM)
                        .stroke(RiffTheme.line, lineWidth: 1)
                )
                .cornerRadius(RiffTheme.radiusSM)
            }
        }
    }
}

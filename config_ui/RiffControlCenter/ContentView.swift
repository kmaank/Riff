import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var authManager: SwiftAuthManager
    @EnvironmentObject var runtime: RiffRuntimeStatus
    @State private var selectedSection = "home"
    @State private var settingsTab = "dictation"

    var body: some View {
        let onboardingDone = settings.config.onboarding_completed ?? false
        let hasKey = settings.config.api.api_key.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("gsk_")
        let needsSetup = !onboardingDone || !authManager.isAuthenticated || !hasKey

        Group {
            if needsSetup {
                OnboardingView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        sidebar
                        Rectangle().fill(RiffTheme.line).frame(width: 1)
                        mainColumn
                    }
                    RiffStatusBar(
                        hotkey: settings.config.hotkey.combination,
                        script: settings.config.script_mode.active_mode,
                        style: settings.config.style.active_style,
                        hudState: runtime.hud.state,
                        hasKey: hasKey,
                        providerState: runtime.provider.state
                    )
                }
                .background(RiffTheme.surface000)
            }
        }
        .background(RiffTheme.surface000)
        .onAppear {
            RiffTheme.applyAppearance(settings.config.ui?.theme ?? "system")
            restoreSession()
            persistSession()
        }
        .onChange(of: settings.config.ui?.theme ?? "system") { theme in
            RiffTheme.applyAppearance(theme)
        }
        .onChange(of: selectedSection) { _ in persistSession() }
        .onChange(of: settingsTab) { _ in persistSession() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let wordmark = RiffLogo.wordmark {
                Image(nsImage: wordmark)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 36)
                    .padding(.bottom, 16)
                    .padding(.top, 8)
            } else {
                Text("Riff")
                    .font(RiffType.displayLG)
                    .foregroundColor(RiffTheme.amberInk)
                    .padding(.bottom, 16)
                    .padding(.top, 8)
            }

            SidebarItem(index: "01", icon: "house", title: "Home", id: "home", selection: $selectedSection)
            SidebarItem(index: "02", icon: "clock.arrow.circlepath", title: "History", id: "history", selection: $selectedSection)
            SidebarItem(index: "03", icon: "slider.horizontal.3", title: "Settings", id: "settings", selection: $selectedSection)
            SidebarItem(index: "04", icon: "questionmark.circle", title: "How to", id: "help", selection: $selectedSection)

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(groqDot)
                        .frame(width: 6, height: 6)
                    Text("GROQ")
                        .font(RiffType.label)
                        .tracking(1.1)
                        .foregroundColor(RiffTheme.inkMuted)
                    Text(groqLabel)
                        .font(RiffType.num)
                        .foregroundColor(RiffTheme.ink)
                        .lineLimit(1)
                }
                Button(action: {
                    selectedSection = "settings"
                    settingsTab = "account"
                }) {
                    HStack(spacing: 10) {
                        Text(initial)
                            .font(RiffType.mono(12))
                            .foregroundColor(RiffTheme.amberInk)
                            .frame(width: 24, height: 24)
                            .background(RiffTheme.amberWash)
                            .cornerRadius(RiffTheme.radiusXS)
                        Text(authManager.userEmail)
                            .font(RiffType.caption)
                            .foregroundColor(RiffTheme.inkMuted)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open Account")
                .accessibilityLabel("Account \(authManager.userEmail)")
            }
            .padding(.top, 8)
        }
        .padding(16)
        .frame(width: RiffTheme.sidebarWidth)
        .background(RiffTheme.surface100)
    }

    private var mainColumn: some View {
        Group {
            switch selectedSection {
            case "history":
                HistoryView()
            case "settings":
                SettingsHub(tab: $settingsTab)
            case "help":
                HelpView()
            default:
                HomeView(onOpenPermissions: {
                    selectedSection = "settings"
                    settingsTab = "permissions"
                }, onOpenAccount: {
                    selectedSection = "settings"
                    settingsTab = "account"
                }, onOpenHistory: {
                    selectedSection = "history"
                })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RiffTheme.surface000)
    }

    private func restoreSession() {
        guard let saved = SettingsSession.load() else { return }
        if saved.section == "home" || saved.section == "history" || saved.section == "settings" || saved.section == "help" {
            selectedSection = saved.section
        }
        if !saved.tab.isEmpty {
            settingsTab = saved.tab
        }
    }

    private func persistSession() {
        let onboardingDone = settings.config.onboarding_completed ?? false
        let hasKey = settings.config.api.api_key.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("gsk_")
        let needsSetup = !onboardingDone || !authManager.isAuthenticated || !hasKey
        SettingsSession.update(
            resume: needsSetup || settingsTab == "permissions",
            route: needsSetup ? "onboarding" : "main",
            section: selectedSection,
            tab: settingsTab
        )
    }

    private var hasGroqKey: Bool {
        settings.config.api.api_key.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("gsk_")
    }

    private var groqDot: Color {
        switch runtime.provider.state {
        case "healthy": return RiffTheme.gain
        case "rate_limited", "offline", "key_rejected": return RiffTheme.loss
        default: return hasGroqKey ? RiffTheme.gain : RiffTheme.loss
        }
    }

    private var groqLabel: String {
        if !hasGroqKey { return "Missing" }
        if runtime.provider.waiting > 0 { return "\(runtime.provider.waiting) waiting" }
        switch runtime.provider.state {
        case "rate_limited", "offline", "key_rejected":
            return runtime.provider.label.isEmpty ? runtime.provider.state : runtime.provider.label
        default:
            return "Your key"
        }
    }

    private var initial: String {
        String(authManager.userEmail.prefix(1)).uppercased()
    }
}

struct SidebarItem: View {
    let index: String
    let icon: String
    let title: String
    let id: String
    @Binding var selection: String

    var body: some View {
        Button(action: { selection = id }) {
            HStack(spacing: 8) {
                Text(index)
                    .font(RiffType.mono(11))
                    .foregroundColor(RiffTheme.inkFaint)
                    .frame(width: 18, alignment: .leading)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 16)
                Text(title)
                    .font(RiffType.sans(14, weight: .medium))
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .foregroundColor(selection == id ? RiffTheme.amberInk : RiffTheme.inkMuted)
            .background(selection == id ? RiffTheme.amberWash : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: RiffTheme.radiusXS)
                    .stroke(selection == id ? RiffTheme.amberInk : Color.clear, lineWidth: 1)
            )
            .cornerRadius(RiffTheme.radiusXS)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(title)
    }
}

import SwiftUI

struct AccountView: View {
    @EnvironmentObject var authManager: SwiftAuthManager
    @EnvironmentObject var settings: SettingsManager
    @State private var keyDraft = ""
    @FocusState private var keyFocused: Bool

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        identityCard
                        themeCard
                        keyCard
                        RiffButton(
                            title: "Sign Out",
                            icon: "rectangle.portrait.and.arrow.right",
                            kind: .danger,
                            action: {
                                authManager.signOut()
                                settings.loadConfig()
                            }
                        )
                    }
                    .padding(RiffTheme.space6)
                }
            } else {
                LoginView(compact: true)
            }
        }
        .background(RiffTheme.surface000)
    }

    private var identityCard: some View {
        HStack(spacing: 16) {
            Text(String(authManager.userEmail.prefix(1)).uppercased())
                .font(RiffType.mono(18))
                .foregroundColor(RiffTheme.amberInk)
                .frame(width: 40, height: 40)
                .background(RiffTheme.amberWash)
                .cornerRadius(RiffTheme.radiusXS)
            VStack(alignment: .leading, spacing: 4) {
                Text(authManager.userEmail)
                    .font(RiffType.h2)
                    .foregroundColor(RiffTheme.ink)
                Text("Member since \(authManager.memberSince.isEmpty ? memberSinceDate() : authManager.memberSince)")
                    .font(RiffType.caption)
                    .foregroundColor(RiffTheme.inkFaint)
            }
            Spacer()
        }
        .padding(16)
        .background(RiffTheme.surface100)
        .overlay(RoundedRectangle(cornerRadius: RiffTheme.radiusSM).stroke(RiffTheme.line, lineWidth: 1))
        .cornerRadius(RiffTheme.radiusSM)
    }

    private var themeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Appearance")
                .font(RiffType.h2)
                .foregroundColor(RiffTheme.ink)
            Text("Paper is the light theme. Terminal is dark. System follows macOS.")
                .font(RiffType.bodySM)
                .foregroundColor(RiffTheme.inkMuted)
            RiffSegmentedControl(
                options: [
                    ("system", "System"),
                    ("terminal", "Terminal"),
                    ("paper", "Paper")
                ],
                selection: Binding(
                    get: { settings.config.ui?.theme ?? "system" },
                    set: { value in
                        if settings.config.ui == nil {
                            settings.config.ui = UIConfig(theme: value, show_notifications: settings.config.ui?.show_notifications)
                        } else {
                            settings.config.ui?.theme = value
                        }
                        settings.saveConfig()
                        RiffTheme.applyAppearance(value)
                    }
                )
            )
        }
        .padding(16)
        .background(RiffTheme.surface100)
        .overlay(RoundedRectangle(cornerRadius: RiffTheme.radiusSM).stroke(RiffTheme.line, lineWidth: 1))
        .cornerRadius(RiffTheme.radiusSM)
    }

    private var keyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Groq key")
                .font(RiffType.h2)
                .foregroundColor(RiffTheme.ink)
            Text("Stored on your account so a new Mac or Android can restore it. Sign out clears it from this Mac.")
                .font(RiffType.bodySM)
                .foregroundColor(RiffTheme.inkMuted)
            SecureField("gsk_...", text: $keyDraft)
            .textFieldStyle(.plain)
            .font(RiffType.mono(13))
            .foregroundColor(RiffTheme.ink)
            .padding(10)
            .frame(height: 40)
            .background(RiffTheme.surface200)
            .overlay(RoundedRectangle(cornerRadius: RiffTheme.radiusXS).stroke(RiffTheme.lineStrong, lineWidth: 1))
            .cornerRadius(RiffTheme.radiusXS)
            .focused($keyFocused)
            .onSubmit { commitKey() }
            .onChange(of: keyFocused) { focused in
                if !focused { commitKey() }
            }
            .onAppear { keyDraft = settings.config.api.api_key }
            Button("Get a free key at console.groq.com/keys") {
                if let url = URL(string: "https://console.groq.com/keys") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.plain)
            .font(RiffType.bodySM)
            .foregroundColor(RiffTheme.link)
        }
        .padding(16)
        .background(RiffTheme.surface100)
        .overlay(RoundedRectangle(cornerRadius: RiffTheme.radiusSM).stroke(RiffTheme.line, lineWidth: 1))
        .cornerRadius(RiffTheme.radiusSM)
    }

    private func commitKey() {
        let trimmed = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != settings.config.api.api_key else { return }
        settings.config.api.api_key = trimmed
        settings.saveConfig()
        guard trimmed.hasPrefix("gsk_"), trimmed.count >= 40 else { return }
        Task { await authManager.saveCloudGroqKey(trimmed) }
    }

    private func memberSinceDate() -> String {
        "—"
    }
}

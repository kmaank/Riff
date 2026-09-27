import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var authManager: SwiftAuthManager
    @State private var step = 1
    @State private var apiKeyInput = ""
    @State private var isKeyValid = false
    @State private var keyCaptured = false
    @State private var restoredFromAccount = false
    @State private var testDriveBaseline = 0
    @State private var testDriveSucceeded = false
    @State private var testDriveText = ""
    @State private var restoringKey = false
    @State private var riffPermissions = RiffPermissionStatus()
    @State private var permissionIndex = 0
    @State private var permissionAskedAt: Date?
    @State private var autoAdvancedForIndex = -1
    @State private var hudStatus = HudStatus()
    @FocusState private var groqFieldFocused: Bool
    @FocusState private var driveFocused: Bool

    private let permissionBeats: [(id: String, title: String, why: String)] = [
        ("microphone", "Microphone", "So I can hear you."),
        ("accessibility", "Accessibility", "So I can paste what you said."),
        ("input_monitoring", "Keyboard", "So I notice when you hold the key.")
    ]

    var body: some View {
        VStack(spacing: 16) {
            progress
            Group {
                if step == 1 {
                    welcomeStep
                } else if step == 2 {
                    accountStep
                } else if step == 3 {
                    if restoredFromAccount {
                        restoredKeyStep
                    } else {
                        apiKeyStep
                    }
                } else if step == 4 {
                    permissionsStep
                } else {
                    testDriveStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(RiffTheme.space5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RiffTheme.surface000)
        .onAppear {
            AuthLogger.log("[Onboarding] appear step=\(step) authenticated=\(authManager.isAuthenticated) onboardingDone=\(settings.config.onboarding_completed ?? false) hasKey=\(settings.config.api.api_key.hasPrefix("gsk_"))")
            restoreOrAdvance()
            persistProgress()
        }
        .onChange(of: step) { newStep in
            AuthLogger.log("[Onboarding] step -> \(newStep)")
            persistProgress()
        }
        .onChange(of: permissionIndex) { _ in persistProgress() }
        .onChange(of: authManager.isAuthenticated) { authenticated in
            AuthLogger.log("[Onboarding] isAuthenticated -> \(authenticated) (step=\(step))")
            if authenticated && step <= 2 {
                advanceAfterAccount()
            }
        }
    }

    var progress: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { n in
                Circle()
                    .fill(n <= step ? RiffTheme.amber : RiffTheme.surface300)
                    .frame(width: n == step ? 10 : 7, height: n == step ? 10 : 7)
            }
        }
        .padding(.top, 4)
        .animation(.easeInOut(duration: 0.12), value: step)
    }

    var welcomeStep: some View {
        VStack(spacing: 22) {
            Spacer()
            if let wordmark = RiffLogo.wordmark {
                Image(nsImage: wordmark)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 56)
            } else if let icon = RiffLogo.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 88, height: 88)
            }
            Text("You're about to talk, and Riff types.")
                .font(RiffType.displayXL)
                .foregroundColor(RiffTheme.ink)
                .multilineTextAlignment(.center)
            Text("I'll walk you through a few minutes of setup. Stay on this window. I'll tell you each click.")
                .font(RiffType.body)
                .multilineTextAlignment(.center)
                .foregroundColor(RiffTheme.inkMuted)
                .frame(maxWidth: 520)
            Text("Riff lives in the menu bar after this — not the Dock. Click the Riff icon anytime to open Home.")
                .font(RiffType.bodySM)
                .multilineTextAlignment(.center)
                .foregroundColor(RiffTheme.inkFaint)
                .frame(maxWidth: 480)
            Text("Bring your own Groq key · No subscription")
                .font(RiffType.caption)
                .foregroundColor(RiffTheme.inkFaint)
            Spacer()
            RiffButton(title: "I'm ready", kind: .primary, action: {
                AuthLogger.log("[Onboarding] I'm ready tapped")
                withAnimation { step = 2 }
            })
            .padding(.bottom, 8)
        }
        .padding()
    }

    var accountStep: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                Text(authManager.isAuthenticated ? "Welcome back." : "A home for your key")
                    .font(RiffType.h1)
                    .foregroundColor(RiffTheme.ink)
                Text(authManager.isAuthenticated
                     ? "I'll fetch your key next. You won't paste it again."
                     : "Create a home for your key so a new Mac or Android can pick it up.")
                    .font(RiffType.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(RiffTheme.inkMuted)
                    .frame(maxWidth: 480)
            }
            .padding(.top, 8)

            if restoringKey {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Welcome back. I'll fetch your key next.")
                        .font(RiffType.bodySM)
                        .foregroundColor(RiffTheme.inkMuted)
                }
                .padding(.top, 24)
                Spacer()
            } else {
                LoginView(compact: true, companionCopy: true)
                Spacer()
            }

            HStack {
                RiffButton(title: "Back", kind: .ghost, action: { withAnimation { step = 1 } })
                Spacer()
            }
        }
        .padding(.horizontal)
    }

    var restoredKeyStep: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(RiffTheme.gain)
                .frame(width: 52, height: 52)
                .background(RiffTheme.gainWash)
                .cornerRadius(RiffTheme.radiusSM)
            Text("I already have your key from last time.")
                .font(RiffType.h1)
                .foregroundColor(RiffTheme.ink)
                .multilineTextAlignment(.center)
            Text("Continuing.")
                .font(RiffType.body)
                .foregroundColor(RiffTheme.inkMuted)
            Spacer()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) {
                if step == 3 && restoredFromAccount {
                    withAnimation { step = 4 }
                }
            }
        }
    }

    var apiKeyStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(spacing: 8) {
                        Text("Your voice engine")
                            .font(RiffType.h1)
                            .foregroundColor(RiffTheme.ink)
                        Text("This is yours, not ours. Groq is what hears you. You keep the key. I'll stay on this screen the whole time.")
                            .font(RiffType.body)
                            .multilineTextAlignment(.center)
                            .foregroundColor(RiffTheme.inkMuted)
                            .frame(maxWidth: 520)
                    }
                    .frame(maxWidth: .infinity)

                    groqBeat(
                        number: 1,
                        title: "Open Groq",
                        caption: "I'll wait. Come back when you see API Keys."
                    ) {
                        RiffButton(title: "Open Groq", kind: .primary, action: {
                            if let url = URL(string: "https://console.groq.com/keys") {
                                NSWorkspace.shared.open(url)
                            }
                        })
                    }

                    groqBeat(number: 2, title: "Create an API key", caption: "Click Create API Key. Copy the line that starts with gsk_.") {
                        groqKeysMock
                    }

                    groqBeat(number: 3, title: "Paste it here", caption: keyCaptured ? "That's it. I have it." : "The field is ready. Paste when you have the key.") {
                        SecureField("gsk_...", text: $apiKeyInput)
                            .textFieldStyle(.plain)
                            .font(RiffType.mono(13))
                            .foregroundColor(RiffTheme.ink)
                            .padding(10)
                            .frame(height: 40)
                            .background(RiffTheme.surface200)
                            .overlay(RoundedRectangle(cornerRadius: RiffTheme.radiusXS).stroke(RiffTheme.lineStrong, lineWidth: 1))
                            .focused($groqFieldFocused)
                            .onChange(of: apiKeyInput) { newValue in
                                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                isKeyValid = trimmed.hasPrefix("gsk_") && trimmed.count > 8
                                if isKeyValid && !keyCaptured {
                                    keyCaptured = true
                                    AuthLogger.log("[Onboarding] Groq key looks valid prefix=\(trimmed.prefix(7))")
                                }
                            }
                        if keyCaptured {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(RiffTheme.gain)
                                Text("That's it. I have it.")
                                    .font(RiffType.bodySM)
                                    .foregroundColor(RiffTheme.gain)
                            }
                        }
                    }

                    Text("Free Groq quota is enough to try Riff. The key stays on your Riff account.")
                        .font(RiffType.caption)
                        .foregroundColor(RiffTheme.inkFaint)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            VStack(alignment: .trailing, spacing: 6) {
                HStack {
                    RiffButton(title: "Back", kind: .ghost, action: { withAnimation { step = 2 } })
                    Spacer()
                    RiffButton(title: "Next", kind: .primary, enabled: isKeyValid, action: {
                        Task {
                            AuthLogger.log("[Onboarding] Saving Groq key then advancing to permissions")
                            await saveKey()
                            await MainActor.run { withAnimation { step = 4 } }
                        }
                    })
                }
                if !isKeyValid {
                    DisabledReason(text: "Paste a key that starts with gsk_.")
                }
            }
            .padding(.horizontal)
        }
        .onAppear {
            apiKeyInput = settings.config.api.api_key
            isKeyValid = apiKeyInput.trimmingCharacters(in: .whitespaces).starts(with: "gsk_")
            keyCaptured = isKeyValid
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                groqFieldFocused = true
            }
        }
    }

    func groqBeat<Content: View>(number: Int, title: String, caption: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(RiffType.mono(12))
                .foregroundColor(RiffTheme.onAmber)
                .frame(width: 28, height: 28)
                .background(RiffTheme.amber)
                .cornerRadius(RiffTheme.radiusXS)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(RiffType.h2).foregroundColor(RiffTheme.ink)
                Text(caption).font(RiffType.bodySM).foregroundColor(RiffTheme.inkMuted)
                content()
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RiffTheme.surface100)
        .overlay(RoundedRectangle(cornerRadius: RiffTheme.radiusSM).stroke(RiffTheme.line, lineWidth: 1))
        .cornerRadius(RiffTheme.radiusSM)
    }

    var groqKeysMock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("API Keys").font(RiffType.caption).fontWeight(.semibold).foregroundColor(RiffTheme.ink)
                Spacer()
                Text("Create API Key")
                    .font(RiffType.mono(10))
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RiffTheme.amber)
                    .foregroundColor(RiffTheme.onAmber)
                    .cornerRadius(RiffTheme.radiusXS)
            }
            Rectangle().fill(RiffTheme.line).frame(height: 1)
            HStack {
                Text("Name").font(RiffType.mono(11)).foregroundColor(RiffTheme.inkFaint).frame(maxWidth: .infinity, alignment: .leading)
                Text("Key").font(RiffType.mono(11)).foregroundColor(RiffTheme.inkFaint).frame(maxWidth: .infinity, alignment: .leading)
                Text("Created").font(RiffType.mono(11)).foregroundColor(RiffTheme.inkFaint)
            }
            HStack {
                Text("riff-mac").font(RiffType.caption).foregroundColor(RiffTheme.ink)
                Spacer()
                Text("gsk_••••••••").font(RiffType.mono(12)).foregroundColor(RiffTheme.ink)
                Spacer()
                Text("just now").font(RiffType.caption).foregroundColor(RiffTheme.inkFaint)
            }
        }
        .padding(10)
        .background(RiffTheme.surface200)
        .overlay(RoundedRectangle(cornerRadius: RiffTheme.radiusSM).stroke(RiffTheme.line, lineWidth: 1))
        .cornerRadius(RiffTheme.radiusSM)
        .frame(maxWidth: 420)
    }

    var permissionsStep: some View {
        let beat = permissionBeats[min(permissionIndex, permissionBeats.count - 1)]
        let granted = isGranted(beat.id)
        let stalled = !granted && permissionAskedAt.map { Date().timeIntervalSince($0) > 8 } == true

        return VStack(spacing: 20) {
            Text("One permission at a time")
                .font(RiffType.h1)
                .foregroundColor(RiffTheme.ink)
            Text(restoredFromAccount
                 ? "I already have your key from last time. Now I'll ask macOS, once each. This window stays open."
                 : "I'll ask macOS now. Click Allow on Riff. This window stays open and turns green when it's done.")
                .font(RiffType.body)
                .multilineTextAlignment(.center)
                .foregroundColor(RiffTheme.inkMuted)
                .frame(maxWidth: 480)

            VStack(spacing: 14) {
                Image(systemName: granted ? "checkmark" : "circle")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(granted ? RiffTheme.gain : RiffTheme.inkMuted)
                Text(beat.title)
                    .font(RiffType.h2)
                    .foregroundColor(RiffTheme.ink)
                Text(beat.why)
                    .font(RiffType.body)
                    .foregroundColor(RiffTheme.inkMuted)
                RiffTag(
                    text: granted ? "Granted" : (stalled ? "Still here" : "Required"),
                    kind: granted ? .gain : (stalled ? .amber : .neutral)
                )
                if stalled {
                    Text("In System Settings, turn on the row named Riff. If macOS asks to quit and reopen, this window stays here.")
                        .font(RiffType.bodySM)
                        .foregroundColor(RiffTheme.inkMuted)
                        .multilineTextAlignment(.center)
                }
                RiffButton(
                    title: granted ? "Continue" : "Allow \(beat.title)",
                    kind: .primary,
                    action: {
                        if granted {
                            advancePermission()
                        } else {
                            permissionAskedAt = Date()
                            requestRiffPermission(beat.id)
                        }
                    }
                )
            }
            .padding(28)
            .frame(maxWidth: 420)
            .background(granted ? RiffTheme.gainWash : RiffTheme.surface100)
            .overlay(
                RoundedRectangle(cornerRadius: RiffTheme.radiusSM)
                    .stroke(granted ? RiffTheme.gain : RiffTheme.line, lineWidth: 1)
            )
            .cornerRadius(RiffTheme.radiusSM)
            .animation(.easeInOut(duration: 0.12), value: granted)

            HStack(spacing: 8) {
                ForEach(0..<permissionBeats.count, id: \.self) { i in
                    Circle()
                        .fill(isGranted(permissionBeats[i].id) ? RiffTheme.gain : (i == permissionIndex ? RiffTheme.amber : RiffTheme.surface300))
                        .frame(width: 7, height: 7)
                }
            }

            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                HStack {
                    RiffButton(title: "Back", kind: .ghost, action: { withAnimation { step = restoredFromAccount ? 2 : 3 } })
                    Spacer()
                    RiffButton(title: "Next", kind: .primary, enabled: riffPermissions.accessibility && riffPermissions.microphoneEffective && riffPermissions.input_monitoring, action: {
                        AuthLogger.log("[Onboarding] Permissions next. accessibility=\(riffPermissions.accessibility) mic=\(riffPermissions.microphoneEffective) input=\(riffPermissions.input_monitoring)")
                        withAnimation { step = 5 }
                    })
                }
                if !(riffPermissions.accessibility && riffPermissions.microphoneEffective && riffPermissions.input_monitoring) {
                    DisabledReason(text: "Grant Microphone, Accessibility, and Keyboard to continue.")
                }
            }
        }
        .padding()
        .onAppear {
            refreshRiffPermissions()
            maybeAutoAdvancePermission()
        }
        .onReceive(Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()) { _ in
            refreshRiffPermissions()
            maybeAutoAdvancePermission()
        }
    }

    var testDriveStep: some View {
        let hint: String = {
            if testDriveSucceeded {
                return "There you are. That's a riff."
            }
            switch hudStatus.state {
            case "recording":
                return "I'm listening. Keep holding."
            case "working", "processing":
                return "Working — I'll type it in a moment."
            default:
                if driveFocused {
                    return "Hold \(RiffHotkey.keycap(settings.config.hotkey.combination)) and speak. Say anything — even hello."
                }
                return "Click the box."
            }
        }()

        return VStack(spacing: 16) {
            Text("Try it with me")
                .font(RiffType.h1)
                .foregroundColor(RiffTheme.ink)
            HStack(spacing: 8) {
                Text(hint)
                    .font(RiffType.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(testDriveSucceeded ? RiffTheme.gain : RiffTheme.inkMuted)
            }
            .frame(maxWidth: 520)
            .animation(.easeInOut(duration: 0.12), value: hint)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $testDriveText)
                    .font(RiffType.body)
                    .foregroundColor(RiffTheme.ink)
                    .padding(10)
                    .frame(minHeight: 140)
                    .focused($driveFocused)
                    .background(RiffTheme.surface200)
                    .cornerRadius(RiffTheme.radiusSM)
                    .overlay(
                        RoundedRectangle(cornerRadius: RiffTheme.radiusSM)
                            .stroke(driveFocused ? RiffTheme.focus : RiffTheme.lineStrong, lineWidth: 1)
                    )
                if testDriveText.isEmpty {
                    Text("This box is a real text field. Click it, then hold the key.")
                        .font(RiffType.bodySM)
                        .foregroundColor(RiffTheme.inkFaint)
                        .padding(18)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 24)

            if testDriveSucceeded {
                Text("I'll live in the menu bar at the top-right. There is no Dock icon. Click that Riff icon to open Home again — hold the same key in Mail, Slack, anywhere.")
                    .font(RiffType.bodySM)
                    .foregroundColor(RiffTheme.inkMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }

            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                HStack {
                    RiffButton(title: "Back", kind: .ghost, action: { withAnimation { step = 4 } })
                    Spacer()
                    RiffButton(title: "I'll try later", kind: .ghost, action: {
                        AuthLogger.log("[Onboarding] Test drive skipped")
                        completeOnboarding()
                    })
                    RiffButton(title: "Start riffing", kind: .primary, enabled: testDriveSucceeded, action: {
                        completeOnboarding()
                    })
                }
                if !testDriveSucceeded {
                    DisabledReason(text: "Hold \(RiffHotkey.keycap(settings.config.hotkey.combination)) and say something, or skip.")
                }
            }
        }
        .padding()
        .onAppear {
            testDriveBaseline = settings.history.count
            driveFocused = true
            AuthLogger.log("[Onboarding] Test drive waiting. historyCount=\(testDriveBaseline) accessibility=\(riffPermissions.accessibility)")
        }
        .onChange(of: hudStatus.state) { state in
            if ["working", "processing"].contains(state) {
                testDriveSucceeded = true
            }
        }
        .onReceive(Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()) { _ in
            refreshHudStatus()
            if settings.history.count > testDriveBaseline {
                if !testDriveSucceeded {
                    AuthLogger.log("[Onboarding] Test drive succeeded. historyCount=\(settings.history.count)")
                }
                testDriveSucceeded = true
            }
        }
    }

    func saveKey() async {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        var newConfig = settings.config
        newConfig.api.api_key = key
        newConfig.onboarding_completed = false
        settings.config = newConfig
        settings.saveConfig()
        AuthLogger.log("[Onboarding] Local Groq key written. prefix=\(key.prefix(7))")
        await authManager.saveCloudGroqKey(key)
    }

    func completeOnboarding() {
        AuthLogger.log("[Onboarding] completeOnboarding testDrive=\(testDriveSucceeded) accessibility=\(riffPermissions.accessibility)")
        var newConfig = settings.config
        newConfig.onboarding_completed = true
        settings.config = newConfig
        settings.saveConfig()
        authManager.clearPlanSelection()
        SettingsSession.update(resume: false, route: "main", section: "home", tab: "dictation", onboardingStep: 1)
    }

    func advanceAfterAccount() {
        restoringKey = true
        AuthLogger.log("[Onboarding] Restoring Groq key after account step")
        Task {
            _ = await authManager.syncGroqKeyWithCloud(localKey: settings.config.api.api_key)
            await MainActor.run {
                settings.loadConfig()
                restoringKey = false
                let key = settings.config.api.api_key.trimmingCharacters(in: .whitespacesAndNewlines)
                if key.hasPrefix("gsk_") {
                    AuthLogger.log("[Onboarding] Key present after restore — skip paste")
                    restoredFromAccount = true
                    withAnimation { step = 3 }
                } else {
                    AuthLogger.log("[Onboarding] No key after restore — show paste step")
                    restoredFromAccount = false
                    withAnimation { step = 3 }
                }
            }
        }
    }

    func persistProgress() {
        SettingsSession.update(
            resume: true,
            route: "onboarding",
            onboardingStep: step,
            permissionIndex: permissionIndex,
            restoredFromAccount: restoredFromAccount
        )
    }

    func restoreOrAdvance() {
        if let saved = SettingsSession.load(), saved.onboardingStep >= 1 {
            step = min(max(saved.onboardingStep, 1), 5)
            permissionIndex = min(max(saved.permissionIndex, 0), permissionBeats.count - 1)
            restoredFromAccount = saved.restoredFromAccount
            AuthLogger.log("[Onboarding] Restored step=\(step) permissionIndex=\(permissionIndex)")
        }
        if !authManager.isAuthenticated {
            if step > 2 { step = settings.config.onboarding_completed == true ? 2 : 1 }
            AuthLogger.log("[Onboarding] Not signed in — at step \(step)")
            return
        }
        let key = settings.config.api.api_key.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.hasPrefix("gsk_") {
            if step < 3 {
                advanceAfterAccount()
            }
            return
        }
        restoredFromAccount = true
        if step < 3 {
            AuthLogger.log("[Onboarding] Signed in with key — skip ahead to restored-key step")
            step = 3
        } else {
            AuthLogger.log("[Onboarding] Keeping restored step \(step)")
        }
    }

    func isGranted(_ id: String) -> Bool {
        switch id {
        case "microphone": return riffPermissions.microphoneEffective
        case "accessibility": return riffPermissions.accessibility
        case "input_monitoring": return riffPermissions.input_monitoring
        default: return false
        }
    }

    func advancePermission() {
        if permissionIndex < permissionBeats.count - 1 {
            permissionAskedAt = nil
            withAnimation { permissionIndex += 1 }
        } else if riffPermissions.accessibility && riffPermissions.microphoneEffective && riffPermissions.input_monitoring {
            withAnimation { step = 5 }
        }
    }

    func maybeAutoAdvancePermission() {
        guard step == 4, permissionIndex < permissionBeats.count - 1 else { return }
        let beat = permissionBeats[permissionIndex]
        guard isGranted(beat.id), autoAdvancedForIndex != permissionIndex else { return }
        autoAdvancedForIndex = permissionIndex
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            if step == 4 && permissionIndex == autoAdvancedForIndex && isGranted(permissionBeats[permissionIndex].id) {
                advancePermission()
            }
        }
    }

    func requestRiffPermission(_ kind: String) {
        SettingsSession.notePermissionGrant()
        persistProgress()
        AuthLogger.log("[Onboarding] Asking Riff process to prompt \(kind)")
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Riff")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let promptURL = dir.appendingPathComponent("permission_prompt")
        try? kind.data(using: .utf8)?.write(to: promptURL, options: .atomic)
    }

    func refreshRiffPermissions() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Riff")
        var next = riffPermissions
        if let data = try? Data(contentsOf: dir.appendingPathComponent("permissions_status.json")),
           let decoded = try? JSONDecoder().decode(RiffPermissionStatus.self, from: data) {
            next = decoded
        }
        if let data = try? Data(contentsOf: dir.appendingPathComponent("mic_verified.json")),
           let proof = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           (proof["verified"] as? Bool) == true {
            next.mic_verified = true
            next.microphone = true
        }
        riffPermissions = next
    }

    func refreshHudStatus() {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Riff/hud_status.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(HudStatus.self, from: data) else {
            return
        }
        hudStatus = decoded
    }
}

struct RiffPermissionStatus: Codable, Equatable {
    var accessibility: Bool = false
    var microphone: Bool = false
    var input_monitoring: Bool = false
    var updated_at: Double? = nil
    var mic_verified: Bool? = nil
    var microphone_status: String? = nil

    var microphoneEffective: Bool {
        microphone || mic_verified == true || microphone_status == "authorized"
    }
}

import SwiftUI
import ApplicationServices
import AVFoundation

struct OnboardingView: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var authManager: SwiftAuthManager
    @State private var step = 1
    @State private var apiKeyInput = ""
    @State private var isKeyValid = false
    @State private var micGranted = false
    @State private var testDriveBaseline = 0
    @State private var testDriveSucceeded = false
    @State private var waitingForPayment = false

    private var paidManagedKey: Bool {
        authManager.isPaidPlan
    }

    var body: some View {
        VStack(spacing: 16) {
            progress
            if step == 1 {
                welcomeStep
            } else if step == 2 {
                accountStep
            } else if step == 3 {
                planStep
            } else if step == 4 {
                apiKeyStep
            } else if step == 5 {
                permissionsStep
            } else {
                testDriveStep
            }
        }
        .padding()
        .frame(minWidth: 780, minHeight: 560)
        .background(Color(.windowBackgroundColor))
        .onAppear { advanceIfPossible() }
        .onChange(of: authManager.isAuthenticated) { authenticated in
            if authenticated && step <= 2 {
                advanceAfterAccount()
            }
        }
        .onChange(of: authManager.isPaidPlan) { paid in
            if paid && (step == 3 || step == 4) {
                waitingForPayment = false
                authManager.clearPlanSelection()
                withAnimation { step = 5 }
            }
        }
    }

    var progress: some View {
        HStack(spacing: 8) {
            ForEach(1...6, id: \.self) { n in
                Circle()
                    .fill(n <= step ? Color.accentColor : Color.gray.opacity(0.25))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.top, 8)
    }

    var welcomeStep: some View {
        VStack(spacing: 24) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                .resizable()
                .frame(width: 88, height: 88)
            Text("Welcome to Riff")
                .font(.system(size: 28, weight: .bold))
            Text("Create an account, pick a plan, then grant permissions from the next screens.\nTakes about a minute.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Spacer()
            Button("Get Started") {
                withAnimation { step = 2 }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }

    var accountStep: some View {
        VStack {
            LoginView(compact: true)
            Spacer()
            HStack {
                Button("Back") { withAnimation { step = 1 } }
                Spacer()
            }
        }
        .padding(.horizontal)
    }

    var planStep: some View {
        VStack(spacing: 12) {
            SubscriptionView(
                embedded: true,
                onChoseFree: {
                    waitingForPayment = false
                    withAnimation { step = 4 }
                },
                onPaidCheckoutOpened: {
                    waitingForPayment = true
                }
            )
            .environmentObject(authManager)

            if waitingForPayment {
                Text("Finish checkout in your browser. This screen continues when payment completes.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button("Continue with Free instead") {
                    waitingForPayment = false
                    withAnimation { step = 4 }
                }
            }

            HStack {
                Button("Back") { withAnimation { step = 2 } }
                Spacer()
            }
        }
        .padding(.horizontal, 8)
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            guard waitingForPayment else { return }
            Task {
                try? await authManager.validateSubscription()
                if authManager.isPaidPlan {
                    await MainActor.run {
                        waitingForPayment = false
                        authManager.clearPlanSelection()
                        withAnimation { step = 5 }
                    }
                }
            }
        }
    }

    var apiKeyStep: some View {
        VStack(spacing: 20) {
            Text("Connect Groq")
                .font(.title)
                .fontWeight(.bold)
            Text("Free accounts use your own Groq key. Paid plans skip this.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            VStack(alignment: .leading) {
                Text("Secret Key").font(.caption).foregroundColor(.secondary)
                SecureField("gsk_...", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: apiKeyInput) { newValue in
                        isKeyValid = newValue.trimmingCharacters(in: .whitespaces).starts(with: "gsk_")
                    }
                Link("Get a free key at console.groq.com", destination: URL(string: "https://console.groq.com/keys")!)
                    .font(.caption)
            }
            .padding(.horizontal)

            Spacer()
            HStack {
                Button("Back") {
                    withAnimation { step = authManager.needsPlanSelection ? 3 : 2 }
                }
                Button("Next") {
                    saveKey()
                    withAnimation { step = 5 }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isKeyValid)
            }
        }
        .padding()
        .onAppear {
            if paidManagedKey {
                withAnimation { step = 5 }
            }
            apiKeyInput = settings.config.api.api_key
            isKeyValid = apiKeyInput.trimmingCharacters(in: .whitespaces).starts(with: "gsk_")
        }
    }

    var permissionsStep: some View {
        VStack(spacing: 16) {
            Text("Grant Permissions")
                .font(.title)
                .fontWeight(.bold)
            Text("Riff stays in the menu bar. This window is Settings — you can close it and reopen it from the tray.\nClick each button below. macOS asks only when you click.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                permissionCard(
                    title: "Accessibility",
                    granted: isAccessibilityTrusted(),
                    actionTitle: "Allow",
                    action: promptAccessibility
                )
                permissionCard(
                    title: "Microphone",
                    granted: micGranted,
                    actionTitle: "Allow Mic",
                    action: requestMic
                )
            }

            HStack(spacing: 12) {
                permissionCard(
                    title: "Input Monitoring",
                    granted: false,
                    actionTitle: "Open Settings",
                    action: openInputSettings
                )
                permissionCard(
                    title: "Paste (Automation)",
                    granted: false,
                    actionTitle: "Allow Paste",
                    action: promptAutomation
                )
            }

            Spacer()
            HStack {
                Button("Back") {
                    withAnimation { step = paidManagedKey ? (authManager.needsPlanSelection ? 3 : 2) : 4 }
                }
                Button("Next") { withAnimation { step = 6 } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isAccessibilityTrusted())
            }
        }
        .padding()
        .onAppear { refreshMicStatus() }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            refreshMicStatus()
        }
    }

    func permissionCard(title: String, granted: Bool, actionTitle: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(granted ? .green : .secondary)
                .font(.title)
            Text(title).fontWeight(.semibold)
            Text(granted ? "Granted" : "Required")
                .font(.caption)
                .foregroundColor(granted ? .green : .secondary)
            Button(actionTitle, action: action)
                .font(.caption)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(10)
    }

    var testDriveStep: some View {
        VStack(spacing: 16) {
            Text("Test Drive")
                .font(.title)
                .fontWeight(.bold)
            Text("Hold Left Control (ctrl) and speak. Riff will transcribe into the box below once a riff lands in History.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            if testDriveSucceeded {
                Text("First riff received. You're ready.")
                    .foregroundColor(.green)
                    .fontWeight(.semibold)
            } else {
                Text("Waiting for a riff…")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }

            Spacer()
            HStack {
                Button("Back") { withAnimation { step = 5 } }
                Button("Start Riffing") {
                    completeOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!testDriveSucceeded && !isAccessibilityTrusted())
            }
            Text("You can continue if Accessibility is granted even without a test riff.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .onAppear {
            testDriveBaseline = settings.history.count
        }
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            if settings.history.count > testDriveBaseline {
                testDriveSucceeded = true
            }
        }
    }

    func saveKey() {
        var newConfig = settings.config
        newConfig.api.api_key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        newConfig.onboarding_completed = false
        settings.config = newConfig
        settings.saveConfig()
    }

    func completeOnboarding() {
        var newConfig = settings.config
        newConfig.onboarding_completed = true
        settings.config = newConfig
        settings.saveConfig()
        authManager.clearPlanSelection()
    }

    func advanceAfterAccount() {
        if authManager.needsPlanSelection && !paidManagedKey {
            withAnimation { step = 3 }
        } else if paidManagedKey {
            withAnimation { step = 5 }
        } else {
            withAnimation { step = 4 }
        }
    }

    func advanceIfPossible() {
        if !authManager.isAuthenticated {
            step = settings.config.onboarding_completed == true ? 2 : 1
            return
        }
        if authManager.needsPlanSelection && !paidManagedKey {
            step = 3
            return
        }
        if !paidManagedKey && settings.config.api.api_key.isEmpty {
            step = 4
            return
        }
        if !(settings.config.onboarding_completed ?? false) {
            step = 5
        }
    }

    func promptAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        openAccessibilitySettings()
    }

    func promptAutomation() {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", "tell application \"System Events\" to get name of first process"]
        try? proc.run()
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func openInputSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }

    func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func refreshMicStatus() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            micGranted = true
        default:
            break
        }
    }

    func requestMic() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async { micGranted = granted }
        }
    }
}

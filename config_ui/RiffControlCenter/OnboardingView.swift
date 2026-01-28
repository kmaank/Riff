import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var settings: SettingsManager
    @State private var step = 1
    @State private var apiKeyInput = ""
    @State private var isKeyValid = false
    @State private var selectedScriptMode = "english_mixed"
    @State private var testInput = "Click here, hold your trigger key, and speak..."

    var body: some View {
        VStack(spacing: 20) {
            if step == 1 {
                welcomeStep
            } else if step == 2 {
                apiKeyStep
            } else if step == 3 {
                scriptModeStep
            } else if step == 4 {
                advancedPermissionsStep
            } else if step == 5 {
                testStep
            }
        }
        .padding()
        .frame(width: 700, height: 500)
        .background(Color(.windowBackgroundColor))
    }
    
    // MARK: - Step 1: Welcome
    var welcomeStep: some View {
        VStack(spacing: 30) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage()) 
                .resizable()
                .frame(width: 100, height: 100)
            
            Text("Welcome to Riff")
                .font(.system(size: 32, weight: .bold))
            
            Text("Stop typing like a robot. Start sounding like a human.\nLet's make you lively and riffing in just a minute!")
                .multilineTextAlignment(.center)
                .font(.title3)
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
    
    // MARK: - Step 2: API Key
    var apiKeyStep: some View {
        VStack(spacing: 25) {
            Text("Connect Your Brain")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Riff runs on Groq. It’s the only engine fast enough to keep up with your mouth.\nGrab a free key to start the speed.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading) {
                Text("Secret Key")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
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
                    withAnimation { step = 1 }
                }
                
                Button("Next") {
                    saveKey()
                    withAnimation { step = 3 }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isKeyValid)
            }
        }
        .padding()
    }
    


    // MARK: - Step 3: Script Mode Selection
    var scriptModeStep: some View {
        VStack(spacing: 25) {
            Text("Choose Your Script Mode")
                .font(.title)
                .fontWeight(.bold)

            Text("How should Riff handle multilingual dictation?")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            HStack(spacing: 15) {
                ScriptModeOnboardingCard(
                    mode: "english_mixed",
                    title: "English Mixed",
                    badge: "Recommended",
                    icon: "textformat.abc",
                    example: "Mujhe lagta hai we should meet",
                    description: "Romanizes non-English, keeps vernacular",
                    isSelected: selectedScriptMode == "english_mixed",
                    action: { selectedScriptMode = "english_mixed" }
                )

                ScriptModeOnboardingCard(
                    mode: "english_translated",
                    title: "English Translated",
                    badge: "",
                    icon: "character.book.closed",
                    example: "I think we should meet",
                    description: "Translates everything to English",
                    isSelected: selectedScriptMode == "english_translated",
                    action: { selectedScriptMode = "english_translated" }
                )

                ScriptModeOnboardingCard(
                    mode: "original_mixed",
                    title: "Original Mixed",
                    badge: "",
                    icon: "globe",
                    example: "मुझे लगता है we should meet",
                    description: "Uses original script (Devanagari, etc.)",
                    isSelected: selectedScriptMode == "original_mixed",
                    action: { selectedScriptMode = "original_mixed" }
                )
            }

            Spacer()

            HStack {
                Button("Back") {
                    withAnimation { step = 2 }
                }

                Button("Next") {
                    saveScriptMode()
                    withAnimation { step = 4 }
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
        .padding()
    }

    // MARK: - Step 4: Grant Permissions (Microphone, Accessibility, Input)
    var advancedPermissionsStep: some View {
        ScrollView {
            VStack(spacing: 25) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)

                Text("Grant Permissions")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Riff needs access to See (Accessibility) and Type (Input).")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                // 1. Accessibility & Input (Renumbered to 1 since Mic is gone)
                // Note: Keeping the UI focused on interactions that require explicit system settings.
                // Microphone will be asked on-demand during Test Drive.

                // 2. Accessibility & Input
                VStack(alignment: .center, spacing: 10) {
                // 1. Accessibility & Input
                VStack(alignment: .center, spacing: 10) {
                    Text("1. Accessibility & Input Monitoring")
                        .font(.headline)

                    Text("**Note:** If Riff is already listed, you must reset it to ensure a clean link.")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.bottom, 5)
                        .multilineTextAlignment(.center)

                    Text("**Remove:** Select Riff and click the [ - ] (minus) button.")
                    Text("**Re-add:** Click the [ + ] (plus) button.")
                    Text("**Select:** Go to Applications > Double-click Riff.")
                    Text("**Enable:** Ensure the toggle is ON.")
                }
                .font(.system(size: 13))
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

                if isAccessibilityTrusted() {
                    Text("Accessibility Granted! 🎉")
                        .foregroundColor(.green)
                        .fontWeight(.bold)
                } else {
                    Text("Waiting for Accessibility...")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }

                HStack {
                    Button("Open Accessibility Settings") {
                        openAccessibilitySettings()
                    }
                    .font(.caption)

                    Button("Open Input Settings") {
                        openInputSettings()
                    }
                    .font(.caption)
                }

                Spacer()

                HStack {
                    Button("Back") {
                        withAnimation { step = 3 }
                    }

                    Button("Next") {
                        withAnimation { step = 5 }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding()
        }
        // Poll for permission changes
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            let _ = isAccessibilityTrusted()
        }
    }

    // MARK: - Step 5: Test Drive
    var testStep: some View {
        VStack(spacing: 20) {
            Text("Test Drive")
                .font(.title)
                .fontWeight(.bold)

            Text("1. Press Left Ctrl. Grant microphone access.\n2. Hold Left Ctrl to speak.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            TextEditor(text: $testInput)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .padding(5)
                .background(Color.white)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                .frame(height: 150)

            Spacer()

            HStack {
                Button("Back") {
                    withAnimation { step = 4 }
                }

                Button("Start Riffing") {
                    completeOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding()
    }

    func saveKey() {
        var newConfig = settings.config
        newConfig.api.api_key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        // Ensure flag keeps false
        newConfig.onboarding_completed = false
        settings.config = newConfig
        settings.saveConfig()
    }

    func saveScriptMode() {
        var newConfig = settings.config
        newConfig.script_mode.active_mode = selectedScriptMode
        settings.config = newConfig
        settings.saveConfig()
    }

    func completeOnboarding() {
        var newConfig = settings.config
        newConfig.onboarding_completed = true
        settings.config = newConfig
        settings.saveConfig()
    }
    
    func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }
    
    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
    
    func openInputSettings() {
        // macOS Input Monitoring URL
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }
    
    func isAccessibilityTrusted() -> Bool {
        return AXIsProcessTrusted()
    }
    
    func quitAndRestart() {
         NSApplication.shared.terminate(nil)
    }
}

struct ScriptModeOnboardingCard: View {
    let mode: String
    let title: String
    let badge: String
    let icon: String
    let example: String
    let description: String
    let isSelected: Bool
    let action: () -> Void

    var color: Color {
        switch mode {
        case "english_mixed": return .green
        case "english_translated": return .blue
        case "original_mixed": return .purple
        default: return .gray
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(isSelected ? .white : color)
                    .frame(maxWidth: .infinity, alignment: .leading)

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
                        .lineLimit(2)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? color : Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(isSelected ? 0.2 : 0.05), radius: isSelected ? 6 : 2, x: 0, y: isSelected ? 3 : 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? color.opacity(0.0) : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

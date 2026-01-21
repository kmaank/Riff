import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var settings: SettingsManager
    @State private var step = 1
    @State private var apiKeyInput = ""
    @State private var isKeyValid = false
    @State private var testInput = "Click here, hold your trigger key, and speak..."
    
    var body: some View {
        VStack(spacing: 20) {
            if step == 1 {
                welcomeStep
            } else if step == 2 {
                apiKeyStep
            } else if step == 3 {
                micStep
            } else if step == 4 {
                advancedPermissionsStep
            } else if step == 5 {
                testStep
            }
        }
        .padding()
        .frame(width: 600, height: 400)
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
    
    // MARK: - Step 3: Microphone Permission
    var micStep: some View {
        VStack(spacing: 25) {
            Image(systemName: "mic.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Grant Permissions")
                .font(.title)
                .fontWeight(.bold)
                
            Text("Riff needs access to Hear (Mic), See (Accessibility), and Type (Input).")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            VStack(alignment: .center, spacing: 10) {
                 Text("1. Enable Microphone")
                    .font(.headline)
                
                Text("**Hold Left Control for 2 seconds.**")
                Text("When the pop-up appears, click **Open System Settings**.")
                Text("Toggle ON for Riff.")
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            
            Button("Open Microphone Settings") {
                openMicrophoneSettings()
            }
            .font(.caption)
            
            Spacer()
            
            HStack {
                Button("Back") {
                    withAnimation { step = 2 }
                }
                
                Button("Next") {
                     withAnimation { step = 4 }
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
        .padding()
    }

    // MARK: - Step 4: Accessibility & Input
    var advancedPermissionsStep: some View {
        VStack(spacing: 20) {
            Text("2. Accessibility & Input")
                .font(.title2)
                .fontWeight(.bold)

            VStack(alignment: .center, spacing: 5) {
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
            
            Text("Click below, hold your trigger key (Left Ctrl), and speak.")
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

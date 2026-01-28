import SwiftUI

struct KeysView: View {
    @EnvironmentObject var settings: SettingsManager
    
    // Common keys map to pynput names
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
            VStack(alignment: .leading, spacing: 30) {
                Text("Keys & Permissions")
                    .font(.title2)
                    .bold()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Push-to-Talk Key")
                        .font(.headline)
                    Text("Press and hold this key to speak.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("", selection: $settings.config.hotkey.combination) {
                        ForEach(availableKeys, id: \.1) { name, value in
                            Text(name).tag(value)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                    .onChange(of: settings.config.hotkey.combination) { _ in
                        settings.saveConfig()
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(10)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Latch Mode")
                        .font(.headline)

                    HStack(spacing: 15) {
                        Image(systemName: "lock.open.fill")
                            .font(.title)
                            .foregroundStyle(.orange)

                        VStack(alignment: .leading) {
                            Text("Shift + Trigger Key")
                                .bold()
                            Text("Hold Shift while pressing your trigger key to lock recording ON. Press trigger again to stop.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(10)

                // Permissions Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Permissions")
                        .font(.headline)

                    Text("Riff requires Microphone, Accessibility, and Input Monitoring permissions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 8) {
                        Button("Open Microphone Settings") {
                            openMicrophoneSettings()
                        }
                        .buttonStyle(.bordered)

                        Button("Open Accessibility Settings") {
                            openAccessibilitySettings()
                        }
                        .buttonStyle(.bordered)

                        Button("Open Input Monitoring Settings") {
                            openInputSettings()
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(10)

                Spacer()
            }
            .padding(30)
        }
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
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }
}

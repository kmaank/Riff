//
//  AccountView.swift
//  RiffControlCenter
//
//  Account management view with subscription status and billing
//

import SwiftUI

struct AccountView: View {
    @EnvironmentObject var authManager: SwiftAuthManager
    @EnvironmentObject var settings: SettingsManager
    @State private var keySaveTask: Task<Void, Never>?

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        userInfoSection
                        Divider()
                        apiKeySection
                        Divider()
                        signOutButton
                        Spacer()
                    }
                    .padding(30)
                }
            } else {
                LoginView(compact: true)
            }
        }
    }

    @ViewBuilder
    private var userInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Account")
                .font(.title2)
                .bold()

            HStack(spacing: 16) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 60, height: 60)
                    .overlay(
                        Text(String(authManager.userEmail.prefix(1)).uppercased())
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(authManager.userEmail)
                        .font(.body)
                        .fontWeight(.medium)

                    Text("Member since \(authManager.memberSince.isEmpty ? memberSinceDate() : authManager.memberSince)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(20)
            .background(Color.gray.opacity(0.08))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("API Key")
                .font(.title2)
                .bold()

            Text("Paste once. Encrypted on your account so Mac, Android, and reinstalls restore it after login. Sign out clears it from this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)

            SecureField("gsk_...", text: Binding(
                get: { settings.config.api.api_key },
                set: { newValue in
                    settings.config.api.api_key = newValue
                    settings.saveConfig()
                    scheduleCloudSave(newValue)
                }
            ))
            .textFieldStyle(.plain)
            .font(.system(.body, design: .monospaced))
            .padding(12)
            .background(Color.gray.opacity(0.08))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
            )

            Link("Get your free API key from Groq →", destination: URL(string: "https://console.groq.com")!)
                .font(.caption)
                .foregroundStyle(.blue)
        }
    }

    private var signOutButton: some View {
        Button(action: {
            authManager.signOut()
            settings.loadConfig()
        }) {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("Sign Out")
            }
            .foregroundStyle(.red)
        }
        .buttonStyle(.plain)
    }

    private func scheduleCloudSave(_ key: String) {
        keySaveTask?.cancel()
        keySaveTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await authManager.saveCloudGroqKey(key)
        }
    }

    private func memberSinceDate() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: Date())
    }
}

struct AccountView_Previews: PreviewProvider {
    static var previews: some View {
        AccountView()
            .environmentObject(SwiftAuthManager())
            .environmentObject(SettingsManager())
    }
}

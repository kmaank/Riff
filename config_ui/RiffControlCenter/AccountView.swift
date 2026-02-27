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
    @State private var showSubscriptionView: Bool = false
    @State private var isLoadingPortal: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                userInfoSection
                Divider()
                subscriptionSection
                Divider()
                if authManager.subscriptionTier == "free" {
                    apiKeySection
                    Divider()
                }
                signOutButton
                Spacer()
            }
            .padding(30)
        }
        .sheet(isPresented: $showSubscriptionView) {
            SubscriptionView()
                .environmentObject(authManager)
        }
        .task {
            if authManager.isAuthenticated {
                try? await authManager.validateSubscription()
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

                    Text("Member since \(memberSinceDate())")
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
    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Subscription")
                .font(.title2)
                .bold()

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tierDisplayName())
                            .font(.headline)

                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusColor())
                                .frame(width: 8, height: 8)

                            Text(authManager.subscriptionStatus.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    tierBadge()
                }

                if let quota = authManager.quota {
                    quotaUsageSection(quota: quota)
                }

                subscriptionActionButtons
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
    private func quotaUsageSection(quota: QuotaInfo) -> some View {
        VStack(spacing: 12) {
            if let riffsLimit = quota.riffsLimit {
                UsageBar(
                    label: "Riffs",
                    used: quota.riffsUsed,
                    limit: riffsLimit,
                    unit: "riffs"
                )
            } else {
                HStack {
                    Text("Riffs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(quota.riffsUsed) riffs")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("∞")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let secondsLimit = quota.secondsLimit {
                UsageBar(
                    label: "Recording Time",
                    used: Int(quota.secondsUsed / 60),
                    limit: secondsLimit / 60,
                    unit: "minutes"
                )
            } else {
                HStack {
                    Text("Recording Time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(quota.secondsUsed / 60)) minutes")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("∞")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var subscriptionActionButtons: some View {
        HStack(spacing: 12) {
            if authManager.subscriptionTier == "free" || authManager.subscriptionTier == "starter" {
                Button(action: { showSubscriptionView = true }) {
                    HStack {
                        Image(systemName: "arrow.up.circle.fill")
                        Text("Upgrade")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }

            if authManager.subscriptionTier != "free" {
                Button(action: openBillingPortal) {
                    HStack {
                        if isLoadingPortal {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "creditcard.circle")
                        }
                        Text("Manage Billing")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(Color.gray.opacity(0.08))
                    .foregroundStyle(.primary)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isLoadingPortal)
            }
        }
    }

    @ViewBuilder
    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("API Key")
                .font(.title2)
                .bold()

            Text("Free tier users need to provide their own Groq API key")
                .font(.caption)
                .foregroundStyle(.secondary)

            SecureField("gsk_...", text: Binding(
                get: { settings.config.api.api_key },
                set: { newValue in
                    settings.config.api.api_key = newValue
                    settings.saveConfig()
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
        Button(action: { authManager.signOut() }) {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("Sign Out")
            }
            .foregroundStyle(.red)
        }
        .buttonStyle(.plain)
    }

    private func tierDisplayName() -> String {
        switch authManager.subscriptionTier {
        case "free": return "Free (BYOK)"
        case "starter": return "Starter"
        case "pro": return "Pro"
        case "lifetime": return "Lifetime"
        default: return authManager.subscriptionTier.capitalized
        }
    }

    private func tierBadge() -> some View {
        Text(authManager.subscriptionTier.uppercased())
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(tierColor())
            .cornerRadius(6)
    }

    private func tierColor() -> Color {
        switch authManager.subscriptionTier {
        case "free": return .gray
        case "starter": return .blue
        case "pro": return .purple
        case "lifetime": return .orange
        default: return .gray
        }
    }

    private func statusColor() -> Color {
        switch authManager.subscriptionStatus {
        case "active": return .green
        case "past_due": return .orange
        case "canceled", "expired": return .red
        default: return .gray
        }
    }

    private func memberSinceDate() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: Date())  // TODO: Get actual signup date
    }

    private func openBillingPortal() {
        isLoadingPortal = true

        Task {
            guard let accessToken = UserDefaults.standard.string(forKey: "supabase_access_token") else {
                isLoadingPortal = false
                return
            }

            let url = URL(string: "\(authManager.supabaseUrl)/functions/v1/create-portal")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(authManager.supabaseAnonKey, forHTTPHeaderField: "apikey")

            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                if let result = try? JSONDecoder().decode(PortalResponse.self, from: data),
                   let portalUrl = URL(string: result.url) {
                    await MainActor.run {
                        NSWorkspace.shared.open(portalUrl)
                        isLoadingPortal = false
                    }
                }
            } catch {
                await MainActor.run {
                    isLoadingPortal = false
                }
            }
        }
    }
}

struct UsageBar: View {
    let label: String
    let used: Int
    let limit: Int
    let unit: String

    private var percentage: Double {
        min(Double(used) / Double(limit), 1.0)
    }

    private var isNearLimit: Bool {
        percentage >= 0.8
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(used) / \(limit) \(unit)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(isNearLimit ? .red : .primary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.15))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(isNearLimit ? Color.red : Color.blue)
                        .frame(width: geometry.size.width * percentage)
                }
            }
            .frame(height: 8)
        }
    }
}

struct PortalResponse: Codable {
    let url: String
}

#Preview {
    AccountView()
        .environmentObject(SwiftAuthManager())
        .environmentObject(SettingsManager())
}

//
//  SubscriptionView.swift
//  RiffControlCenter
//
//  Subscription tier selection and upgrade view
//

import SwiftUI

struct SubscriptionView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: SwiftAuthManager
    @State private var isCreatingCheckout: Bool = false
    @State private var selectedTier: String = ""

    let tiers: [(id: String, name: String, price: String, priceDetail: String, features: [String], badge: String, color: Color)] = [
        (
            id: "free",
            name: "Free",
            price: "$0",
            priceDetail: "Bring Your Own Key",
            features: [
                "100 riffs per month",
                "Unlimited recording time",
                "Basic styles (clean, casual)",
                "Your own Groq API key",
                "Cloud history sync"
            ],
            badge: "Current",
            color: .gray
        ),
        (
            id: "starter",
            name: "Starter",
            price: "$9.99",
            priceDetail: "per month",
            features: [
                "500 riffs per month",
                "2 hours recording time",
                "All 4 styles",
                "Managed API key (no setup)",
                "Cloud history sync",
                "Priority support"
            ],
            badge: "Popular",
            color: .blue
        ),
        (
            id: "pro",
            name: "Pro",
            price: "$19.99",
            priceDetail: "per month",
            features: [
                "Unlimited riffs",
                "Unlimited recording time",
                "All styles + custom prompts",
                "Managed API key",
                "Cloud history sync",
                "Priority support",
                "Early access to new features"
            ],
            badge: "Best Value",
            color: .purple
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Choose Your Plan")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Upgrade anytime, cancel anytime")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(30)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Tier Cards
            ScrollView {
                HStack(alignment: .top, spacing: 20) {
                    ForEach(tiers, id: \.id) { tier in
                        TierCard(
                            tier: tier,
                            isCurrentTier: authManager.subscriptionTier == tier.id,
                            isSelected: selectedTier == tier.id,
                            isLoading: isCreatingCheckout && selectedTier == tier.id,
                            onSelect: {
                                if tier.id != "free" && tier.id != authManager.subscriptionTier {
                                    createCheckoutSession(for: tier.id)
                                }
                            }
                        )
                    }
                }
                .padding(30)

                // Lifetime Option
                VStack(alignment: .leading, spacing: 16) {
                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Lifetime Deal")
                                    .font(.title2)
                                    .fontWeight(.bold)

                                Text("LIMITED TIME")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange)
                                    .cornerRadius(4)
                            }

                            Text("Pay once, use forever. Get Pro features for life.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("$149")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(.orange)

                            Text("one-time payment")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Button(action: { createCheckoutSession(for: "lifetime") }) {
                            HStack {
                                if isCreatingCheckout && selectedTier == "lifetime" {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .scaleEffect(0.8)
                                        .tint(.white)
                                } else {
                                    Image(systemName: "sparkles")
                                    Text("Get Lifetime")
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.orange)
                            .foregroundStyle(.white)
                            .cornerRadius(8)
                            .fontWeight(.semibold)
                        }
                        .buttonStyle(.plain)
                        .disabled(isCreatingCheckout || authManager.subscriptionTier == "lifetime")
                    }
                    .padding(24)
                    .background(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.1), Color.orange.opacity(0.05)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 2)
                    )
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 30)

                // FAQ / Info
                VStack(alignment: .leading, spacing: 12) {
                    Text("Frequently Asked Questions")
                        .font(.headline)
                        .padding(.bottom, 4)

                    FAQItem(
                        question: "Can I change plans later?",
                        answer: "Yes! Upgrade or downgrade anytime. Changes take effect at your next billing cycle."
                    )

                    FAQItem(
                        question: "What payment methods do you accept?",
                        answer: "We accept all major credit cards via Stripe. All payments are secure and encrypted."
                    )

                    FAQItem(
                        question: "Can I cancel anytime?",
                        answer: "Absolutely. Cancel from your account settings. You'll keep access until the end of your billing period."
                    )
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 40)
            }
        }
        .frame(width: 900, height: 700)
    }

    private func createCheckoutSession(for tier: String) {
        selectedTier = tier
        isCreatingCheckout = true

        Task {
            guard let accessToken = UserDefaults.standard.string(forKey: "supabase_access_token") else {
                await MainActor.run {
                    isCreatingCheckout = false
                }
                return
            }

            let url = URL(string: "\(authManager.supabaseUrl)/functions/v1/create-checkout")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(authManager.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: Any] = ["tier": tier]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                if let result = try? JSONDecoder().decode(CheckoutResponse.self, from: data),
                   let checkoutUrl = URL(string: result.url) {
                    await MainActor.run {
                        NSWorkspace.shared.open(checkoutUrl)
                        isCreatingCheckout = false
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isCreatingCheckout = false
                }
            }
        }
    }
}

struct TierCard: View {
    let tier: (id: String, name: String, price: String, priceDetail: String, features: [String], badge: String, color: Color)
    let isCurrentTier: Bool
    let isSelected: Bool
    let isLoading: Bool
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                if !tier.badge.isEmpty {
                    Text(tier.badge)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(tier.color)
                        .cornerRadius(4)
                }

                Text(tier.name)
                    .font(.title2)
                    .fontWeight(.bold)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(tier.price)
                        .font(.system(size: 32, weight: .bold))
                    Text(tier.priceDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Features
            VStack(alignment: .leading, spacing: 10) {
                ForEach(tier.features, id: \.self) { feature in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(tier.color)
                            .font(.system(size: 16))

                        Text(feature)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Spacer()

            // Action Button
            Button(action: onSelect) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                            .tint(.white)
                    } else {
                        Text(buttonText())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(buttonBackground())
                .foregroundStyle(buttonForeground())
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(tier.color.opacity(isCurrentTier ? 0.5 : 0), lineWidth: 2)
                )
            }
            .buttonStyle(.plain)
            .disabled(isCurrentTier || isLoading)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isCurrentTier ? tier.color : Color.gray.opacity(0.15), lineWidth: isCurrentTier ? 2 : 1)
        )
    }

    private func buttonText() -> String {
        if isCurrentTier {
            return "Current Plan"
        } else if tier.id == "free" {
            return "Downgrade"
        } else {
            return "Select \(tier.name)"
        }
    }

    private func buttonBackground() -> Color {
        if isCurrentTier {
            return Color.gray.opacity(0.2)
        } else if tier.id == "free" {
            return Color.gray.opacity(0.2)
        } else {
            return tier.color
        }
    }

    private func buttonForeground() -> Color {
        if isCurrentTier || tier.id == "free" {
            return .secondary
        } else {
            return .white
        }
    }
}

struct FAQItem: View {
    let question: String
    let answer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(question)
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(answer)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}

struct CheckoutResponse: Codable {
    let url: String
    let sessionId: String

    enum CodingKeys: String, CodingKey {
        case url
        case sessionId = "session_id"
    }
}

#Preview {
    SubscriptionView()
        .environmentObject(SwiftAuthManager())
}

//
//  SubscriptionView.swift
//  RiffControlCenter
//
//  Free / Monthly / Yearly plan picker
//

import SwiftUI

struct SubscriptionView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: SwiftAuthManager
    @State private var isCreatingCheckout: Bool = false
    @State private var selectedTier: String = ""
    @State private var checkoutError: String?

    /// When true, used inside onboarding: no close button, Free is selectable.
    var embedded: Bool = false
    var onChoseFree: (() -> Void)? = nil
    var onPaidCheckoutOpened: (() -> Void)? = nil

    let tiers: [(id: String, name: String, price: String, priceDetail: String, features: [String], badge: String, color: Color)] = [
        (
            id: "free",
            name: "Free",
            price: "$0",
            priceDetail: "Bring your own Groq key",
            features: [
                "100 riffs per month",
                "Basic styles (clean, casual)",
                "Your own Groq API key",
                "Cloud history sync"
            ],
            badge: "BYOK",
            color: .gray
        ),
        (
            id: "monthly",
            name: "Monthly",
            price: "$9.99",
            priceDetail: "per month",
            features: [
                "Unlimited riffs",
                "All styles + custom prompts",
                "Managed Groq key — no setup",
                "Cloud history sync",
                "Cancel anytime"
            ],
            badge: "Popular",
            color: .blue
        ),
        (
            id: "yearly",
            name: "Yearly",
            price: "$79",
            priceDetail: "per year",
            features: [
                "Everything in Monthly",
                "Two months free vs monthly",
                "Managed Groq key — no setup",
                "Cloud history sync",
                "Best value if you riff daily"
            ],
            badge: "Best Value",
            color: .purple
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(embedded ? "Choose your plan" : "Change your plan")
                        .font(.title)
                        .fontWeight(.bold)

                    Text(embedded
                         ? "Start free with your own key, or subscribe and skip Groq setup."
                         : "Upgrade anytime, cancel anytime")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !embedded {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(embedded ? 16 : 30)

            Divider()

            ScrollView {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(tiers, id: \.id) { tier in
                        TierCard(
                            tier: tier,
                            isCurrentTier: !embedded && authManager.subscriptionTier == tier.id,
                            isSelected: selectedTier == tier.id,
                            isLoading: isCreatingCheckout && selectedTier == tier.id,
                            embedded: embedded,
                            onSelect: {
                                if tier.id == "free" {
                                    if embedded {
                                        onChoseFree?()
                                    }
                                } else if tier.id != authManager.subscriptionTier {
                                    createCheckoutSession(for: tier.id)
                                }
                            }
                        )
                    }
                }
                .padding(embedded ? 16 : 30)

                if let checkoutError {
                    Text(checkoutError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                if !embedded {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Frequently Asked Questions")
                            .font(.headline)
                            .padding(.bottom, 4)

                        FAQItem(
                            question: "Can I change plans later?",
                            answer: "Yes. Upgrade or switch from Account anytime. Changes take effect at your next billing cycle."
                        )

                        FAQItem(
                            question: "What do I get if I stay on Free?",
                            answer: "You use your own Groq API key. Paid monthly and yearly plans include a managed key so you can skip that setup."
                        )

                        FAQItem(
                            question: "Can I cancel anytime?",
                            answer: "Yes. Cancel from Account → Manage Billing. You keep access until the end of the billing period."
                        )
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 40)
                }
            }
        }
        .frame(width: embedded ? nil : 900, height: embedded ? nil : 700)
    }

    private func createCheckoutSession(for tier: String) {
        selectedTier = tier
        isCreatingCheckout = true
        checkoutError = nil

        Task {
            guard let accessToken = UserDefaults.standard.string(forKey: "supabase_access_token") else {
                await MainActor.run {
                    isCreatingCheckout = false
                    checkoutError = "Please sign in again, then retry."
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
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                    let message = (try? JSONDecoder().decode(CheckoutError.self, from: data))?.error
                        ?? "Could not start checkout. Price IDs may not be configured yet."
                    await MainActor.run {
                        isCreatingCheckout = false
                        checkoutError = message
                    }
                    return
                }
                if let result = try? JSONDecoder().decode(CheckoutResponse.self, from: data),
                   let checkoutUrl = URL(string: result.url) {
                    await MainActor.run {
                        NSWorkspace.shared.open(checkoutUrl)
                        isCreatingCheckout = false
                        if embedded {
                            onPaidCheckoutOpened?()
                        } else {
                            dismiss()
                        }
                    }
                } else {
                    await MainActor.run {
                        isCreatingCheckout = false
                        checkoutError = "Could not start checkout. Try again in a moment."
                    }
                }
            } catch {
                await MainActor.run {
                    isCreatingCheckout = false
                    checkoutError = error.localizedDescription
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
    var embedded: Bool = false
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
            return embedded ? "Continue with Free" : "Stay on Free"
        } else {
            return embedded ? "Subscribe" : "Select \(tier.name)"
        }
    }

    private func buttonBackground() -> Color {
        if isCurrentTier {
            return Color.gray.opacity(0.2)
        } else if tier.id == "free" {
            return embedded ? Color.gray.opacity(0.25) : Color.gray.opacity(0.2)
        } else {
            return tier.color
        }
    }

    private func buttonForeground() -> Color {
        if isCurrentTier {
            return .secondary
        } else if tier.id == "free" {
            return embedded ? .primary : .secondary
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

private struct CheckoutError: Codable {
    let error: String?
}

struct SubscriptionView_Previews: PreviewProvider {
    static var previews: some View {
        SubscriptionView()
            .environmentObject(SwiftAuthManager())
    }
}

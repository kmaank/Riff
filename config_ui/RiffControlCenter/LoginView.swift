//
//  LoginView.swift
//  RiffControlCenter
//
//  Login and signup view with email + OAuth options
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: SwiftAuthManager
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isSignUp: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 16) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)

                Text("Welcome to Riff")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text(isSignUp ? "Create your account to get started" : "Sign in to continue")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 60)
            .padding(.bottom, 40)

            // Form
            VStack(spacing: 16) {
                // Email field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    TextField("your@email.com", text: $email)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Color.gray.opacity(0.08))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                        )
                }

                // Password field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Password")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    SecureField("Enter your password", text: $password)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Color.gray.opacity(0.08))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                        )
                }

                // Status message (error or info)
                if let message = authManager.errorMessage {
                    let isInfo = message.starts(with: "Check your email")
                    HStack {
                        Image(systemName: isInfo ? "envelope.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(isInfo ? .green : .red)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(isInfo ? .primary : .red)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(isInfo ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                    .cornerRadius(8)
                }

                // Submit button
                Button(action: handleSubmit) {
                    HStack {
                        if authManager.isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                                .tint(.white)
                        }
                        Text(isSignUp ? "Sign Up" : "Sign In")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(8)
                }
                .disabled(email.isEmpty || password.isEmpty || authManager.isLoading)
                .opacity((email.isEmpty || password.isEmpty || authManager.isLoading) ? 0.6 : 1.0)

                // Toggle sign in/up
                Button(action: { isSignUp.toggle() }) {
                    Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: 400)
            .padding(.horizontal, 40)

            // Divider
            HStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 1)

                Text("or")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)

                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 1)
            }
            .frame(maxWidth: 400)
            .padding(.horizontal, 40)
            .padding(.vertical, 32)

            // OAuth buttons
            VStack(spacing: 12) {
                OAuthButton(
                    icon: "g.circle.fill",
                    text: "Continue with Google",
                    color: .red,
                    action: { authManager.signInWithOAuth(provider: "google") }
                )

                OAuthButton(
                    icon: "link.circle.fill",
                    text: "Continue with GitHub",
                    color: .primary,
                    action: { authManager.signInWithOAuth(provider: "github") }
                )

                OAuthButton(
                    icon: "applelogo",
                    text: "Continue with Apple",
                    color: .primary,
                    action: { authManager.signInWithOAuth(provider: "apple") }
                )
            }
            .frame(maxWidth: 400)
            .padding(.horizontal, 40)

            Spacer()

            // Footer
            Text("By continuing, you agree to Riff's Terms of Service and Privacy Policy")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func handleSubmit() {
        Task {
            do {
                if isSignUp {
                    try await authManager.signUpWithEmail(email: email, password: password)
                } else {
                    try await authManager.signInWithEmail(email: email, password: password)
                }
            } catch {
                // Error message is already set on authManager.errorMessage by the auth methods
                // so the UI will show it automatically via the binding
            }
        }
    }
}

struct OAuthButton: View {
    let icon: String
    let text: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(text)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(Color.gray.opacity(0.08))
            .foregroundStyle(color)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView()
            .environmentObject(SwiftAuthManager())
    }
}

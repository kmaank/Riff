import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: SwiftAuthManager
    var compact: Bool = true
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isSignUp: Bool = false

    var body: some View {
        VStack(spacing: compact ? 16 : 0) {
            VStack(spacing: compact ? 8 : 16) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: compact ? 36 : 64))
                    .foregroundStyle(.blue)

                Text(isSignUp ? "Create your account" : "Sign in")
                    .font(compact ? .title2 : .largeTitle)
                    .fontWeight(.bold)

                Text(isSignUp ? "Next you'll paste your Groq key once. It follows this account." : "Use the email you signed up with")
                    .foregroundStyle(.secondary)
                    .font(compact ? .subheadline : .body)
            }
            .padding(.top, compact ? 8 : 60)
            .padding(.bottom, compact ? 8 : 40)

            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Email").font(.subheadline).fontWeight(.medium)
                    TextField("your@email.com", text: $email)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color.gray.opacity(0.08))
                        .cornerRadius(8)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Password").font(.subheadline).fontWeight(.medium)
                    SecureField("Enter your password", text: $password)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color.gray.opacity(0.08))
                        .cornerRadius(8)
                }

                if let message = authManager.errorMessage {
                    let isInfo = message.starts(with: "Check your email")
                        || message.starts(with: "This email already")
                        || message.starts(with: "If an account exists")
                    HStack(alignment: .top) {
                        Image(systemName: isInfo ? "envelope.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(isInfo ? .green : .red)
                        Text(message)
                            .font(.caption)
                            .foregroundColor(isInfo ? Color(NSColor.labelColor) : .red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(isInfo ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                    .cornerRadius(8)
                }

                Button(action: handleSubmit) {
                    HStack {
                        if authManager.isLoading {
                            ProgressView().scaleEffect(0.8).tint(.white)
                        }
                        Text(isSignUp ? "Sign Up" : "Sign In").fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(8)
                }
                .disabled(email.isEmpty || password.isEmpty || authManager.isLoading)
                .opacity((email.isEmpty || password.isEmpty || authManager.isLoading) ? 0.6 : 1.0)

                if !isSignUp {
                    Button("Forgot password?") {
                        Task { await authManager.sendPasswordReset(email: email) }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.blue)
                    .disabled(email.isEmpty || authManager.isLoading)
                }

                Button(action: {
                    isSignUp.toggle()
                    authManager.errorMessage = nil
                }) {
                    Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, compact ? 16 : 40)

            if authManager.googleOAuthEnabled {
                HStack {
                    Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 1)
                    Text("or").font(.caption).foregroundStyle(.secondary)
                    Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 1)
                }
                .frame(maxWidth: 420)
                .padding(.horizontal, compact ? 16 : 40)

                Button(action: { authManager.signInWithOAuth(provider: "google") }) {
                    HStack {
                        Image(systemName: "g.circle.fill")
                        Text("Continue with Google").fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(Color.gray.opacity(0.08))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: 420)
                .padding(.horizontal, compact ? 16 : 40)
            }

            if !compact { Spacer() }
        }
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func handleSubmit() {
        Task {
            do {
                if isSignUp {
                    try await authManager.signUpWithEmail(email: email, password: password)
                    if let message = authManager.errorMessage, message.starts(with: "This email already") {
                        await MainActor.run { isSignUp = false }
                    }
                } else {
                    try await authManager.signInWithEmail(email: email, password: password)
                }
            } catch {
                // errorMessage is set on the manager
            }
        }
    }
}

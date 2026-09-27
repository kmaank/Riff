import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: SwiftAuthManager
    var compact: Bool = true
    var companionCopy: Bool = false
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isSignUp: Bool = false

    var body: some View {
        VStack(spacing: compact ? 16 : 0) {
            if !companionCopy {
                VStack(spacing: compact ? 8 : 16) {
                    if let icon = RiffLogo.appIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: compact ? 40 : 64, height: compact ? 40 : 64)
                    }
                    Text(isSignUp ? "Create your account" : "Sign in")
                        .font(RiffType.h1)
                        .foregroundColor(RiffTheme.ink)
                    Text(accountCaption)
                        .font(RiffType.bodySM)
                        .foregroundColor(RiffTheme.inkMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, compact ? 8 : 40)
                .padding(.bottom, compact ? 8 : 24)
            }

            VStack(alignment: .leading, spacing: 12) {
                field(title: "Email", content: {
                    TextField("your@email.com", text: $email)
                        .textFieldStyle(.plain)
                        .onSubmit { handleSubmit() }
                })
                field(title: "Password", content: {
                    SecureField("Enter your password", text: $password)
                        .onSubmit { handleSubmit() }
                })

                if let message = authManager.errorMessage {
                    let isInfo = message.starts(with: "Check your email")
                        || message.starts(with: "This email already")
                        || message.starts(with: "If an account exists")
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: isInfo ? "envelope" : "exclamationmark.triangle")
                            .foregroundColor(isInfo ? RiffTheme.gain : RiffTheme.loss)
                        Text(message)
                            .font(RiffType.caption)
                            .foregroundColor(isInfo ? RiffTheme.ink : RiffTheme.loss)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(isInfo ? RiffTheme.gainWash : RiffTheme.lossWash)
                    .cornerRadius(RiffTheme.radiusSM)
                }

                RiffButton(
                    title: isSignUp ? "Sign Up" : "Sign In",
                    kind: .primary,
                    enabled: !email.isEmpty && !password.isEmpty && !authManager.isLoading,
                    fullWidth: true,
                    action: handleSubmit
                )
                if email.isEmpty || password.isEmpty {
                    DisabledReason(text: "Enter email and password to continue.")
                }

                if !isSignUp {
                    Button("Forgot password?") {
                        Task { await authManager.sendPasswordReset(email: email) }
                    }
                    .buttonStyle(.plain)
                    .font(RiffType.bodySM)
                    .foregroundColor(RiffTheme.link)
                    .disabled(email.isEmpty || authManager.isLoading)
                }

                Button(action: {
                    isSignUp.toggle()
                    authManager.errorMessage = nil
                }) {
                    Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                        .font(RiffType.bodySM)
                        .foregroundColor(RiffTheme.link)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, compact ? 16 : 40)

            if authManager.googleOAuthEnabled {
                HStack {
                    Rectangle().fill(RiffTheme.line).frame(height: 1)
                    Text("or").font(RiffType.caption).foregroundColor(RiffTheme.inkFaint)
                    Rectangle().fill(RiffTheme.line).frame(height: 1)
                }
                .frame(maxWidth: 420)
                .padding(.horizontal, compact ? 16 : 40)

                RiffButton(
                    title: "Continue with Google",
                    icon: "g.circle",
                    kind: .secondary,
                    action: { authManager.signInWithOAuth(provider: "google") }
                )
                .frame(maxWidth: 420)
                .padding(.horizontal, compact ? 16 : 40)
            }

            if !compact { Spacer() }
        }
        .frame(maxWidth: .infinity)
        .background(RiffTheme.surface000)
    }

    private func field<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(RiffType.label)
                .tracking(1.1)
                .foregroundColor(RiffTheme.inkFaint)
            content()
                .font(RiffType.body)
                .foregroundColor(RiffTheme.ink)
                .padding(10)
                .frame(height: 40)
                .background(RiffTheme.surface200)
                .overlay(RoundedRectangle(cornerRadius: RiffTheme.radiusXS).stroke(RiffTheme.lineStrong, lineWidth: 1))
                .cornerRadius(RiffTheme.radiusXS)
        }
    }

    private var accountCaption: String {
        if companionCopy {
            return isSignUp
                ? "Create a home for your key so a new Mac or Android can pick it up."
                : "Welcome back. If we've met before, I'll fetch your key next. You won't paste it again."
        }
        return isSignUp
            ? "Next you'll paste your Groq key once. It follows this account."
            : "Your Groq key comes back from this account after sign-in."
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

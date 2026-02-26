import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var authManager: SwiftAuthManager
    @State private var selectedTab = "script-style"

    var body: some View {
        // Phase 3: Auth gate - require login first
        if !authManager.isAuthenticated {
            LoginView()
        } else if (settings.config.onboarding_completed ?? false) == false || settings.config.api.api_key.isEmpty {
            OnboardingView()
        } else {
            HStack(spacing: 0) {
                // Sidebar
                VStack(alignment: .leading, spacing: 10) {
                    if let imagePath = Bundle.main.path(forResource: "settings_logo", ofType: "png"),
                       let nsImage = NSImage(contentsOfFile: imagePath) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 60) // Adjust size as needed
                            .padding(.bottom, 20)
                    } else {
                        Text("Riff")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.orange, .yellow],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .padding(.bottom, 20)
                    }

                    SidebarButton(icon: "sparkles", title: "Script & Style", id: "script-style", selection: $selectedTab)
                    SidebarButton(icon: "keyboard", title: "Keys", id: "keys", selection: $selectedTab)
                    SidebarButton(icon: "clock.arrow.circlepath", title: "History", id: "history", selection: $selectedTab)
                    SidebarButton(icon: "person.circle", title: "Account", id: "account", selection: $selectedTab)
                    SidebarButton(icon: "book.fill", title: "How to", id: "help", selection: $selectedTab)

                    Spacer()
                }
                .padding()
                .frame(width: 180)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))

                // Main Content
                VStack {
                    switch selectedTab {
                    case "script-style": ScriptAndStyleView()
                    case "keys": KeysView()
                    case "history": HistoryView()
                    case "account": AccountView()
                    case "help": HelpView()
                    default: ScriptAndStyleView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
    }
}

struct SidebarButton: View {
    let icon: String
    let title: String
    let id: String
    @Binding var selection: String

    var body: some View {
        Button(action: { selection = id }) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 20)
                Text(title)
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(selection == id ? Color.accentColor.opacity(0.1) : Color.clear)
            .foregroundStyle(selection == id ? Color.accentColor : Color.primary)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

import SwiftUI

@main
struct RiffControlCenterApp: App {
    @StateObject var settings = SettingsManager()
    @StateObject var authManager = SwiftAuthManager()

    @Environment(\.scenePhase) var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(authManager)
                .frame(minWidth: 600, minHeight: 400)
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active {
                        settings.loadConfig()
                    }
                }
                // Handle OAuth callback (riff://oauth/callback) and email confirmation (riff://auth/callback)
                .onOpenURL { url in
                    if url.scheme == "riff" && (url.host == "oauth" || url.host == "auth") {
                        authManager.handleAuthCallback(url: url)
                    }
                }
        }
    }
}

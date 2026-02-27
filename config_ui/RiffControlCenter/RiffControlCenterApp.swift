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
                // Phase 3: Handle OAuth callback
                .onOpenURL { url in
                    if url.scheme == "riff" && url.host == "oauth" {
                        authManager.handleOAuthCallback(url: url)
                    }
                }
        }
    }
}

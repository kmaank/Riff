import SwiftUI

@main
struct RiffControlCenterApp: App {
    @StateObject var settings = SettingsManager()
    
    @Environment(\.scenePhase) var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .frame(minWidth: 600, minHeight: 400)
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active {
                        settings.loadConfig()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
    }
}

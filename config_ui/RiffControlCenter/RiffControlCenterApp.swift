import SwiftUI

@main
struct RiffControlCenterApp: App {
    @StateObject var settings = SettingsManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .frame(minWidth: 600, minHeight: 400)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

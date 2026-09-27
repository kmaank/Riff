import SwiftUI
import AppKit

@main
struct RiffControlCenterApp: App {
    @NSApplicationDelegateAdaptor(RiffAppDelegate.self) var appDelegate
    @StateObject var settings = SettingsManager()
    @StateObject var authManager = SwiftAuthManager()
    @StateObject var runtime = RiffRuntimeStatus()

    @Environment(\.scenePhase) var scenePhase

    init() {
        RiffFonts.register()
        WindowConfigurator.shared.install()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(authManager)
                .environmentObject(runtime)
                .frame(
                    minWidth: WindowMetrics.minWidth,
                    idealWidth: WindowMetrics.preferredWidth,
                    minHeight: WindowMetrics.minHeight,
                    idealHeight: WindowMetrics.preferredHeight
                )
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active {
                        settings.refreshMetricsFromDisk()
                        settings.loadHistory()
                        settings.loadStats()
                    }
                }
                .onAppear {
                    RiffTheme.applyAppearance(settings.config.ui?.theme ?? "system")
                    fitRiffWindows()
                }
                .onOpenURL { url in
                    if url.scheme == "riff" && (url.host == "oauth" || url.host == "auth") {
                        authManager.handleAuthCallback(url: url)
                    }
                }
        }
    }

    private func fitRiffWindows() {
        let apply = {
            for window in NSApp.windows {
                window.title = "Riff"
                WindowConfigurator.shared.apply(to: window, force: true)
            }
        }
        DispatchQueue.main.async(execute: apply)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: apply)
    }
}

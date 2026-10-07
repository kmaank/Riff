import Foundation
import AppKit

/// Survives macOS “Quit and Reopen”. The tray and this window both die;
/// we write where the user was, then open this window again after Riff is back.
enum SettingsSession {
    struct Snapshot {
        var resume: Bool
        var route: String
        var section: String
        var tab: String
        var onboardingStep: Int
        var permissionIndex: Int
        var restoredFromAccount: Bool
        var updatedAt: Double
    }

    private static var heartbeat: Timer?
    private static var isTerminating = false
    private static var snapshot = Snapshot(
        resume: false,
        route: "main",
        section: "home",
        tab: "dictation",
        onboardingStep: 1,
        permissionIndex: 0,
        restoredFromAccount: false,
        updatedAt: 0
    )

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Riff")
    }

    static var sessionURL: URL {
        directory.appendingPathComponent("settings_session.json")
    }

    static var reopenURL: URL {
        directory.appendingPathComponent("reopen_settings")
    }

    static func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: sessionURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let loaded = Snapshot(
            resume: (obj["resume"] as? Bool) ?? false,
            route: (obj["route"] as? String) ?? "main",
            section: (obj["section"] as? String) ?? "home",
            tab: (obj["tab"] as? String) ?? "dictation",
            onboardingStep: (obj["onboarding_step"] as? Int) ?? 1,
            permissionIndex: (obj["permission_index"] as? Int) ?? 0,
            restoredFromAccount: (obj["restored_from_account"] as? Bool) ?? false,
            updatedAt: (obj["updated_at"] as? Double) ?? 0
        )
        snapshot = loaded
        return loaded
    }

    static func update(
        resume: Bool? = nil,
        route: String? = nil,
        section: String? = nil,
        tab: String? = nil,
        onboardingStep: Int? = nil,
        permissionIndex: Int? = nil,
        restoredFromAccount: Bool? = nil
    ) {
        if let resume { snapshot.resume = resume }
        if let route { snapshot.route = route }
        if let section { snapshot.section = section }
        if let tab { snapshot.tab = tab }
        if let onboardingStep { snapshot.onboardingStep = onboardingStep }
        if let permissionIndex { snapshot.permissionIndex = permissionIndex }
        if let restoredFromAccount { snapshot.restoredFromAccount = restoredFromAccount }
        persist(open: true)
        startHeartbeat()
    }

    static func notePermissionGrant() {
        snapshot.resume = true
        persist(open: true)
        writeReopenFlag()
    }

    static func markClosed() {
        heartbeat?.invalidate()
        heartbeat = nil
        snapshot.resume = false
        persist(open: false)
        try? FileManager.default.removeItem(at: reopenURL)
    }

    static func clear() {
        heartbeat?.invalidate()
        heartbeat = nil
        snapshot.resume = false
        snapshot.route = "main"
        snapshot.section = "home"
        snapshot.tab = "dictation"
        snapshot.onboardingStep = 1
        snapshot.permissionIndex = 0
        try? FileManager.default.removeItem(at: sessionURL)
        try? FileManager.default.removeItem(at: reopenURL)
    }

    static func beginTerminate() {
        isTerminating = true
    }

    static func handleWillTerminate() {
        isTerminating = true
        if snapshot.resume {
            persist(open: false, interrupted: true)
            writeReopenFlag()
            scheduleDelayedReopen()
        } else {
            markClosed()
        }
    }

    static func handleLastWindowClosed() -> Bool {
        if isTerminating {
            return true
        }
        markClosed()
        return true
    }

    private static func persist(open: Bool, interrupted: Bool = false) {
        snapshot.updatedAt = Date().timeIntervalSince1970
        var payload: [String: Any] = [
            "open": open,
            "resume": snapshot.resume,
            "route": snapshot.route,
            "section": snapshot.section,
            "tab": snapshot.tab,
            "onboarding_step": snapshot.onboardingStep,
            "permission_index": snapshot.permissionIndex,
            "restored_from_account": snapshot.restoredFromAccount,
            "updated_at": snapshot.updatedAt
        ]
        if interrupted {
            payload["interrupted"] = true
            payload["interrupted_at"] = snapshot.updatedAt
        }
        write(payload, to: sessionURL)
    }

    private static func writeReopenFlag() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? "1".data(using: .utf8)?.write(to: reopenURL, options: .atomic)
    }

    private static func write(_ payload: [String: Any], to url: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func startHeartbeat() {
        guard heartbeat == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            persist(open: true)
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeat = timer
    }

    /// Works even if the packaged tray is old: after both processes die, a
    /// detached shell waits for Riff to come back and opens this window.
    private static func scheduleDelayedReopen() {
        let ccPath = Bundle.main.bundlePath.replacingOccurrences(of: "\"", with: "\\\"")
        let flagPath = reopenURL.path.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        (
          for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
            sleep 1
            if /usr/bin/pgrep -x RiffControlCenter >/dev/null 2>&1; then exit 0; fi
            if /usr/bin/pgrep -x Riff >/dev/null 2>&1 && [ -f "\(flagPath)" ]; then
              /usr/bin/open "\(ccPath)"
              exit 0
            fi
          done
        ) >/dev/null 2>&1 &
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}

final class RiffAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Always take focus so first launch is never an invisible background window.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            for window in NSApp.windows {
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            for window in NSApp.windows {
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
        let saved = SettingsSession.load()
        SettingsSession.update(resume: saved?.resume ?? false)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        SettingsSession.beginTerminate()
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        SettingsSession.handleLastWindowClosed()
    }

    func applicationWillTerminate(_ notification: Notification) {
        SettingsSession.handleWillTerminate()
    }
}

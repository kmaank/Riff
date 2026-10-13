import Foundation
import AppKit
import Combine

final class RiffRuntimeStatus: ObservableObject {
    @Published var permissions = RiffPermissionStatus()
    @Published var hud = HudStatus()
    @Published var provider = GroqProviderStatus(state: "unknown", label: "Unknown", waiting: 0, retry_after: nil)
    @Published var reporterStale = true
    @Published var applyingPermissions = false
    @Published var startingMenuBar = false
    @Published var updateAvailable = false
    @Published var updateLatest = ""
    @Published var updateState = "idle"
    @Published var updateMessage = ""

    private var timer: Timer?
    private var lastLaunchAttempt = Date.distantPast

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    deinit {
        timer?.invalidate()
    }

    var microphoneGranted: Bool {
        permissions.microphoneEffective
    }

    var missingPermissionCount: Int {
        [microphoneGranted, permissions.accessibility, permissions.input_monitoring]
            .filter { !$0 }.count
    }

    var missingPermissionNames: [String] {
        var names: [String] = []
        if !microphoneGranted { names.append("Microphone") }
        if !permissions.accessibility { names.append("Accessibility") }
        if !permissions.input_monitoring { names.append("Input Monitoring") }
        return names
    }

    var canDictate: Bool {
        !reporterStale && missingPermissionCount == 0
    }

    var permissionBannerVisible: Bool {
        applyingPermissions || reporterStale || missingPermissionCount > 0
    }

    func refresh() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Riff")
        var next = permissions
        var haveFile = false
        if let data = try? Data(contentsOf: dir.appendingPathComponent("permissions_status.json")),
           let decoded = try? JSONDecoder().decode(RiffPermissionStatus.self, from: data) {
            next = decoded
            haveFile = true
        }
        if let data = try? Data(contentsOf: dir.appendingPathComponent("mic_verified.json")),
           let proof = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           (proof["verified"] as? Bool) == true {
            next.mic_verified = true
            next.microphone = true
        }
        let relaunching = Self.isRelaunching(dir)
        let stale: Bool
        if relaunching {
            stale = false
        } else if let ts = next.updated_at {
            stale = Date().timeIntervalSince1970 - ts > 45
        } else {
            stale = !haveFile
        }
        if next != permissions || stale != reporterStale || relaunching != applyingPermissions {
            DispatchQueue.main.async {
                self.permissions = next
                self.reporterStale = stale
                self.applyingPermissions = relaunching
                if !stale {
                    self.startingMenuBar = false
                }
            }
        }
        if stale && !relaunching {
            ensureMenuBarApp()
        }
        if let data = try? Data(contentsOf: dir.appendingPathComponent("hud_status.json")),
           let decoded = try? JSONDecoder().decode(HudStatus.self, from: data),
           decoded.state != hud.state {
            DispatchQueue.main.async { self.hud = decoded }
        }
        if let data = try? Data(contentsOf: dir.appendingPathComponent("update_status.json")),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let available = (obj["available"] as? Bool) == true
            let latest = obj["latest"] as? String ?? ""
            let state = obj["state"] as? String ?? "idle"
            let message = obj["message"] as? String ?? ""
            if available != updateAvailable || latest != updateLatest || state != updateState || message != updateMessage {
                DispatchQueue.main.async {
                    self.updateAvailable = available
                    self.updateLatest = latest
                    self.updateState = state
                    self.updateMessage = message
                }
            }
        }
        if let data = try? Data(contentsOf: dir.appendingPathComponent("provider_status.json")),
           let decoded = try? JSONDecoder().decode(GroqProviderStatus.self, from: data) {
            if decoded.state != provider.state || decoded.waiting != provider.waiting || decoded.label != provider.label {
                DispatchQueue.main.async { self.provider = decoded }
            }
        }
    }

    func requestUpdate() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Riff")
        let url = dir.appendingPathComponent("update_install.request")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? Data("1".utf8).write(to: url)
        DispatchQueue.main.async {
            self.updateState = "downloading"
            self.updateMessage = "Downloading the latest Riff…"
        }
    }

    /// Home cannot see the microphone or hotkey unless the menu-bar process is alive.
    /// If its heartbeat is stale, start that process instead of leaving a dead banner.
    func ensureMenuBarApp() {
        let now = Date()
        guard now.timeIntervalSince(lastLaunchAttempt) > 8 else { return }
        lastLaunchAttempt = now
        let url = Self.menuBarAppURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        DispatchQueue.main.async { self.startingMenuBar = true }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if error != nil {
                DispatchQueue.main.async { self.startingMenuBar = false }
            }
        }
    }

    private static func menuBarAppURL() -> URL {
        let bundle = Bundle.main.bundleURL
        let parent = bundle
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        if parent.lastPathComponent == "Riff.app" {
            return parent
        }
        return URL(fileURLWithPath: "/Applications/Riff.app")
    }

    private static func isRelaunching(_ dir: URL) -> Bool {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("tray_relaunch.json")),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ts = obj["at"] as? Double else {
            return false
        }
        return Date().timeIntervalSince1970 - ts < 20
    }
}

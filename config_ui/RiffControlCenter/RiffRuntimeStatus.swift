import Foundation
import Combine

final class RiffRuntimeStatus: ObservableObject {
    @Published var permissions = RiffPermissionStatus()
    @Published var hud = HudStatus()
    @Published var provider = GroqProviderStatus(state: "unknown", label: "Unknown", waiting: 0, retry_after: nil)
    @Published var reporterStale = true
    @Published var applyingPermissions = false

    private var timer: Timer?

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
            }
        }
        if let data = try? Data(contentsOf: dir.appendingPathComponent("hud_status.json")),
           let decoded = try? JSONDecoder().decode(HudStatus.self, from: data),
           decoded.state != hud.state {
            DispatchQueue.main.async { self.hud = decoded }
        }
        if let data = try? Data(contentsOf: dir.appendingPathComponent("provider_status.json")),
           let decoded = try? JSONDecoder().decode(GroqProviderStatus.self, from: data) {
            if decoded.state != provider.state || decoded.waiting != provider.waiting || decoded.label != provider.label {
                DispatchQueue.main.async { self.provider = decoded }
            }
        }
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

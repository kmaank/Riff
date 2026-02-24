import Foundation
import Combine

struct Config: Codable {
    var audio: AudioConfig
    var api: ApiConfig
    var hotkey: HotkeyConfig
    var style: StyleConfig
    var script_mode: ScriptModeConfig
    var onboarding_completed: Bool? = false
    var metrics: MetricsConfig? = nil
}

struct AudioConfig: Codable {
    var sample_rate: Int
    var silence_threshold_ms: Int
}

struct ApiConfig: Codable {
    var api_key: String
    var llm_model: String
}

struct HotkeyConfig: Codable {
    var combination: String
}

struct StyleConfig: Codable {
    var active_style: String
}

struct ScriptModeConfig: Codable {
    var active_mode: String
}

struct MetricsConfig: Codable {
    var total_words: Int
    var total_riffs: Int
    var total_recording_seconds: Double
    var this_week_riffs: Int
    var week_start_date: String
    var style_counts: [String: Int]
}

struct HistoryEntry: Codable, Identifiable {
    var id: String { timestamp }
    let timestamp: String
    let original: String
    let refined: String
    let style: String
}

class SettingsManager: ObservableObject {
    @Published var config: Config
    @Published var history: [HistoryEntry] = []
    
    private let configPath: URL
    private let historyPath: URL
    
    init() {
        // Default Config
        self.config = Config(
            audio: AudioConfig(sample_rate: 16000, silence_threshold_ms: 600),
            api: ApiConfig(api_key: "", llm_model: "llama-3.3-70b-versatile"),
            hotkey: HotkeyConfig(combination: "f8"),
            style: StyleConfig(active_style: "casual"),
            script_mode: ScriptModeConfig(active_mode: "english_mixed"),
            onboarding_completed: false
        )
        
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let riffDir = appSupport.appendingPathComponent("Riff")
        
        self.configPath = riffDir.appendingPathComponent("config.json")
        self.historyPath = riffDir.appendingPathComponent("history.json")
        
        loadConfig()
        loadHistory()
        
        // Start watching for history changes? 
        // For simple MVP we just reload on appear or timer
        startHistoryTimer()
    }
    
    func loadConfig() {
        guard let data = try? Data(contentsOf: configPath) else { return }
        do {
            let decoded = try JSONDecoder().decode(Config.self, from: data)
            DispatchQueue.main.async { self.config = decoded }
        } catch {
            print("Config decode error: \(error)")
        }
    }
    
    func saveConfig() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(config)
            try data.write(to: configPath)
        } catch {
            print("Config save error: \(error)")
        }
    }
    
    func loadHistory() {
        guard let data = try? Data(contentsOf: historyPath) else { return }
        do {
            let decoded = try JSONDecoder().decode([HistoryEntry].self, from: data)
            DispatchQueue.main.async { self.history = decoded }
        } catch {
            print("History decode error: \(error)")
        }
    }
    
    func startHistoryTimer() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            self.loadHistory()
            self.loadConfig()  // Also reload config to get updated metrics
        }
    }
}

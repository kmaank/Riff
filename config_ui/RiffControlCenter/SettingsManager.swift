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
    var ui: UIConfig? = nil

    init(audio: AudioConfig, api: ApiConfig, hotkey: HotkeyConfig, style: StyleConfig, script_mode: ScriptModeConfig, onboarding_completed: Bool? = false, metrics: MetricsConfig? = nil, ui: UIConfig? = nil) {
        self.audio = audio
        self.api = api
        self.hotkey = hotkey
        self.style = style
        self.script_mode = script_mode
        self.onboarding_completed = onboarding_completed
        self.metrics = metrics
        self.ui = ui
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        audio = try c.decodeIfPresent(AudioConfig.self, forKey: .audio) ?? AudioConfig(sample_rate: 16000, silence_threshold_ms: 600)
        api = try c.decodeIfPresent(ApiConfig.self, forKey: .api) ?? ApiConfig(api_key: "", llm_model: "openai/gpt-oss-120b")
        hotkey = try c.decodeIfPresent(HotkeyConfig.self, forKey: .hotkey) ?? HotkeyConfig(combination: "ctrl_l")
        style = try c.decodeIfPresent(StyleConfig.self, forKey: .style) ?? StyleConfig(active_style: "casual")
        script_mode = try c.decodeIfPresent(ScriptModeConfig.self, forKey: .script_mode) ?? ScriptModeConfig(active_mode: "english_mixed")
        onboarding_completed = try c.decodeIfPresent(Bool.self, forKey: .onboarding_completed) ?? false
        metrics = try c.decodeIfPresent(MetricsConfig.self, forKey: .metrics)
        ui = try c.decodeIfPresent(UIConfig.self, forKey: .ui)
    }
}

struct UIConfig: Codable {
    var theme: String?
    var show_notifications: Bool?
}

struct AudioConfig: Codable {
    var sample_rate: Int
    var silence_threshold_ms: Int

    init(sample_rate: Int, silence_threshold_ms: Int) {
        self.sample_rate = sample_rate
        self.silence_threshold_ms = silence_threshold_ms
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sample_rate = try c.decodeIfPresent(Int.self, forKey: .sample_rate) ?? 16000
        silence_threshold_ms = try c.decodeIfPresent(Int.self, forKey: .silence_threshold_ms) ?? 600
    }
}

struct ApiConfig: Codable {
    var api_key: String
    var llm_model: String

    init(api_key: String, llm_model: String) {
        self.api_key = api_key
        self.llm_model = llm_model
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        api_key = try c.decodeIfPresent(String.self, forKey: .api_key) ?? ""
        llm_model = try c.decodeIfPresent(String.self, forKey: .llm_model) ?? "openai/gpt-oss-120b"
    }
}

struct HotkeyConfig: Codable {
    var combination: String

    init(combination: String) {
        self.combination = combination
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try c.decodeIfPresent(String.self, forKey: .combination) {
            combination = s
        } else if let arr = try c.decodeIfPresent([String].self, forKey: .combination), let first = arr.first {
            combination = first
        } else {
            combination = "ctrl_l"
        }
    }
}

struct StyleConfig: Codable {
    var active_style: String

    init(active_style: String) {
        self.active_style = active_style
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        active_style = try c.decodeIfPresent(String.self, forKey: .active_style) ?? "casual"
    }
}

struct ScriptModeConfig: Codable {
    var active_mode: String

    init(active_mode: String) {
        self.active_mode = active_mode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        active_mode = try c.decodeIfPresent(String.self, forKey: .active_mode) ?? "english_mixed"
    }
}

struct MetricsConfig: Codable {
    var total_words: Int
    var total_riffs: Int
    var total_recording_seconds: Double
    var this_week_riffs: Int
    var week_start_date: String
    var style_counts: [String: Int]
    var typing_wpm: Int?

    init(total_words: Int = 0, total_riffs: Int = 0, total_recording_seconds: Double = 0, this_week_riffs: Int = 0, week_start_date: String = "", style_counts: [String: Int] = [:], typing_wpm: Int? = 40) {
        self.total_words = total_words
        self.total_riffs = total_riffs
        self.total_recording_seconds = total_recording_seconds
        self.this_week_riffs = this_week_riffs
        self.week_start_date = week_start_date
        self.style_counts = style_counts
        self.typing_wpm = typing_wpm
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total_words = try c.decodeIfPresent(Int.self, forKey: .total_words) ?? 0
        total_riffs = try c.decodeIfPresent(Int.self, forKey: .total_riffs) ?? 0
        total_recording_seconds = try c.decodeIfPresent(Double.self, forKey: .total_recording_seconds) ?? 0
        this_week_riffs = try c.decodeIfPresent(Int.self, forKey: .this_week_riffs) ?? 0
        week_start_date = try c.decodeIfPresent(String.self, forKey: .week_start_date) ?? ""
        style_counts = try c.decodeIfPresent([String: Int].self, forKey: .style_counts) ?? [:]
        typing_wpm = try c.decodeIfPresent(Int.self, forKey: .typing_wpm)
    }
}

struct HistoryEntry: Codable, Identifiable {
    var id: String { timestamp }
    let timestamp: String
    let original: String
    let refined: String
    let style: String
    var transcribe_ms: Int?
    var rewrite_ms: Int?
    var type_ms: Int?
    var round_trip_ms: Int?
    var likely_noise: Bool?
}

struct StatsDay: Codable {
    var date: String
    var minutes: Double
    var riffs: Int
}

struct StreakCell: Codable {
    var date: String
    var level: Int
    var minutes: Double
    var riffs: Int
}

struct StatsSnapshot: Codable {
    var typing_wpm: Int
    var minutes: Double
    var minutes_prior: Double
    var words_30: Int
    var spoken_minutes_30: Double
    var series: [StatsDay]
    var streak_days: Int
    var streak_cells: [StreakCell]
    var formula: String
}

struct GroqProviderStatus: Codable {
    var state: String
    var label: String
    var waiting: Int
    var retry_after: Int?
}

class SettingsManager: ObservableObject {
    @Published var config: Config
    @Published var history: [HistoryEntry] = []
    @Published var stats: StatsSnapshot?
    
    private let configPath: URL
    private let historyPath: URL
    private let statsPath: URL
    private let deletedPath: URL
    
    init() {
        // Default Config
        self.config = Config(
            audio: AudioConfig(sample_rate: 16000, silence_threshold_ms: 600),
            api: ApiConfig(api_key: "", llm_model: "openai/gpt-oss-120b"),
            hotkey: HotkeyConfig(combination: "ctrl_l"),
            style: StyleConfig(active_style: "casual"),
            script_mode: ScriptModeConfig(active_mode: "english_mixed"),
            onboarding_completed: false
        )
        
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let riffDir = appSupport.appendingPathComponent("Riff")
        
        self.configPath = riffDir.appendingPathComponent("config.json")
        self.historyPath = riffDir.appendingPathComponent("history.json")
        self.statsPath = riffDir.appendingPathComponent("stats_snapshot.json")
        self.deletedPath = riffDir.appendingPathComponent("history_deleted.json")
        
        loadConfig()
        loadHistory()
        loadStats()
        
        // Start watching for history changes? 
        // For simple MVP we just reload on appear or timer
        startHistoryTimer()
    }
    
    func loadConfig() {
        guard let data = try? Data(contentsOf: configPath) else { return }
        do {
            let decoded = try JSONDecoder().decode(Config.self, from: data)
            if Thread.isMainThread {
                self.config = decoded
            } else {
                DispatchQueue.main.async { self.config = decoded }
            }
        } catch {
            AuthLogger.log("[Settings] Config decode error: \(error)")
            print("Config decode error: \(error)")
        }
    }
    
    func saveConfig() {
        do {
            var existing: [String: Any] = [:]
            if let data = try? Data(contentsOf: configPath),
               let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                existing = obj
            }
            let diskMetrics = existing["metrics"] as? [String: Any]
            var uiPatch: [String: Any] = [:]
            if let theme = config.ui?.theme {
                uiPatch["theme"] = theme
            }
            var patch: [String: Any] = [
                "style": ["active_style": config.style.active_style],
                "script_mode": ["active_mode": config.script_mode.active_mode],
                "hotkey": ["combination": config.hotkey.combination],
                "api": ["api_key": config.api.api_key, "llm_model": config.api.llm_model],
                "onboarding_completed": config.onboarding_completed ?? false
            ]
            if !uiPatch.isEmpty {
                patch["ui"] = uiPatch
            }
            existing = Self.deepMerge(existing, patch)
            var metrics = diskMetrics ?? [:]
            if let wpm = config.metrics?.typing_wpm {
                metrics["typing_wpm"] = wpm
            }
            existing["metrics"] = metrics
            let out = try JSONSerialization.data(withJSONObject: existing, options: [.prettyPrinted, .sortedKeys])
            try out.write(to: configPath, options: .atomic)
            AuthLogger.log("[Settings] Saved style=\(config.style.active_style) script=\(config.script_mode.active_mode)")
        } catch {
            AuthLogger.log("[Settings] Config save error: \(error)")
            print("Config save error: \(error)")
        }
    }

    private static func deepMerge(_ base: [String: Any], _ overlay: [String: Any]) -> [String: Any] {
        var out = base
        for (key, value) in overlay {
            if value is NSNull { continue }
            if let child = value as? [String: Any], let existing = out[key] as? [String: Any] {
                out[key] = deepMerge(existing, child)
            } else {
                out[key] = value
            }
        }
        return out
    }
    
    func loadHistory() {
        guard let data = try? Data(contentsOf: historyPath) else { return }
        do {
            let decoded = try JSONDecoder().decode([HistoryEntry].self, from: data)
            let apply = { self.history = decoded }
            if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
        } catch {
            print("History decode error: \(error)")
        }
    }
    
    func startHistoryTimer() {
        let timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            self.loadHistory()
            self.refreshMetricsFromDisk()
            self.loadStats()
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    func loadStats() {
        if let data = try? Data(contentsOf: statsPath),
           var decoded = try? JSONDecoder().decode(StatsSnapshot.self, from: data) {
            if let wpm = config.metrics?.typing_wpm, wpm > 0 {
                decoded.typing_wpm = wpm
            }
            let apply = { self.stats = decoded }
            if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
            return
        }
        let fallback = Self.statsFromHistory(history, metrics: config.metrics)
        let apply = { self.stats = fallback }
        if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
    }

    static func statsFromHistory(_ history: [HistoryEntry], metrics: MetricsConfig?) -> StatsSnapshot {
        let wpm = max(metrics?.typing_wpm ?? 40, 1)
        var dailyWords: [String: Int] = [:]
        var dailyRiffs: [String: Int] = [:]
        for entry in history {
            let day = String(entry.timestamp.prefix(10))
            guard day.count == 10 else { continue }
            let words = entry.refined.split { $0.isWhitespace || $0.isNewline }.count
            dailyWords[day, default: 0] += words
            dailyRiffs[day, default: 0] += 1
        }
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        func dayString(_ offset: Int) -> String {
            let date = cal.date(byAdding: .day, value: -offset, to: today) ?? today
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: date)
        }
        func window(days: Int, offset: Int) -> (minutes: Double, words: Int, series: [StatsDay]) {
            var words = 0
            var series: [StatsDay] = []
            for i in stride(from: days - 1, through: 0, by: -1) {
                let key = dayString(offset + i)
                let dayWords = dailyWords[key] ?? 0
                let saved = Double(dayWords) / Double(wpm)
                words += dayWords
                series.append(StatsDay(date: key, minutes: (saved * 100).rounded() / 100, riffs: dailyRiffs[key] ?? 0))
            }
            return (Double(words) / Double(wpm), words, series)
        }
        let current = window(days: 30, offset: 0)
        let prior = window(days: 30, offset: 30)
        let spoken = Double(current.words) / 150.0
        let minutes = max(0, current.minutes - spoken)
        var cells: [StreakCell] = []
        for i in stride(from: 83, through: 0, by: -1) {
            let key = dayString(i)
            let dayWords = dailyWords[key] ?? 0
            let riffs = dailyRiffs[key] ?? 0
            let mins = Double(dayWords) / Double(wpm)
            let level: Int
            if riffs == 0 { level = 0 }
            else if mins >= 20 { level = 4 }
            else if mins >= 8 { level = 3 }
            else if mins >= 3 { level = 2 }
            else { level = 1 }
            cells.append(StreakCell(date: key, level: level, minutes: mins, riffs: riffs))
        }
        var streak = 0
        for i in 0..<84 {
            let key = dayString(i)
            let riffs = dailyRiffs[key] ?? 0
            if i == 0 && riffs == 0 { continue }
            if riffs > 0 { streak += 1 } else { break }
        }
        return StatsSnapshot(
            typing_wpm: wpm,
            minutes: (minutes * 100).rounded() / 100,
            minutes_prior: (prior.minutes * 100).rounded() / 100,
            words_30: current.words,
            spoken_minutes_30: (spoken * 100).rounded() / 100,
            series: current.series,
            streak_days: streak,
            streak_cells: cells,
            formula: "words ÷ \(wpm) WPM − time spent speaking"
        )
    }

    func deleteHistory(timestamp: String) {
        do {
            var rows: [[String: Any]] = []
            if let data = try? Data(contentsOf: historyPath),
               let parsed = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                rows = parsed
            }
            rows.removeAll { ($0["timestamp"] as? String) == timestamp }
            let out = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
            try out.write(to: historyPath, options: .atomic)
            rememberDeleted(timestamp)
            history.removeAll { $0.timestamp == timestamp }
        } catch {
            AuthLogger.log("[Settings] History delete failed: \(error)")
            loadHistory()
        }
    }

    private func rememberDeleted(_ timestamp: String) {
        var deleted: [String] = []
        if let data = try? Data(contentsOf: deletedPath),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String] {
            deleted = parsed
        }
        if !deleted.contains(timestamp) {
            deleted.append(timestamp)
        }
        if deleted.count > 500 {
            deleted = Array(deleted.suffix(500))
        }
        if let out = try? JSONSerialization.data(withJSONObject: deleted, options: [.prettyPrinted]) {
            try? out.write(to: deletedPath, options: .atomic)
        }
    }

    func refreshMetricsFromDisk() {
        guard let data = try? Data(contentsOf: configPath) else { return }
        do {
            let decoded = try JSONDecoder().decode(Config.self, from: data)
            let apply = { self.config.metrics = decoded.metrics }
            if Thread.isMainThread {
                apply()
            } else {
                DispatchQueue.main.async(execute: apply)
            }
        } catch {
            AuthLogger.log("[Settings] Metrics refresh decode error: \(error)")
        }
    }
}

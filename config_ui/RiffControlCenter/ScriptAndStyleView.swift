import SwiftUI

struct ScriptAndStyleView: View {
    @EnvironmentObject var settings: SettingsManager

    let modes = [
        ("english_mixed", "English Mixed", "Recommended"),
        ("english_translated", "English Translated", ""),
        ("original_mixed", "Original Mixed", "")
    ]

    let styles = ["clean", "formal", "casual", "riff"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                // Metrics Section
                if let metrics = settings.config.metrics {
                    MetricsView(metrics: metrics)
                }

                // Script Mode Section
                VStack(alignment: .leading, spacing: 20) {
                    Text("Script Mode")
                        .font(.title2)
                        .bold()

                    Text("Choose how Riff handles multilingual dictation and code-switching (like Hinglish, Spanglish, Benglish).")
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                        ForEach(modes, id: \.0) { mode in
                            ScriptModeCard(
                                mode: mode.0,
                                title: mode.1,
                                badge: mode.2,
                                isSelected: settings.config.script_mode.active_mode == mode.0,
                                action: {
                                    var newConfig = settings.config
                                    newConfig.script_mode.active_mode = mode.0
                                    settings.config = newConfig
                                    settings.saveConfig()
                                }
                            )
                        }
                    }
                }

                Divider()

                // Style Section
                VStack(alignment: .leading, spacing: 20) {
                    Text("Transcription Style")
                        .font(.title2)
                        .bold()

                    Text("Choose the default personality for your Riffs.")
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 15) {
                        ForEach(styles, id: \.self) { style in
                            StyleCard(
                                style: style,
                                isSelected: settings.config.style.active_style == style,
                                action: {
                                    settings.config.style.active_style = style
                                    settings.saveConfig()
                                }
                            )
                        }
                    }
                }

                Spacer()
            }
            .padding(30)
        }
    }
}

// MARK: - Metrics View
struct MetricsView: View {
    let metrics: MetricsConfig

    var totalMinutes: Double {
        metrics.total_recording_seconds / 60.0
    }

    var favoriteStyle: String {
        guard !metrics.style_counts.isEmpty else { return "N/A" }
        let sorted = metrics.style_counts.sorted { $0.value > $1.value }
        return sorted.first?.key.capitalized ?? "N/A"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Your Riff Stats")
                .font(.title2)
                .bold()

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricCard(
                    icon: "text.word.spacing",
                    value: formatNumber(metrics.total_words),
                    label: "Words",
                    color: .blue
                )

                MetricCard(
                    icon: "clock.fill",
                    value: String(format: "%.1f", totalMinutes),
                    label: "Minutes",
                    color: .green
                )

                MetricCard(
                    icon: "waveform",
                    value: "\(metrics.total_riffs)",
                    label: "Total Riffs",
                    color: .orange
                )

                MetricCard(
                    icon: "calendar",
                    value: "\(metrics.this_week_riffs)",
                    label: "This Week",
                    color: .purple
                )
            }
        }
    }

    func formatNumber(_ num: Int) -> String {
        if num >= 1_000_000 {
            return String(format: "%.1fM", Double(num) / 1_000_000.0)
        } else if num >= 1_000 {
            return String(format: "%.1fK", Double(num) / 1_000.0)
        } else {
            return "\(num)"
        }
    }
}

struct MetricCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(color)

            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(.primary)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 12)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }
}

import SwiftUI

enum RiffButtonKind {
    case primary, secondary, danger, ghost
}

struct RiffButton: View {
    let title: String
    var icon: String? = nil
    var kind: RiffButtonKind = .primary
    var enabled: Bool = true
    var fullWidth: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                }
                Text(title.uppercased())
                    .font(RiffType.button)
                    .tracking(0.72)
            }
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: 32)
            .padding(.horizontal, 12)
            .background(background)
            .foregroundColor(foreground)
            .overlay(
                RoundedRectangle(cornerRadius: RiffTheme.radiusXS)
                    .stroke(border, lineWidth: 1)
            )
            .cornerRadius(RiffTheme.radiusXS)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 1)
    }

    private var background: Color {
        guard enabled else { return Color.clear }
        switch kind {
        case .primary: return RiffTheme.amber
        case .secondary, .danger, .ghost: return Color.clear
        }
    }

    private var foreground: Color {
        if !enabled { return RiffTheme.inkFaint }
        switch kind {
        case .primary: return RiffTheme.onAmber
        case .secondary: return RiffTheme.ink
        case .danger: return RiffTheme.loss
        case .ghost: return RiffTheme.inkMuted
        }
    }

    private var border: Color {
        if !enabled { return RiffTheme.line }
        switch kind {
        case .primary: return RiffTheme.amber
        case .secondary: return RiffTheme.lineStrong
        case .danger: return RiffTheme.loss
        case .ghost: return Color.clear
        }
    }
}

enum RiffTagKind {
    case neutral, amber, gain, loss
}

struct RiffTag: View {
    let text: String
    var kind: RiffTagKind = .neutral
    var showArrow: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if kind == .gain { Circle().fill(RiffTheme.gain).frame(width: 6, height: 6) }
            if kind == .loss { Circle().fill(RiffTheme.loss).frame(width: 6, height: 6) }
            if showArrow && kind == .gain { Text("▲").font(RiffType.mono(9)) }
            if showArrow && kind == .loss { Text("▼").font(RiffType.mono(9)) }
            Text(text.uppercased())
                .font(RiffType.mono(10))
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 6)
        .frame(height: 20)
        .foregroundColor(foreground)
        .background(background)
        .cornerRadius(RiffTheme.radiusXS)
    }

    private var foreground: Color {
        switch kind {
        case .neutral: return RiffTheme.inkMuted
        case .amber: return RiffTheme.onAmber
        case .gain: return RiffTheme.gain
        case .loss: return RiffTheme.loss
        }
    }

    private var background: Color {
        switch kind {
        case .neutral: return RiffTheme.surface300
        case .amber: return RiffTheme.amber
        case .gain: return RiffTheme.gainWash
        case .loss: return RiffTheme.lossWash
        }
    }
}

struct RiffKeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(RiffType.mono(12))
            .foregroundColor(RiffTheme.ink)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(RiffTheme.surface300)
            .overlay(
                RoundedRectangle(cornerRadius: RiffTheme.radiusXS)
                    .stroke(RiffTheme.lineStrong, lineWidth: 1)
            )
            .overlay(
                Rectangle()
                    .fill(RiffTheme.lineStrong)
                    .frame(height: 2),
                alignment: .bottom
            )
            .cornerRadius(RiffTheme.radiusXS)
    }
}

struct RiffBanner: View {
    let title: String
    let detail: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(RiffTheme.loss)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(RiffType.sans(14, weight: .semibold))
                    .foregroundColor(RiffTheme.ink)
                Text(detail)
                    .font(RiffType.bodySM)
                    .foregroundColor(RiffTheme.inkMuted)
            }
            Spacer(minLength: 8)
            RiffButton(title: actionTitle, kind: .primary, action: action)
        }
        .padding(12)
        .background(RiffTheme.lossWash)
        .overlay(
            RoundedRectangle(cornerRadius: RiffTheme.radiusSM)
                .stroke(RiffTheme.loss, lineWidth: 1)
        )
        .cornerRadius(RiffTheme.radiusSM)
    }
}

struct RiffSegmentedControl: View {
    let options: [(id: String, label: String)]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                Button(action: { selection = option.id }) {
                    Text(option.label)
                        .font(RiffType.sans(13, weight: selection == option.id ? .semibold : .regular))
                        .foregroundColor(selection == option.id ? RiffTheme.onAmber : RiffTheme.inkMuted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(selection == option.id ? RiffTheme.amber : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < options.count - 1 {
                    Rectangle().fill(RiffTheme.line).frame(width: 1, height: 32)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: RiffTheme.radiusXS)
                .stroke(RiffTheme.lineStrong, lineWidth: 1)
        )
        .cornerRadius(RiffTheme.radiusXS)
    }
}

struct RiffEmptyState: View {
    let icon: String
    let title: String
    let detail: String
    var keycap: String? = nil
    var primaryTitle: String? = nil
    var primaryAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(RiffTheme.amberInk)
                .frame(width: 36, height: 36)
                .background(RiffTheme.amberWash)
                .cornerRadius(RiffTheme.radiusSM)
            Text(title)
                .font(RiffType.h2)
                .foregroundColor(RiffTheme.ink)
            HStack(spacing: 6) {
                Text(detail)
                    .font(RiffType.bodySM)
                    .foregroundColor(RiffTheme.inkMuted)
                if let keycap {
                    RiffKeyCap(text: keycap)
                }
            }
            if let primaryTitle, let primaryAction {
                RiffButton(title: primaryTitle, kind: .primary, action: primaryAction)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .overlay(
            RoundedRectangle(cornerRadius: RiffTheme.radiusSM)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundColor(RiffTheme.lineStrong)
        )
    }
}

struct RiffStatStrip: View {
    let metrics: MetricsConfig

    var body: some View {
        HStack(spacing: 0) {
            cell("WORDS", formatNumber(metrics.total_words))
            divider
            cell("MINUTES", String(format: "%.1f", metrics.total_recording_seconds / 60.0))
            divider
            cell("TOTAL RIFFS", "\(metrics.total_riffs)")
            divider
            cell("THIS WEEK", "\(metrics.this_week_riffs)")
        }
        .padding(RiffTheme.space4)
        .background(RiffTheme.surface100)
        .overlay(
            RoundedRectangle(cornerRadius: RiffTheme.radiusSM)
                .stroke(RiffTheme.line, lineWidth: 1)
        )
        .cornerRadius(RiffTheme.radiusSM)
    }

    private var divider: some View {
        Rectangle().fill(RiffTheme.line).frame(width: 1, height: 36)
    }

    private func cell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(RiffType.label)
                .tracking(1.1)
                .foregroundColor(RiffTheme.inkFaint)
            Text(value)
                .font(RiffType.numLG)
                .foregroundColor(RiffTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }

    private func formatNumber(_ num: Int) -> String {
        if num >= 1_000_000 { return String(format: "%.1fM", Double(num) / 1_000_000.0) }
        if num >= 1_000 { return String(format: "%.1fK", Double(num) / 1_000.0) }
        return "\(num)"
    }
}

struct RiffTabBar: View {
    let tabs: [(id: String, label: String)]
    @Binding var selection: String
    var problemIDs: Set<String> = []

    var body: some View {
        HStack(spacing: 20) {
            ForEach(tabs, id: \.id) { tab in
                Button(action: { selection = tab.id }) {
                    HStack(spacing: 6) {
                        Text(tab.label)
                            .font(RiffType.sans(14, weight: .medium))
                            .foregroundColor(selection == tab.id ? RiffTheme.amberInk : RiffTheme.inkMuted)
                        if problemIDs.contains(tab.id) {
                            Circle().fill(RiffTheme.loss).frame(width: 6, height: 6)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(selection == tab.id ? RiffTheme.amberInk : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(RiffTheme.line).frame(height: 1)
        }
    }
}

struct RiffStatusBar: View {
    let hotkey: String
    let script: String
    let style: String
    let hudState: String
    let hasKey: Bool
    var providerState: String = "unknown"

    var body: some View {
        HStack(spacing: 0) {
            segment("STATE", stateLabel, healthy: stateHealthy)
            hairline
            segment("PTT", RiffHotkey.keycap(hotkey), healthy: true)
            hairline
            segment("SCRIPT", RiffScriptCopy.short(script), healthy: true)
            hairline
            segment("STYLE", style.capitalized, healthy: true)
            hairline
            segment("GROQ", groqLabel, healthy: groqHealthy)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: RiffTheme.statusBarHeight)
        .background(RiffTheme.surface100)
        .overlay(alignment: .top) { Rectangle().fill(RiffTheme.line).frame(height: 1) }
    }

    private var stateLabel: String {
        switch hudState {
        case "recording": return "Recording"
        case "working", "processing": return "Working"
        default: return "Ready"
        }
    }

    private var stateHealthy: Bool {
        hudState != "error"
    }

    private var groqHealthy: Bool {
        hasKey && !["rate_limited", "offline", "key_rejected"].contains(providerState)
    }

    private var groqLabel: String {
        if !hasKey { return "Key missing" }
        switch providerState {
        case "key_rejected": return "Rejected"
        case "rate_limited": return "Limited"
        case "offline": return "Offline"
        default: return "Connected"
        }
    }

    private var hairline: some View {
        Rectangle().fill(RiffTheme.line).frame(width: 1, height: 14).padding(.horizontal, 10)
    }

    private func segment(_ label: String, _ value: String, healthy: Bool) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(RiffType.mono(11))
                .foregroundColor(RiffTheme.inkMuted)
            Text(value.uppercased())
                .font(RiffType.mono(11))
                .foregroundColor(healthy ? RiffTheme.ink : RiffTheme.loss)
        }
    }
}

struct DisabledReason: View {
    let text: String
    var body: some View {
        Text(text)
            .font(RiffType.caption)
            .foregroundColor(RiffTheme.inkFaint)
    }
}

enum RiffFormat {
    static func duration(_ minutes: Double) -> (value: String, unit: String) {
        if minutes >= 60 {
            let hours = Int(minutes) / 60
            let mins = Int(minutes) % 60
            return ("\(hours)h \(mins)m", "")
        }
        if minutes >= 1 {
            return (String(format: "%.0f", minutes), "m")
        }
        return (String(format: "%.0f", minutes * 60), "s")
    }

    static func seconds(_ ms: Int) -> String {
        String(format: "%.1fs", Double(ms) / 1000.0)
    }
}

struct TimeSavedCard: View {
    let stats: StatsSnapshot

    var body: some View {
        let delta = stats.minutes - stats.minutes_prior
        let pct = stats.minutes_prior > 0 ? (delta / stats.minutes_prior) * 100 : 0
        VStack(alignment: .leading, spacing: 12) {
            Text("TIME SAVED · LAST 30 DAYS")
                .font(RiffType.label)
                .tracking(1.1)
                .foregroundColor(RiffTheme.inkFaint)
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    heroFigure
                    if stats.minutes_prior > 0 || delta != 0 {
                        RiffTag(
                            text: stats.minutes_prior > 0
                                ? String(format: "%+.0f%% vs prior 30 days", pct)
                                : String(format: "%+.0fm vs prior 30d", delta),
                            kind: delta >= 0 ? .gain : .loss,
                            showArrow: true
                        )
                    }
                    HStack(spacing: 16) {
                        fact("YOU SPEAK", String(format: "%.0f wpm", speakWPM))
                        fact("YOU TYPE", "\(stats.typing_wpm) wpm")
                        fact("FASTER", String(format: "%.1f×", max(speakWPM / max(Double(stats.typing_wpm), 1), 0)))
                    }
                }
                sparklineBlock
            }
            Text("Saved = words ÷ \(stats.typing_wpm) WPM − time spent speaking. Set your typing speed in Settings.")
                .font(RiffType.caption)
                .foregroundColor(RiffTheme.inkFaint)
        }
        .padding(16)
        .background(RiffTheme.surface100)
        .overlay(RoundedRectangle(cornerRadius: RiffTheme.radiusSM).stroke(RiffTheme.line, lineWidth: 1))
        .cornerRadius(RiffTheme.radiusSM)
    }

    private var heroFigure: some View {
        let hours = Int(stats.minutes) / 60
        let mins = Int(stats.minutes) % 60
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            if hours > 0 {
                Text("\(hours)")
                    .font(RiffType.heroNum)
                    .foregroundColor(RiffTheme.ink)
                Text("h")
                    .font(RiffType.numLG)
                    .foregroundColor(RiffTheme.inkMuted)
            }
            Text(hours > 0 ? "\(mins)" : (stats.minutes >= 1 ? "\(Int(round(stats.minutes)))" : "\(Int(round(stats.minutes * 60)))"))
                .font(RiffType.heroNum)
                .foregroundColor(RiffTheme.ink)
            Text(hours > 0 ? "m" : (stats.minutes >= 1 ? "m" : "s"))
                .font(RiffType.numLG)
                .foregroundColor(RiffTheme.inkMuted)
        }
    }

    private var speakWPM: Double {
        let minutes = max(stats.spoken_minutes_30, 0.01)
        return Double(stats.words_30) / minutes
    }

    private var sparkline: some View {
        let values = stats.series.map(\.minutes)
        let maxV = max(values.max() ?? 0, 0.1)
        return Canvas { context, size in
            let w = size.width
            let h = size.height
            var path = Path()
            for (i, value) in values.enumerated() {
                let x = w * CGFloat(i) / CGFloat(max(values.count - 1, 1))
                let y = h - (CGFloat(value / maxV) * h)
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(RiffTheme.amberInk), lineWidth: 2)
        }
        .frame(width: 240, height: 48)
        .accessibilityLabel("Time saved each day for 30 days")
    }

    private var sparklineAxis: some View {
        HStack {
            Text(shortDate(stats.series.first?.date))
            Spacer()
            Text("Minutes saved per day")
            Spacer()
            Text(shortDate(stats.series.last?.date))
        }
        .font(RiffType.caption)
        .foregroundColor(RiffTheme.inkFaint)
    }

    private var sparklineBlock: some View {
        VStack(alignment: .trailing, spacing: 6) {
            sparkline
                .frame(minWidth: 180, maxWidth: 280, minHeight: 48, maxHeight: 48)
            sparklineAxis
                .frame(minWidth: 180, maxWidth: 280)
        }
    }

    private func shortDate(_ iso: String?) -> String {
        guard let iso, iso.count >= 10 else { return "" }
        let parts = iso.split(separator: "-")
        guard parts.count == 3 else { return iso }
        let months = ["JAN","FEB","MAR","APR","MAY","JUN","JUL","AUG","SEP","OCT","NOV","DEC"]
        let month = Int(parts[1]) ?? 1
        return "\(parts[2]) \(months[max(0, min(month - 1, 11))])"
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(RiffType.label).tracking(1.1).foregroundColor(RiffTheme.inkFaint)
            Text(value).font(RiffType.num).foregroundColor(RiffTheme.ink)
        }
    }
}

struct StreakStrip: View {
    let stats: StatsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("STREAK")
                    .font(RiffType.label)
                    .tracking(1.1)
                    .foregroundColor(RiffTheme.inkFaint)
                Spacer()
                Text(stats.streak_days == 1 ? "1 day" : (stats.streak_days > 0 ? "\(stats.streak_days) days" : "Start today"))
                    .font(RiffType.numLG)
                    .foregroundColor(RiffTheme.ink)
            }
            let cells = Array(stats.streak_cells.suffix(84))
            let rows = 7
            let cols = 12
            HStack(spacing: 3) {
                ForEach(0..<cols, id: \.self) { col in
                    VStack(spacing: 3) {
                        ForEach(0..<rows, id: \.self) { row in
                            let idx = col * rows + row
                            RoundedRectangle(cornerRadius: 2)
                                .fill(cellColor(idx < cells.count ? cells[idx].level : 0))
                                .frame(width: 11, height: 11)
                                .help(idx < cells.count ? "\(cells[idx].date) · \(cells[idx].minutes)m" : "")
                        }
                    }
                }
            }
            HStack(spacing: 4) {
                Text("Less").font(RiffType.caption).foregroundColor(RiffTheme.inkFaint)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(cellColor(level))
                        .frame(width: 11, height: 11)
                }
                Text("More").font(RiffType.caption).foregroundColor(RiffTheme.inkFaint)
            }
        }
        .padding(16)
        .background(RiffTheme.surface100)
        .overlay(RoundedRectangle(cornerRadius: RiffTheme.radiusSM).stroke(RiffTheme.line, lineWidth: 1))
        .cornerRadius(RiffTheme.radiusSM)
        .accessibilityLabel("Streak \(stats.streak_days) days")
    }

    private func cellColor(_ level: Int) -> Color {
        switch level {
        case 1: return RiffTheme.amberInk.opacity(0.25)
        case 2: return RiffTheme.amberInk.opacity(0.45)
        case 3: return RiffTheme.amberInk.opacity(0.7)
        case 4: return RiffTheme.amberInk
        default: return RiffTheme.surface300
        }
    }
}

struct TimingBar: View {
    let transcribe: Int
    let rewrite: Int
    let type: Int

    var body: some View {
        let total = max(transcribe + rewrite + type, 1)
        let parts: [(String, Int)] = [
            ("Transcribe", transcribe),
            ("Rewrite", rewrite),
            ("Type", type)
        ]
        let slowest = parts.max(by: { $0.1 < $1.1 })?.0
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(parts, id: \.0) { part in
                        Rectangle()
                            .fill(part.0 == slowest ? RiffTheme.amberInk : RiffTheme.surface300)
                            .frame(width: max(4, geo.size.width * CGFloat(part.1) / CGFloat(total)))
                    }
                }
            }
            .frame(height: 8)
            HStack {
                ForEach(parts, id: \.0) { part in
                    Text("\(part.0) \(RiffFormat.seconds(part.1))")
                        .font(RiffType.num)
                        .foregroundColor(part.0 == slowest ? RiffTheme.amberInk : RiffTheme.inkMuted)
                    if part.0 != "Type" { Spacer() }
                }
            }
        }
    }
}

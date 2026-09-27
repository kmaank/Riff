import SwiftUI
import AppKit

struct HistoryView: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var authManager: SwiftAuthManager
    @State private var query = ""
    @State private var expandedID: String?
    @State private var filter = "all"

    private var flaggedCount: Int {
        settings.history.filter { $0.likely_noise == true }.count
    }

    private var filtered: [HistoryEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return settings.history.filter { entry in
            if filter == "flagged" && entry.likely_noise != true { return false }
            if q.isEmpty { return true }
            return entry.refined.lowercased().contains(q)
                || entry.original.lowercased().contains(q)
                || entry.style.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("History")
                    .font(RiffType.h1)
                    .foregroundColor(RiffTheme.ink)
                Spacer()
            }
            .padding(.horizontal, RiffTheme.space6)
            .padding(.top, RiffTheme.space5)

            if let metrics = settings.config.metrics, metrics.total_riffs > 0 {
                RiffStatStrip(metrics: metrics)
                    .padding(.horizontal, RiffTheme.space6)
            }

            if settings.history.isEmpty {
                RiffEmptyState(
                    icon: "clock.arrow.circlepath",
                    title: "No riffs yet.",
                    detail: "Hold",
                    keycap: RiffHotkey.keycap(settings.config.hotkey.combination)
                )
                .padding(.horizontal, RiffTheme.space6)
                Spacer()
            } else {
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(RiffTheme.inkFaint)
                    TextField("Search riffs", text: $query)
                        .textFieldStyle(.plain)
                        .font(RiffType.body)
                        .foregroundColor(RiffTheme.ink)
                    }
                    RiffSegmentedControl(
                        options: [
                            ("all", "All"),
                            ("flagged", flaggedCount > 0 ? "Flagged \(flaggedCount)" : "Flagged")
                        ],
                        selection: $filter
                    )
                    .frame(width: 220)
                }
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(RiffTheme.surface200)
                .overlay(RoundedRectangle(cornerRadius: RiffTheme.radiusXS).stroke(RiffTheme.lineStrong, lineWidth: 1))
                .cornerRadius(RiffTheme.radiusXS)
                .padding(.horizontal, RiffTheme.space6)

                if filtered.isEmpty {
                    RiffEmptyState(
                        icon: "magnifyingglass",
                        title: "No matches.",
                        detail: "Try another word."
                    )
                    .padding(.horizontal, RiffTheme.space6)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(filtered) { entry in
                                HistoryRow(
                                    entry: entry,
                                    compact: false,
                                    expanded: expandedID == entry.id,
                                    onToggle: {
                                        expandedID = expandedID == entry.id ? nil : entry.id
                                    },
                                    onDelete: {
                                        settings.deleteHistory(timestamp: entry.timestamp)
                                        if expandedID == entry.id { expandedID = nil }
                                        Task { await authManager.deleteCloudHistory(timestamp: entry.timestamp) }
                                    }
                                )
                            }
                        }
                        .background(RiffTheme.surface100)
                        .overlay(RoundedRectangle(cornerRadius: RiffTheme.radiusSM).stroke(RiffTheme.line, lineWidth: 1))
                        .cornerRadius(RiffTheme.radiusSM)
                        .padding(.horizontal, RiffTheme.space6)
                        .padding(.bottom, RiffTheme.space6)
                    }
                }
            }
        }
        .background(RiffTheme.surface000)
    }
}

struct HistoryRow: View {
    let entry: HistoryEntry
    var compact: Bool = false
    var expanded: Bool = false
    var onToggle: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                RiffTag(text: entry.style, kind: .neutral)
                    .frame(width: 76, alignment: .leading)
                Text(entry.refined)
                    .font(RiffType.body)
                    .foregroundColor(RiffTheme.ink)
                    .lineLimit(expanded ? nil : (compact ? 2 : 3))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let onToggle {
                            onToggle()
                        } else {
                            copyText()
                        }
                    }
                if entry.likely_noise == true {
                    RiffTag(text: "Likely noise", kind: .loss)
                }
                if let ms = entry.round_trip_ms, ms > 0 {
                    Text(RiffFormat.seconds(ms))
                        .font(RiffType.num)
                        .foregroundColor(ms > 3000 ? RiffTheme.loss : RiffTheme.inkMuted)
                }
                if !compact {
                    Text(RiffDate.history(entry.timestamp))
                        .font(RiffType.mono(12))
                        .foregroundColor(RiffTheme.inkFaint)
                }
                Button(action: copyText) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(RiffTheme.inkMuted)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Copy text")
                .accessibilityLabel("Copy riff")
                if onDelete != nil {
                    Button(action: { confirmDelete = true }) {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(RiffTheme.loss)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Delete riff")
                    .accessibilityLabel("Delete riff")
                    .popover(isPresented: $confirmDelete, arrowEdge: .leading) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Delete this riff?")
                                .font(RiffType.h2)
                                .foregroundColor(RiffTheme.ink)
                            Text("Removes it from History on this Mac.")
                                .font(RiffType.bodySM)
                                .foregroundColor(RiffTheme.inkMuted)
                            HStack(spacing: 8) {
                                Spacer()
                                RiffButton(title: "Cancel", kind: .ghost, action: { confirmDelete = false })
                                RiffButton(title: "Delete", kind: .danger, action: {
                                    confirmDelete = false
                                    onDelete?()
                                })
                            }
                        }
                        .padding(14)
                        .frame(width: 260)
                    }
                }
            }
            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text("RAW")
                        .font(RiffType.label)
                        .tracking(1.1)
                        .foregroundColor(RiffTheme.inkFaint)
                    Text(entry.original)
                        .font(RiffType.bodySM)
                        .foregroundColor(RiffTheme.inkMuted)
                    Text("REWRITE")
                        .font(RiffType.label)
                        .tracking(1.1)
                        .foregroundColor(RiffTheme.inkFaint)
                    Text(entry.refined)
                        .font(RiffType.bodySM)
                        .foregroundColor(RiffTheme.ink)
                    if let t = entry.transcribe_ms, let r = entry.rewrite_ms, let p = entry.type_ms {
                        TimingBar(transcribe: t, rewrite: r, type: p)
                    }
                }
                .padding(12)
                .background(RiffTheme.surface200)
                .cornerRadius(RiffTheme.radiusSM)
            }
        }
        .padding(12)
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(RiffTheme.line).frame(height: 1)
        }
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.refined, forType: .string)
    }
}

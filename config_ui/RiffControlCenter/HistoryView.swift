import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var settings: SettingsManager
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("History")
                .font(.title2)
                .bold()
                .padding(.horizontal, 30)
                .padding(.top, 30)
                
            List {
                if settings.history.isEmpty {
                    Text("No riffs yet. Go make some noise!")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    ForEach(settings.history) { entry in
                        HistoryRow(entry: entry)
                            .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.inset)
        }
    }
}

struct HistoryRow: View {
    let entry: HistoryEntry
    @State private var hover = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.style.uppercased())
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
                
                Spacer()
                
                Text(formatDate(entry.timestamp))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.refined, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
            }
            
            Text(entry.refined)
                .font(.body)
                .lineLimit(3)
        }
        .padding(10)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(8)
        .onTapGesture {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.refined, forType: .string)
        }
    }
    
    func formatDate(_ iso: String) -> String {
        // "Wall Clock" Strategy:
        // The backend saves Local Time (e.g. 20:48). We want to see 20:48.
        // We force both Parser and Display to use GMT. This treats the numbers as literals
        // and prevents any system timezone offsets from shifting the time.
        
        // 1. Parser (Treat input string as GMT)
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .iso8601)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0) // GMT
        
        var date: Date?
        
        // Attempt 1: Full precision
        parser.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        date = parser.date(from: iso)
        
        // Attempt 2: No fractional seconds
        if date == nil {
            parser.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            date = parser.date(from: iso)
        }
        
        // Attempt 3: ISO Standard parser (fallback)
        if date == nil {
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            isoFormatter.timeZone = TimeZone(secondsFromGMT: 0) // GMT
            date = isoFormatter.date(from: iso)
        }

        if let validDate = date {
            return formatDisplayDate(validDate)
        }

        // Fallback: Just show raw string if parsing fails
        return iso.components(separatedBy: "T").last?.components(separatedBy: ".").first ?? iso
    }
    
    func formatDisplayDate(_ date: Date) -> String {
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium // e.g. Jan 28, 2026
        displayFormatter.timeStyle = .short  // e.g. 8:48 PM
        displayFormatter.timeZone = TimeZone(secondsFromGMT: 0) // GMT (Crucial: Don't shift back to local)
        return displayFormatter.string(from: date)
    }
}

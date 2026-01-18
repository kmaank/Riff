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
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .onTapGesture {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.refined, forType: .string)
        }
    }
    
    func formatDate(_ iso: String) -> String {
        // Simple parser
        return iso.components(separatedBy: "T").last?.components(separatedBy: ".").first ?? iso
    }
}

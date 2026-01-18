import SwiftUI

struct StyleView: View {
    @EnvironmentObject var settings: SettingsManager
    
    let styles = ["formal", "casual"]
    
    var body: some View {
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
            .padding(.top)
            
            Spacer()
        }
        .padding(30)
    }
}

struct StyleCard: View {
    let style: String
    let isSelected: Bool
    let action: () -> Void
    
    var icon: String {
        switch style {
        case "code": return "chevron.left.forwardslash.chevron.right"
        case "pirate": return "flag.fill"
        case "formal": return "suit.tie.fill"
        case "casual": return "bubble.left.fill"
        case "tweet": return "bird.fill"
        default: return "sparkles"
        }
    }
    
    var color: Color {
        switch style {
        case "code": return .blue
        case "pirate": return .red
        case "formal": return .gray
        case "casual": return .purple
        case "tweet": return .cyan
        default: return .orange
        }
    }
    
    var body: some View {
        Button(action: action) {
            VStack {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(isSelected ? .white : color)
                    .padding(.bottom, 5)
                
                Text(style.capitalized)
                    .font(.headline)
                    .foregroundStyle(isSelected ? .white : .primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? color : Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? color.opacity(0.0) : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

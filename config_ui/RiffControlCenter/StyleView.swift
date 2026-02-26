import SwiftUI

struct StyleView: View {
    @EnvironmentObject var settings: SettingsManager
    
    let styles = ["clean", "formal", "casual", "riff"]
    
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
    var isLocked: Bool = false
    let action: () -> Void
    
    var icon: String {
        switch style {
        case "clean": return "wand.and.stars"
        case "code": return "chevron.left.forwardslash.chevron.right"
        case "pirate": return "flag.fill"
        case "formal": return "suit.tie.fill"
        case "casual": return "bubble.left.fill"
        case "tweet": return "bird.fill"
        case "riff": return "music.note"
        default: return "sparkles"
        }
    }
    
    var color: Color {
        switch style {
        case "clean": return .teal
        case "code": return .blue
        case "pirate": return .red
        case "formal": return .gray
        case "casual": return .purple
        case "tweet": return .cyan
        case "riff": return .pink
        default: return .orange
        }
    }
    
    var body: some View {
        Button(action: action) {
            VStack {
                ZStack {
                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundStyle(isLocked ? .gray.opacity(0.5) : (isSelected ? .white : color))
                        .padding(.bottom, 5)

                    // Lock icon overlay for locked styles
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                            .offset(x: 12, y: -12)
                    }
                }

                Text(style.capitalized)
                    .font(.headline)
                    .foregroundStyle(isLocked ? .gray.opacity(0.5) : (isSelected ? .white : .primary))

                if isLocked {
                    Text("Upgrade")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isLocked ? Color.gray.opacity(0.05) : (isSelected ? color : Color.gray.opacity(0.08)))
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isLocked ? Color.orange.opacity(0.3) : (isSelected ? color.opacity(0.0) : Color.gray.opacity(0.15)), lineWidth: isLocked ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
        .opacity(isLocked ? 0.7 : 1.0)
    }
}

import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("How to Riff")
                    .font(.title2)
                    .bold()
                    .padding(.bottom, 10)
                
                Group {
                    HelpSection(icon: "mic.fill", title: "1. Speak", bodyText: "Hold your **Trigger Key** (Default: F8). Speak naturally. Riff listens while you hold.")
                    HelpSection(icon: "brain.head.profile", title: "2. Think", bodyText: "Release the key. Riff processes your audio using Groq + Llama 3 for super-fast, context-aware logical refinement.")
                    HelpSection(icon: "text.cursor", title: "3. Type", bodyText: "Riff types the refined text directly into your active window. No pasting required.")
                }
                
                Divider().padding(.vertical)
                
                Text("Tips & Tricks")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 12) {
                    TipRow(text: "**Context Aware:** Riff sees what app you are using and adapts. Coding in VS Code? It formats as code.")
                    TipRow(text: "**Latch Mode:** Hold **Shift + Trigger** to start a long recording session without holding the key. Tap Trigger again to stop.")
                    TipRow(text: "**Styles:** Use the **Style** tab to force specific personalities like 'Pirate' or 'Formal'.")
                }
            }
            .padding(30)
        }
    }
}

struct HelpSection: View {
    let icon: String
    let title: String
    let bodyText: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .font(.title)
                .frame(width: 30)
                .foregroundStyle(.orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(.init(bodyText)) // Markdown init
                    .foregroundStyle(.secondary)
                    .font(.body)
            }
        }
    }
}

struct TipRow: View {
    let text: String
    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.yellow)
            Text(.init(text))
                .foregroundStyle(.secondary)
        }
    }
}

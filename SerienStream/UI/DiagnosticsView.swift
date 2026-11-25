import SwiftUI

/// Zeigt die In-App-Debuglogs — für Fehlerberichte und CI-Verification.
struct DiagnosticsView: View {
    @State private var lines: [String] = []
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Diagnose")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(DS.textPrimary)
                Spacer()
                Button {
                    UIPasteboard.general.string = lines.joined(separator: "\n")
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(DS.accent)
                        .padding(8)
                        .glass(radius: 8)
                }
                .buttonStyle(.plain)
                Button {
                    DebugLog.shared.clear()
                    lines = []
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.red)
                        .padding(8)
                        .glass(radius: 8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)

            Text("Bei Problemen: Log kopieren und melden.")
                .font(.footnote)
                .foregroundColor(DS.textSecondary)
                .padding(.horizontal)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(lines.indices, id: \.self) { i in
                        Text(lines[i])
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(color(for: lines[i]))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
            }
            .frame(height: 220)
            .background(Color.black.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DS.glassStroke, lineWidth: 1)
            )
            .padding(.horizontal)
        }
        .onAppear {
            lines = DebugLog.shared.all()
        }
    }

    private func color(for line: String) -> Color {
        if line.contains("Fehler") || line.contains("fehlgeschlagen") { return .red.opacity(0.9) }
        if line.contains("OK") || line.contains("gefunden") || line.contains("abgefangen") { return .green.opacity(0.85) }
        return DS.textSecondary
    }
}

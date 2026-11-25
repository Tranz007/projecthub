import SwiftUI

struct ServiceLogsView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    let project: Project

    var body: some View {
        let output = store.running[project.id]?.output ?? store.recentOutput[project.id] ?? ""
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("\(project.name) server logs").font(.headline)
                    if let service = store.running[project.id] {
                        Text("Port \(service.port) · \(service.command)")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Button("Close") { dismiss() }
            }
            ScrollView {
                Text(output.isEmpty ? "Waiting for output…" : output)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
            }
            .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
        .frame(width: 680, height: 420)
    }
}

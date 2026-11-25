import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: ProjectStore

    var body: some View {
        TabView {
            Form {
                Section("Project folders") {
                    Text("Project Hub scans the immediate subfolders of these locations.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(store.settings.scanFolders, id: \.self) { path in
                        HStack {
                            Text(path).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button(role: .destructive) { store.removeScanFolder(path) } label: {
                                Image(systemName: "minus.circle")
                            }.buttonStyle(.plain).accessibilityLabel("Remove \(path)")
                        }
                    }
                    Button("Add folder…") { chooseFolder() }
                    if store.settings.scanFolders.isEmpty {
                        Text("Add a folder to discover projects.").foregroundStyle(.secondary)
                    }
                }
            }
            .tabItem { Label("Projects", systemImage: "folder") }

            Form {
                Picker("Preferred editor", selection: $store.settings.preferredEditor) {
                    ForEach(["Cursor", "Visual Studio Code", "Zed", "Custom"], id: \.self) { Text($0).tag($0) }
                }
                if store.settings.preferredEditor == "Custom" {
                    TextField("Application path", text: $store.settings.customEditorPath)
                        .textFieldStyle(.roundedBorder)
                }
                Picker("AI tool", selection: $store.settings.aiTool) {
                    ForEach(["Codex", "Claude Code", "Gemini CLI", "Custom"], id: \.self) { Text($0).tag($0) }
                }
                if store.settings.aiTool == "Custom" {
                    TextField("Command to run in Terminal", text: $store.settings.customAICommand)
                        .textFieldStyle(.roundedBorder)
                }
                Text("Install the selected command-line tool separately. Project Hub starts it in the selected project folder.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .tabItem { Label("Tools", systemImage: "terminal") }
        }
        .frame(width: 520, height: 300)
        .padding(20)
        .onChange(of: store.settings.preferredEditor) { _, _ in store.savePreferences() }
        .onChange(of: store.settings.customEditorPath) { _, _ in store.savePreferences() }
        .onChange(of: store.settings.aiTool) { _, _ in store.savePreferences() }
        .onChange(of: store.settings.customAICommand) { _, _ in store.savePreferences() }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        if panel.runModal() == .OK {
            for url in panel.urls { store.addScanFolder(url) }
        }
    }
}

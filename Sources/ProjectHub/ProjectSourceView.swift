import SwiftUI

struct ProjectSourceView: View {
    @EnvironmentObject private var store: ProjectStore
    let welcome: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 32))
                .foregroundStyle(.blue)
            Text(welcome ? "Welcome to Project Hub" : "No projects found")
                .font(.title2.bold())
            Text("Choose a folder to scan its immediate subfolders, or add one project directly.")
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Choose Folder…") { chooseFolder() }
                    .buttonStyle(.borderedProminent)
                Button("Add Project…") { chooseProject() }
                    .buttonStyle(.bordered)
            }
            if welcome {
                Button("Continue with Desktop") { store.completeWelcome() }
                    .buttonStyle(.link)
                Text("Project Hub will also scan the immediate folders on your Desktop. You can change this in Settings.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(28)
        .frame(maxWidth: welcome ? 440 : .infinity, alignment: .leading)
    }

    private func chooseFolder() {
        let folders = ProjectPicker.chooseFolders(multiple: true, prompt: "Choose")
        guard !folders.isEmpty else { return }
        for folder in folders { store.addScanFolder(folder) }
        if welcome { store.completeWelcome() }
    }

    private func chooseProject() {
        guard let folder = ProjectPicker.chooseFolders(multiple: false, prompt: "Add Project").first else { return }
        if store.addProject(folder), welcome { store.completeWelcome() }
    }
}

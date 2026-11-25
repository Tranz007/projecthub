import AppKit

@MainActor
enum ProjectPicker {
    static func chooseFolders(multiple: Bool, prompt: String) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = multiple
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.urls : []
    }
}

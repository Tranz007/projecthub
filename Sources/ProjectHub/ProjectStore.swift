import AppKit
import Darwin
import Foundation
import SwiftUI

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [Project] = []
    @Published private(set) var running: [String: RunningService] = [:]
    @Published private(set) var recentOutput: [String: String] = [:]
    @Published var search = ""
    @Published var selectedFilter: Filter = .all
    @Published var settings = SavedSettings()
    @Published var alert: AppAlert?
    @Published private var listeningPorts = Set<Int>()

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All Projects"
        case favorites = "Favorites"
        case running = "Running"
        var id: String { rawValue }
    }

    struct AppAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let actionLabel: String?
        let action: (() -> Void)?

        init(
            title: String,
            message: String,
            actionLabel: String? = nil,
            action: (() -> Void)? = nil
        ) {
            self.title = title
            self.message = message
            self.actionLabel = actionLabel
            self.action = action
        }
    }

    private var refreshTimer: Timer?

    init() {
        loadSettings()
        refreshProjects()
        refreshPortSnapshot()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in Task { @MainActor in self?.refreshPortSnapshot() } }
    }

    var visibleProjects: [Project] {
        let text = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return projects.filter { project in
            let matchesText = text.isEmpty || [project.name, project.description ?? "", project.kind.rawValue]
                .joined(separator: " ").lowercased().contains(text)
            let matchesFilter: Bool
            switch selectedFilter {
            case .all: matchesFilter = true
            case .favorites: matchesFilter = setting(for: project).favorite
            case .running: matchesFilter = status(for: project).isRunning
            }
            return matchesText && matchesFilter
        }
    }

    func refreshProjects() {
        var folders: [URL] = []
        var inaccessible: [String] = []
        for root in settings.scanFolders {
            do {
                folders += try FileManager.default.contentsOfDirectory(
                    at: URL(filePath: root), includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
                )
            } catch {
                inaccessible.append(root)
            }
        }
        if !inaccessible.isEmpty {
            alert = AppAlert(title: "Cannot read project folders", message: "Check access to: \(inaccessible.joined(separator: ", "))")
        }

        var seenPaths = Set<String>()
        projects = folders.filter { seenPaths.insert($0.standardizedFileURL.path()).inserted }.compactMap { folder -> Project? in
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            let packageURL = folder.appending(path: "package.json")
            let pythonURL = folder.appending(path: "pyproject.toml")
            let gitURL = folder.appending(path: ".git", directoryHint: .isDirectory)
            let hasPackage = FileManager.default.fileExists(atPath: packageURL.path())
            let hasPython = FileManager.default.fileExists(atPath: pythonURL.path())
            let hasGit = FileManager.default.fileExists(atPath: gitURL.path())
            guard hasPackage || hasPython || hasGit else { return nil }

            let package = hasPackage ? Self.readPackage(at: packageURL) : nil
            let kind: Project.ProjectKind = hasPackage && hasPython ? .mixed : hasPackage ? .node : hasPython ? .python : .git
            let defaultCommand = Self.defaultCommand(package: package)
            let isFastAPI = (try? String(contentsOf: pythonURL, encoding: .utf8))?.lowercased().contains("fastapi") == true
            let branch = hasGit ? Self.run("/usr/bin/git", ["-C", folder.path(), "branch", "--show-current"]).nilIfEmpty : nil
            let changes = hasGit ? Int(Self.run("/usr/bin/git", ["-C", folder.path(), "status", "--porcelain=v1"]).split(separator: "\n").count) : nil
            let remote = hasGit ? Self.githubURL(Self.run("/usr/bin/git", ["-C", folder.path(), "remote", "get-url", "origin"])) : nil
            let order = max(0, folders.firstIndex(of: folder) ?? 0)
            let path = folder.path()
            let projectID = path.hasSuffix("/") ? String(path.dropLast()) : path
            return Project(
                id: projectID, name: folder.lastPathComponent, path: folder, kind: kind,
                techSummary: Self.techSummary(package: package, hasPackage: hasPackage, hasPython: hasPython, isFastAPI: isFastAPI), repositoryURL: remote,
                branch: branch, changedFiles: changes, description: package?.description,
                defaultCommand: defaultCommand, defaultPort: 3000 + order
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func setting(for project: Project) -> ProjectSettings { settings.projects[project.id] ?? ProjectSettings() }

    func addScanFolder(_ url: URL) {
        let path = url.standardizedFileURL.path()
        guard !settings.scanFolders.contains(path) else { return }
        settings.scanFolders.append(path)
        persistSettings()
        refreshProjects()
    }

    func removeScanFolder(_ path: String) {
        settings.scanFolders.removeAll { $0 == path }
        persistSettings()
        refreshProjects()
    }

    func savePreferences() { persistSettings() }

    func command(for project: Project) -> String? { setting(for: project).command ?? project.defaultCommand }

    func port(for project: Project) -> Int { setting(for: project).preferredPort ?? project.defaultPort }

    func status(for project: Project) -> (isRunning: Bool, port: Int?, managed: Bool, portBusy: Bool, ready: Bool) {
        if let service = running[project.id], service.process.isRunning {
            return (true, service.port, true, false, listeningPorts.contains(service.port))
        }
        let configuredPort = port(for: project)
        return (false, configuredPort, false, listeningPorts.contains(configuredPort), false)
    }

    func save(project: Project, command: String, port: Int, favorite: Bool) {
        settings.projects[project.id] = ProjectSettings(command: command.nilIfEmpty, preferredPort: port, favorite: favorite)
        persistSettings()
    }

    func toggleFavorite(_ project: Project) {
        var item = setting(for: project)
        item.favorite.toggle()
        settings.projects[project.id] = item
        persistSettings()
    }

    func start(_ project: Project) {
        guard running[project.id] == nil else { return }
        startService(project)
    }

    private func startService(_ project: Project) {
        guard running[project.id] == nil else { return }
        guard let template = command(for: project) else {
            alert = AppAlert(title: "Configure \(project.name)", message: "This project has no safe default dev command. Use Configure to add one before starting it.")
            return
        }
        let requested = port(for: project)
        guard let chosenPort = Self.firstFreePort(startingAt: requested) else {
            alert = AppAlert(title: "No free port found", message: "Project Hub could not find a free local port in the next 100 ports.")
            return
        }
        let command = template.replacingOccurrences(of: "{port}", with: String(chosenPort))
        let process = Process()
        process.executableURL = URL(filePath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = project.path
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (environment["PATH"] ?? "")
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        let id = project.id
        recentOutput[id] = ""
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                guard var service = self?.running[id] else { return }
                service.output = String((service.output + text).suffix(12_000))
                self?.running[id] = service
                self?.recentOutput[id] = service.output
            }
        }
        process.terminationHandler = { [weak self] _ in
            output.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in self?.running.removeValue(forKey: id) }
        }
        do {
            try process.run()
            running[project.id] = RunningService(id: UUID().uuidString, projectID: project.id, port: chosenPort, command: command, process: process, startedAt: .now)
        } catch {
            alert = AppAlert(title: "Could not start \(project.name)", message: error.localizedDescription)
        }
    }

    func stop(_ project: Project) {
        guard let service = running[project.id] else { return }
        for child in Self.descendants(of: service.process.processIdentifier).reversed() {
            kill(child, SIGTERM)
        }
        service.process.terminate()
        running.removeValue(forKey: project.id)
    }

    var aiToolLabel: String { settings.aiTool == "Custom" ? "AI tool" : settings.aiTool }

    func openInAI(_ project: Project) {
        let command: String
        switch settings.aiTool {
        case "Codex":
            let bundled = "/Applications/ChatGPT.app/Contents/Resources/codex"
            command = FileManager.default.isExecutableFile(atPath: bundled) ? shellQuote(bundled) : "codex"
        case "Claude Code": command = "claude"
        case "Gemini CLI": command = "gemini"
        case "Custom": command = settings.customAICommand.trimmingCharacters(in: .whitespacesAndNewlines)
        default: command = ""
        }
        guard !command.isEmpty else {
            alert = AppAlert(title: "Set up an AI tool", message: "Choose a tool or enter a custom command in Settings.")
            return
        }
        openTerminal(project, command: command)
    }

    func openInEditor(_ project: Project) {
        let path = settings.preferredEditor == "Custom" ? settings.customEditorPath : "/Applications/\(settings.preferredEditor).app"
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
            alert = AppAlert(title: "Editor not found", message: "Choose an installed editor in Settings.")
            return
        }
        openApplication(at: URL(filePath: path), project: project.path)
    }
    private func openTerminal(_ project: Project, command: String?) {
        let initial = "cd \(shellQuote(project.path.path()))"
        let commandLine = command.map { "\(initial) && \($0); exec zsh -l" } ?? "\(initial); exec zsh -l"
        let escaped = commandLine.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = "tell application \"Terminal\"\nactivate\ndo script \"\(escaped)\"\nend tell"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { alert = AppAlert(title: "Could not open Terminal", message: error.description) }
    }
    func openInFinder(_ project: Project) { NSWorkspace.shared.activateFileViewerSelecting([project.path]) }
    func openURL(for project: Project) {
        let current = status(for: project)
        guard current.ready, let port = current.port else { return }
        NSWorkspace.shared.open(URL(string: "http://localhost:\(port)")!)
    }
    func openRepository(_ project: Project) { if let url = project.repositoryURL { NSWorkspace.shared.open(url) } }

    private func refreshPortSnapshot() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let output = Self.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN"])
            let ports = Set(output.split(separator: "\n").compactMap { line -> Int? in
                guard let range = line.range(of: #":\d+"#, options: .regularExpression) else { return nil }
                return Int(line[range].dropFirst())
            })
            Task { @MainActor in self?.listeningPorts = ports }
        }
    }

    private func openApplication(at application: URL, project: URL) {
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([project], withApplicationAt: application, configuration: config) { [weak self] _, error in
            guard let error else { return }
            Task { @MainActor in
                self?.alert = AppAlert(title: "Could not open editor", message: error.localizedDescription)
            }
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private func loadSettings() {
        guard let data = try? Data(contentsOf: settingsURL), let saved = try? JSONDecoder().decode(SavedSettings.self, from: data) else { return }
        settings = saved
        for (path, value) in saved.projects where path.hasSuffix("/") {
            let normalized = String(path.dropLast())
            if settings.projects[normalized] == nil { settings.projects[normalized] = value }
            settings.projects.removeValue(forKey: path)
        }
    }

    private func persistSettings() {
        let folder = settingsURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: settingsURL, options: .atomic)
    }

    private var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/ProjectHub/settings.json")
    }

    private struct PackageFile: Decodable { let description: String?; let scripts: [String: String]?; let dependencies: [String: String]?; let devDependencies: [String: String]? }
    private static func readPackage(at url: URL) -> PackageFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PackageFile.self, from: data)
    }
    nonisolated private static func run(_ path: String, _ args: [String]) -> String {
        let task = Process(); task.executableURL = URL(filePath: path); task.arguments = args
        let output = Pipe(); task.standardOutput = output
        guard (try? task.run()) != nil else { return "" }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    private static func descendants(of parent: Int32) -> [Int32] {
        let children = run("/usr/bin/pgrep", ["-P", String(parent)])
            .split(separator: "\n").compactMap { Int32($0) }
        return children + children.flatMap { descendants(of: $0) }
    }
    private static func portIsBusy(_ port: Int) -> Bool {
        let output = run("/usr/sbin/lsof", ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"])
        return output.split(separator: "\n").count > 1
    }
    private static func firstFreePort(startingAt port: Int) -> Int? {
        for candidate in port..<(port + 100) where !portIsBusy(candidate) { return candidate }
        return nil
    }
    private static func defaultCommand(package: PackageFile?) -> String? {
        guard package?.scripts?["dev"] != nil else { return nil }
        return "npm run dev -- --port {port}"
    }
    private static func techSummary(package: PackageFile?, hasPackage: Bool, hasPython: Bool, isFastAPI: Bool) -> String {
        let dependencies = Set(Array((package?.dependencies ?? [:]).keys) + Array((package?.devDependencies ?? [:]).keys))
        if dependencies.contains("next") { return dependencies.contains("typescript") ? "Next.js · TypeScript" : "Next.js" }
        if dependencies.contains("vite") {
            return ["Vite", dependencies.contains("react") ? "React" : nil, dependencies.contains("typescript") ? "TypeScript" : nil]
                .compactMap { $0 }.joined(separator: " · ")
        }
        if isFastAPI { return "Python · FastAPI" }
        if hasPackage && hasPython { return "Node.js · Python" }
        if hasPython { return "Python" }
        if hasPackage { return "Node.js" }
        return "-"
    }
    private static func githubURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let https = trimmed.replacingOccurrences(of: "git@github.com:", with: "https://github.com/").replacingOccurrences(of: ".git", with: "")
        return https.hasPrefix("https://github.com/") ? URL(string: https) : nil
    }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }

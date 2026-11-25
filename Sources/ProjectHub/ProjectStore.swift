import AppKit
import Darwin
import Foundation
import SwiftUI

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [Project] = []
    @Published private(set) var running: [String: RunningService] = [:]
    @Published private(set) var recentOutput: [String: String] = [:]
    @Published private(set) var serviceExits: [String: ServiceExit] = [:]
    @Published var needsWelcome = false
    @Published var search = ""
    @Published var selectedFilter: Filter = .all
    @Published var settings = SavedSettings()
    @Published var alert: AppAlert?
    @Published private(set) var isScanning = false
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
    private var scanGeneration = 0
    private var lastScanRequestedAt: Date?
    private let settingsURL: URL
    private let cacheURL: URL
    private let preferences: UserDefaults

    init(settingsURL: URL? = nil, scanFolders: [String]? = nil, preferences: UserDefaults = .standard) {
        self.settingsURL = settingsURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/ProjectHub/settings.json")
        self.cacheURL = self.settingsURL.deletingLastPathComponent().appending(path: "projects-cache.json")
        self.preferences = preferences
        needsWelcome = !FileManager.default.fileExists(atPath: self.settingsURL.path())
            && !preferences.bool(forKey: "welcomeCompleted")
        loadSettings()
        if let scanFolders { settings.scanFolders = scanFolders }
        loadCachedProjects()
        isScanning = projects.isEmpty && (!settings.scanFolders.isEmpty || !settings.projectFolders.isEmpty)
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
        lastScanRequestedAt = .now
        isScanning = true
        scanGeneration += 1
        let generation = scanGeneration
        let scanFolders = settings.scanFolders
        let projectFolders = settings.projectFolders
        Task.detached(priority: .utility) { [weak self] in
            let result = Self.scanProjects(scanFolders: scanFolders, projectFolders: projectFolders)
            await self?.applyScan(result, generation: generation)
        }
    }

    func refreshProjectsIfStale() {
        guard lastScanRequestedAt.map({ Date().timeIntervalSince($0) >= 60 }) ?? true else { return }
        refreshProjects()
    }

    private func applyScan(_ result: (projects: [Project], inaccessible: [String]), generation: Int) {
        guard scanGeneration == generation else { return }
        isScanning = false
        if result.inaccessible.isEmpty || projects.isEmpty {
            projects = result.projects
        }
        if result.inaccessible.isEmpty { persistCachedProjects() }
        if !result.inaccessible.isEmpty {
            alert = AppAlert(title: "Cannot read project folders", message: "Check access to: \(result.inaccessible.joined(separator: ", "))")
        }
    }

    private struct ProjectCache: Codable {
        let scanFolders: [String]
        let projectFolders: [String]
        let projects: [Project]
    }

    private func loadCachedProjects() {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(ProjectCache.self, from: data),
              cache.scanFolders == settings.scanFolders,
              cache.projectFolders == settings.projectFolders else { return }
        projects = cache.projects
    }

    private func persistCachedProjects() {
        let cache = ProjectCache(scanFolders: settings.scanFolders, projectFolders: settings.projectFolders, projects: projects)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
    }

    nonisolated private static func scanProjects(scanFolders: [String], projectFolders: [String]) -> (projects: [Project], inaccessible: [String]) {
        var folders = projectFolders.map { URL(filePath: $0) }
        var inaccessible: [String] = []
        for root in scanFolders {
            do {
                folders += try FileManager.default.contentsOfDirectory(
                    at: URL(filePath: root), includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
                )
            } catch {
                inaccessible.append(root)
            }
        }
        var seenPaths = Set<String>()
        let projects = folders.filter { seenPaths.insert($0.standardizedFileURL.path()).inserted }.compactMap { folder -> Project? in
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
        return (projects, inaccessible)
    }

    func setting(for project: Project) -> ProjectSettings { settings.projects[project.id] ?? ProjectSettings() }

    func addScanFolder(_ url: URL) {
        let path = url.standardizedFileURL.path()
        guard !settings.scanFolders.contains(path) else { return }
        settings.scanFolders.append(path)
        persistSettings()
        refreshProjects()
    }

    @discardableResult func addProject(_ url: URL) -> Bool {
        let folder = url.standardizedFileURL
        let path = folder.path()
        guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
              [".git", "package.json", "pyproject.toml"].contains(where: {
                  FileManager.default.fileExists(atPath: folder.appending(path: $0).path())
              }) else {
            alert = AppAlert(title: "Not a project folder", message: "Choose a folder containing .git, package.json, or pyproject.toml.")
            return false
        }
        guard !settings.projectFolders.contains(path) else { return true }
        settings.projectFolders.append(path)
        persistSettings()
        refreshProjects()
        return true
    }

    func removeProject(_ path: String) {
        settings.projectFolders.removeAll { $0 == path }
        persistSettings()
        refreshProjects()
    }

    func completeWelcome() {
        needsWelcome = false
        preferences.set(true, forKey: "welcomeCompleted")
        persistSettings()
    }

    func removeScanFolder(_ path: String) {
        settings.scanFolders.removeAll { $0 == path }
        persistSettings()
        refreshProjects()
    }

    func savePreferences() { persistSettings() }

    func command(for project: Project) -> String? { setting(for: project).command ?? project.defaultCommand }

    func port(for project: Project) -> Int { project.defaultPort }

    func status(for project: Project) -> (isRunning: Bool, port: Int?, managed: Bool, ready: Bool) {
        if let service = running[project.id], service.process.isRunning {
            return (true, service.port, true, listeningPorts.contains(service.port))
        }
        return (false, nil, false, false)
    }

    func serverHealth(for project: Project) -> ServerHealth {
        if let exit = serviceExits[project.id] {
            return .failed("\(exit.label). Open Logs to see what happened.")
        }
        let current = status(for: project)
        if current.isRunning, let port = current.port {
            if current.ready { return .running(port) }
            if let service = running[project.id], Date().timeIntervalSince(service.startedAt) >= 10 {
                return .warning("The process is running, but no server is listening on port \(port). Check Logs.")
            }
            return .starting(port)
        }
        guard command(for: project) != nil else { return .unavailable }
        return .stopped
    }

    func save(project: Project, command: String, favorite: Bool, hostingProvider: HostingProvider, hostedURL: String) {
        settings.projects[project.id] = ProjectSettings(
            command: command.nilIfEmpty,
            favorite: favorite,
            hostingProvider: hostingProvider,
            hostedURL: hostingProvider == .none ? nil : hostedURL.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
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
        let projectName = project.name
        let runID = UUID().uuidString
        serviceExits.removeValue(forKey: id)
        recentOutput[id] = ""
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                guard var service = self?.running[id], service.id == runID else { return }
                service.output = String((service.output + text).suffix(12_000))
                self?.running[id] = service
                self?.recentOutput[id] = service.output
            }
        }
        process.terminationHandler = { [weak self] finished in
            output.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in
                guard let self, self.running[id]?.id == runID else { return }
                self.running.removeValue(forKey: id)
                let exit = ServiceExit(code: finished.terminationStatus, reason: finished.terminationReason, command: command, port: chosenPort)
                self.serviceExits[id] = exit
                self.alert = AppAlert(title: "\(projectName) server stopped", message: "\(exit.label). Open Logs for details.")
            }
        }
        do {
            try process.run()
            running[project.id] = RunningService(id: runID, projectID: project.id, port: chosenPort, command: command, process: process, startedAt: .now)
        } catch {
            alert = AppAlert(title: "Could not start \(project.name)", message: error.localizedDescription)
        }
    }

    func stop(_ project: Project) {
        stopService(project.id)
    }

    func stopAll() {
        for id in Array(running.keys) { stopService(id) }
    }

    private func stopService(_ id: String) {
        guard let service = running.removeValue(forKey: id) else { return }
        for child in Self.descendants(of: service.process.processIdentifier).reversed() {
            kill(child, SIGTERM)
        }
        if service.process.isRunning { service.process.terminate() }
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
        guard current.ready, let port = current.port,
              let url = URL(string: "http://localhost:\(port)") else { return }
        openExternalURL(url)
    }
    func openRepository(_ project: Project) {
        guard let url = project.repositoryURL else { return }
        openExternalURL(url)
    }

    func openHostedSite(_ project: Project) {
        guard let address = setting(for: project).hostedURL,
              let url = URL(string: address), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else { return }
        openExternalURL(url)
    }

    private func openExternalURL(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(url, configuration: configuration) { [weak self] _, error in
            guard let error else { return }
            Task { @MainActor in
                self?.alert = AppAlert(title: "Could not open link", message: error.localizedDescription)
            }
        }
    }

    private func refreshPortSnapshot() {
        let managedPorts = Set(running.values.map(\.port))
        guard !managedPorts.isEmpty else {
            listeningPorts = []
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let ports = Set(managedPorts.filter { Self.portIsBusy($0) })
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

    private struct PackageFile: Decodable { let description: String?; let scripts: [String: String]?; let dependencies: [String: String]?; let devDependencies: [String: String]? }
    nonisolated private static func readPackage(at url: URL) -> PackageFile? {
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
    nonisolated private static func portIsBusy(_ port: Int) -> Bool {
        let output = run("/usr/sbin/lsof", ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"])
        return output.split(separator: "\n").count > 1
    }
    private static func firstFreePort(startingAt port: Int) -> Int? {
        for candidate in port..<(port + 100) where !portIsBusy(candidate) { return candidate }
        return nil
    }
    nonisolated private static func defaultCommand(package: PackageFile?) -> String? {
        guard package?.scripts?["dev"] != nil else { return nil }
        return "npm run dev -- --port {port}"
    }
    nonisolated private static func techSummary(package: PackageFile?, hasPackage: Bool, hasPython: Bool, isFastAPI: Bool) -> String {
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
    nonisolated private static func githubURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let https = trimmed.replacingOccurrences(of: "git@github.com:", with: "https://github.com/").replacingOccurrences(of: ".git", with: "")
        return https.hasPrefix("https://github.com/") ? URL(string: https) : nil
    }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }

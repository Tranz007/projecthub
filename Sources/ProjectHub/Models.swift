import Foundation
import SwiftUI

struct Project: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let path: URL
    let kind: ProjectKind
    let techSummary: String
    let repositoryURL: URL?
    let branch: String?
    let changedFiles: Int?
    let description: String?
    let defaultCommand: String?
    let defaultPort: Int

    enum ProjectKind: String, Codable, CaseIterable, Sendable {
        case node = "Node"
        case python = "Python"
        case mixed = "Mixed"
        case git = "Git"

        var symbol: String {
            switch self {
            case .node: "cube.fill"
            case .python: "chevron.left.forwardslash.chevron.right"
            case .mixed: "square.stack.3d.up.fill"
            case .git: "folder.fill"
            }
        }
    }
}

extension Project {
    var hoverDetail: String {
        if let description, !description.isEmpty { return description }
        return path.path(percentEncoded: false)
    }

    var technologies: [String] {
        techSummary == "-" ? [] : techSummary.components(separatedBy: " · ")
    }
    var displaySymbol: String {
        kind.symbol
    }

    var displayColor: Color {
        Color(red: 0.52, green: 0.64, blue: 1)
    }
}

struct ProjectSettings: Codable, Hashable {
    var command: String?
    var favorite = false
    var hostingProvider: HostingProvider = .none
    var hostedURL: String?

    init(command: String? = nil, favorite: Bool = false, hostingProvider: HostingProvider = .none, hostedURL: String? = nil) {
        self.command = command
        self.favorite = favorite
        self.hostingProvider = hostingProvider
        self.hostedURL = hostedURL
    }

    private enum CodingKeys: String, CodingKey { case command, favorite, hostingProvider, hostedURL }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        command = try values.decodeIfPresent(String.self, forKey: .command)
        favorite = try values.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        hostingProvider = try values.decodeIfPresent(HostingProvider.self, forKey: .hostingProvider) ?? .none
        hostedURL = try values.decodeIfPresent(String.self, forKey: .hostedURL)
    }
}

enum HostingProvider: String, Codable, CaseIterable, Identifiable {
    case none = "Not hosted"
    case vercel = "Vercel"
    case netlify = "Netlify"
    case cloudflare = "Cloudflare Pages"
    case firebase = "Firebase Hosting"
    case other = "Other host"

    var id: String { rawValue }

    var iconName: String? {
        switch self {
        case .none, .other: nil
        case .vercel: "vercel"
        case .netlify: "netlify"
        case .cloudflare: "cloudflare"
        case .firebase: "firebase"
        }
    }
}

struct SavedSettings: Codable {
    var projects: [String: ProjectSettings] = [:]
    var scanFolders: [String] = [FileManager.default.homeDirectoryForCurrentUser.appending(path: "Desktop").path()]
    var projectFolders: [String] = []
    var preferredEditor = "Cursor"
    var customEditorPath = ""
    var aiTool = "Codex"
    var customAICommand = ""

    init() {}

    private enum CodingKeys: String, CodingKey { case projects, scanFolders, projectFolders, preferredEditor, customEditorPath, aiTool, customAICommand }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        projects = try values.decodeIfPresent([String: ProjectSettings].self, forKey: .projects) ?? [:]
        scanFolders = try values.decodeIfPresent([String].self, forKey: .scanFolders)
            ?? [FileManager.default.homeDirectoryForCurrentUser.appending(path: "Desktop").path()]
        projectFolders = try values.decodeIfPresent([String].self, forKey: .projectFolders) ?? []
        preferredEditor = try values.decodeIfPresent(String.self, forKey: .preferredEditor) ?? "Cursor"
        customEditorPath = try values.decodeIfPresent(String.self, forKey: .customEditorPath) ?? ""
        aiTool = try values.decodeIfPresent(String.self, forKey: .aiTool) ?? "Codex"
        customAICommand = try values.decodeIfPresent(String.self, forKey: .customAICommand) ?? ""
    }
}

struct RunningService: Identifiable {
    let id: String
    let projectID: String
    let port: Int
    let command: String
    let process: Process
    var startedAt: Date
    var output = ""
}

struct ServiceExit {
    let code: Int32
    let reason: Process.TerminationReason
    let command: String
    let port: Int

    var label: String {
        reason == .uncaughtSignal ? "Stopped by signal \(code)" : "Exited (code \(code))"
    }
}

enum ServerHealth {
    case unavailable
    case stopped
    case starting(Int)
    case running(Int)
    case warning(String)
    case failed(String)

    var label: String {
        switch self {
        case .unavailable: "-"
        case .stopped: "Stopped"
        case .starting: "Starting"
        case .running: "Running"
        case .warning: "Issue"
        case .failed: "Exited"
        }
    }

    var detail: String {
        switch self {
        case .unavailable: "No web server configured."
        case .stopped: "Web server stopped. Use Start to launch it."
        case .starting(let port): "Starting the web server on port \(port)…"
        case .running(let port): "Web server running at localhost:\(port). Select the icon to open it in your browser."
        case .warning(let message), .failed(let message): message
        }
    }
}

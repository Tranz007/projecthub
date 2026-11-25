import Foundation
import SwiftUI

struct Project: Identifiable, Hashable {
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

    enum ProjectKind: String, Codable, CaseIterable {
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
    var preferredPort: Int?
    var favorite = false
}

struct SavedSettings: Codable {
    var projects: [String: ProjectSettings] = [:]
    var scanFolders: [String] = [FileManager.default.homeDirectoryForCurrentUser.appending(path: "Desktop").path()]
    var preferredEditor = "Cursor"
    var customEditorPath = ""
    var aiTool = "Codex"
    var customAICommand = ""

    init() {}

    private enum CodingKeys: String, CodingKey { case projects, scanFolders, preferredEditor, customEditorPath, aiTool, customAICommand }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        projects = try values.decodeIfPresent([String: ProjectSettings].self, forKey: .projects) ?? [:]
        scanFolders = try values.decodeIfPresent([String].self, forKey: .scanFolders)
            ?? [FileManager.default.homeDirectoryForCurrentUser.appending(path: "Desktop").path()]
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

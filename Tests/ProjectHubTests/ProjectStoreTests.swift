import Foundation
import XCTest
@testable import ProjectHub

@MainActor
final class ProjectStoreTests: XCTestCase {
    func testDirectProjectAndUnexpectedServerExit() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ProjectHubTests-\(UUID().uuidString)")
        let suiteName = "ProjectHubTests-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let projectFolder = root.appending(path: "nested/example")
        try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: projectFolder.appending(path: "package.json"))
        defer { try? FileManager.default.removeItem(at: root) }
        defer { preferences.removePersistentDomain(forName: suiteName) }

        let settingsURL = root.appending(path: "settings.json")
        let store = ProjectStore(settingsURL: settingsURL, scanFolders: [], preferences: preferences)
        XCTAssertTrue(store.needsWelcome)
        store.completeWelcome()
        XCTAssertFalse(store.needsWelcome)
        try FileManager.default.removeItem(at: settingsURL)
        XCTAssertFalse(ProjectStore(settingsURL: settingsURL, scanFolders: [], preferences: preferences).needsWelcome)
        XCTAssertTrue(store.addProject(projectFolder))
        let project = try XCTUnwrap(store.projects.first)
        XCTAssertEqual(project.path.standardizedFileURL, projectFolder.standardizedFileURL)
        let restored = ProjectStore(settingsURL: settingsURL, scanFolders: [], preferences: preferences)
        XCTAssertEqual(restored.projects.first?.id, project.id)
        XCTAssertEqual(store.serverHealth(for: project).label, "-")
        store.save(project: project, command: "echo fixture failure; exit 7", port: 51000, favorite: false)
        XCTAssertEqual(store.serverHealth(for: project).label, "Stopped")
        store.start(project)

        for _ in 0..<100 where store.serviceExits[project.id] == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(store.serviceExits[project.id]?.code, 7)
        XCTAssertEqual(store.serverHealth(for: project).label, "Exited")
        XCTAssertEqual(store.alert?.title, "example server stopped")
        XCTAssertTrue(store.recentOutput[project.id]?.contains("fixture failure") == true)
        XCTAssertNil(store.running[project.id])

        store.save(project: project, command: "sleep 30", port: 51000, favorite: false)
        store.start(project)
        XCTAssertNotNil(store.running[project.id])
        store.stopAll()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(store.running[project.id])
        XCTAssertNil(store.serviceExits[project.id])
        XCTAssertEqual(store.serverHealth(for: project).label, "Stopped")
    }
}

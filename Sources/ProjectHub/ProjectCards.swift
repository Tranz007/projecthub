import SwiftUI

struct ProjectCards: View {
    let projects: [Project]
    let width: CGFloat
    let columns: String

    private var columnCount: Int {
        let fitting = max(1, Int(width / 300))
        return columns == "Auto" ? min(4, fitting) : min(Int(columns) ?? fitting, fitting)
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: columnCount), spacing: 16) {
            ForEach(projects) { project in ProjectCard(project: project) }
        }
    }
}

private struct ProjectCard: View {
    @EnvironmentObject private var store: ProjectStore
    let project: Project
    @State private var showingConfigure = false
    @State private var showingLogs = false

    var body: some View {
        let status = store.status(for: project)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: project.displaySymbol)
                    .foregroundStyle(project.displayColor)
                    .frame(width: 34, height: 34)
                    .background(project.displayColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    ProjectTitle(project: project, size: 19)
                    TechStack(technologies: project.technologies)
                }
                Spacer(minLength: 0)
                if project.changedFiles != nil { RepoBadge(project: project) }
                Button { store.toggleFavorite(project) } label: {
                    Image(systemName: store.setting(for: project).favorite ? "star.fill" : "star")
                }.buttonStyle(.plain).accessibilityLabel("Toggle favorite")
            }
            Spacer(minLength: 0)
            HStack {
                if let exit = store.serviceExits[project.id] {
                    Circle().fill(.red).frame(width: 7, height: 7)
                    Text(exit.label).foregroundStyle(.red)
                } else if store.command(for: project) == nil && !status.isRunning {
                    Text("-")
                } else {
                    Circle().fill(status.ready ? .green : status.isRunning ? .orange : .gray).frame(width: 7, height: 7)
                    Text(status.ready ? "Running" : status.isRunning ? "Starting" : status.portBusy ? "Port in use" : "Stopped")
                }
                Spacer()
                if status.ready {
                    Button("Open site") { store.openURL(for: project) }.buttonStyle(.link)
                }
                if status.isRunning || store.serviceExits[project.id] != nil || store.recentOutput[project.id]?.isEmpty == false {
                    Button("Logs") { showingLogs = true }.buttonStyle(.link)
                }
            }.font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Open with \(store.aiToolLabel)") { store.openInAI(project) }
                    .buttonStyle(.bordered)
                Spacer()
                if status.managed {
                    Button("Stop") { store.stop(project) }.buttonStyle(PrimaryButton(active: true))
                } else if store.command(for: project) != nil {
                    Button("Start") { store.start(project) }.buttonStyle(PrimaryButton(active: false))
                } else {
                    Button("Configure") { showingConfigure = true }.buttonStyle(.bordered)
                }
                Menu {
                    Button("Open in \(store.settings.preferredEditor)") { store.openInEditor(project) }
                    Button("Open in Finder") { store.openInFinder(project) }
                    if project.repositoryURL != nil { Button("Open repository") { store.openRepository(project) } }
                    Button("Configure…") { showingConfigure = true }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("More actions for \(project.name)")
            }
        }
        .frame(height: 102, alignment: .topLeading)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.09)))
        .popover(isPresented: $showingConfigure) {
            ConfigureProject(project: project, isPresented: $showingConfigure)
        }
        .sheet(isPresented: $showingLogs) { ServiceLogsView(project: project) }
    }
}

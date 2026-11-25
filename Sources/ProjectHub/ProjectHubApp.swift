import AppKit
import SwiftUI

@main
struct ProjectHubApp: App {
    @StateObject private var store = ProjectStore()
    @NSApplicationDelegateAdaptor(ProjectHubAppDelegate.self) private var appDelegate

    init() {
        let defaults = UserDefaults.standard
        let layoutVersion = 1
        if defaults.integer(forKey: "windowLayoutVersion") < layoutVersion {
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("NSWindow Frame SwiftUI.") {
                defaults.removeObject(forKey: key)
            }
            defaults.set(layoutVersion, forKey: "windowLayoutVersion")
        }
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store)
                .frame(minWidth: 1100, minHeight: 700)
                .preferredColorScheme(.dark)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    store.refreshProjects()
                }
                .alert(item: $store.alert) { alert in
                    if let action = alert.action {
                        Alert(
                            title: Text(alert.title),
                            message: Text(alert.message),
                            primaryButton: .default(Text(alert.actionLabel ?? "Continue"), action: action),
                            secondaryButton: .cancel()
                        )
                    } else {
                        Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
                    }
                }
        }
        .defaultSize(width: 1440, height: 900)
        .defaultPosition(.center)
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView().environmentObject(store)
        }
    }
}

private final class ProjectHubAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ProjectHubWindowLayout.apply(after: 0.2)
    }
}

private enum ProjectHubWindowLayout {
    static let minimumSize = NSSize(width: 1100, height: 700)
    static let preferredSize = NSSize(width: 1440, height: 900)

    static func apply(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard let window = NSApplication.shared.windows.first else { return }
            window.minSize = minimumSize
            guard window.frame.width < minimumSize.width || window.frame.height < minimumSize.height else { return }
            let screenFrame = (window.screen ?? NSScreen.main)?.visibleFrame ?? .zero
            let origin = NSPoint(
                x: screenFrame.midX - preferredSize.width / 2,
                y: screenFrame.midY - preferredSize.height / 2
            )
            window.setFrame(NSRect(origin: origin, size: preferredSize), display: true)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: ProjectStore
    @AppStorage("projectLayout") private var projectLayout = "List"
    @AppStorage("cardColumns") private var cardColumns = "Auto"

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
            Divider().overlay(Color.white.opacity(0.08))
            VStack(spacing: 0) {
                Header()
                Divider().overlay(Color.white.opacity(0.08))
                GeometryReader { geometry in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(store.selectedFilter.rawValue).font(.system(size: 32, weight: .bold))
                                Text("\(store.visibleProjects.count) projects  •  \(store.projects.filter { store.status(for: $0).isRunning }.count) running")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Picker("Filter", selection: $store.selectedFilter) {
                                ForEach(ProjectStore.Filter.allCases) { Text($0.rawValue).tag($0) }
                            }.pickerStyle(.segmented).frame(width: 310)
                        }
                        HStack {
                            Picker("View", selection: $projectLayout) {
                                Text("List").tag("List")
                                Text("Cards").tag("Cards")
                            }.pickerStyle(.segmented).frame(width: 175)
                            if projectLayout == "Cards" {
                                Picker("Columns", selection: $cardColumns) {
                                    ForEach(["Auto", "2", "3", "4"], id: \.self) { Text($0).tag($0) }
                                }.frame(width: 150)
                            }
                            Spacer()
                        }
                        if projectLayout == "Cards" {
                            ProjectCards(projects: store.visibleProjects, width: geometry.size.width - 60, columns: cardColumns)
                        } else {
                            ScrollView(.horizontal) {
                                ProjectTable(projects: store.visibleProjects)
                                    .frame(minWidth: max(1050, geometry.size.width - 60))
                            }
                        }
                        }
                        .padding(30)
                    }
                }
            }
        }
        .background(Color(red: 0.055, green: 0.068, blue: 0.078))
    }
}

private struct Sidebar: View {
    @EnvironmentObject private var store: ProjectStore
    @AppStorage("sidebarCollapsed") private var collapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().interpolation(.high).frame(width: 31, height: 31).clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.leading, collapsed ? 3 : 6)
                if !collapsed {
                    Text("Project Hub").font(.system(size: 18, weight: .bold)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { collapsed.toggle() } label: {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.left")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(collapsed ? "Expand sidebar" : "Collapse sidebar")
            }.padding(.top, 25)
            VStack(spacing: 5) {
                NavRow(filter: .all, icon: "rectangle.stack", collapsed: collapsed)
                NavRow(filter: .favorites, icon: "heart", collapsed: collapsed)
                NavRow(filter: .running, icon: "play.circle", collapsed: collapsed)
            }
            Divider().overlay(Color.white.opacity(0.1))
            VStack(alignment: .leading, spacing: 14) {
                Button { store.refreshProjects() } label: {
                    if collapsed { Image(systemName: "arrow.clockwise") }
                    else { Label("Refresh projects", systemImage: "arrow.clockwise") }
                }
                .buttonStyle(.plain).help("Refresh projects")
                SettingsLink {
                    if collapsed { Image(systemName: "gearshape") }
                    else { Label("Settings", systemImage: "gearshape") }
                }
                .buttonStyle(.plain).help("Settings")
            }
            .foregroundStyle(.secondary)
            .padding(.leading, collapsed ? 12 : 15)
            if !collapsed {
                Text("A calmer desk builds a sharper you.").font(.caption).italic().foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, collapsed ? 10 : 18)
        .frame(width: collapsed ? 96 : 225)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.20))
    }
}

private struct NavRow: View {
    @EnvironmentObject private var store: ProjectStore
    let filter: ProjectStore.Filter; let icon: String; let collapsed: Bool
    var count: Int { filter == .running ? store.projects.filter { store.status(for: $0).isRunning }.count : filter == .favorites ? store.projects.filter { store.setting(for: $0).favorite }.count : store.projects.count }
    var body: some View {
        Button { store.selectedFilter = filter } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).frame(width: 20)
                if !collapsed { Text(filter.rawValue); Spacer(minLength: 0) }
                Text("\(count)").font(.caption).padding(.horizontal, collapsed ? 5 : 7).padding(.vertical, 3)
                    .background(.white.opacity(0.09), in: Capsule())
            }
                .padding(.horizontal, collapsed ? 8 : 12).padding(.vertical, 9).background(store.selectedFilter == filter ? Color.white.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).help(filter.rawValue)
    }
}

private struct Header: View {
    @EnvironmentObject private var store: ProjectStore
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search projects, technologies, or tags…", text: $store.search).textFieldStyle(.plain)
            Text("⌘ K").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 7).padding(.vertical, 4).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
        }.padding(.horizontal, 16).padding(.vertical, 13).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9)).padding(18)
    }
}

private enum TableColumns {
    static let tech: CGFloat = 120
    static let repository: CGFloat = 90
    static let webServer: CGFloat = 150
    static let actions: CGFloat = 360
}

private struct ProjectTable: View {
    @EnvironmentObject private var store: ProjectStore
    let projects: [Project]
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text("PROJECT").frame(maxWidth: .infinity, alignment: .leading)
                Text("TECH").frame(width: TableColumns.tech, alignment: .leading)
                Text("GIT / REPO").frame(width: TableColumns.repository, alignment: .leading)
                Text("WebServer").frame(width: TableColumns.webServer, alignment: .leading)
                Text("ACTIONS").frame(width: TableColumns.actions, alignment: .leading)
            }
                .font(.caption.weight(.medium)).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.vertical, 12)
            ForEach(projects) { project in ProjectRow(project: project); Divider().overlay(Color.white.opacity(0.08)).padding(.horizontal, 18) }
        }
        .background(.black.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.09)))
    }
}

private struct ProjectRow: View {
    @EnvironmentObject private var store: ProjectStore
    let project: Project
    @State private var showingConfigure = false
    @State private var showingLogs = false
    var body: some View {
        let status = store.status(for: project)
        HStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: project.displaySymbol)
                    .foregroundStyle(project.displayColor).font(.title3).frame(width: 30, height: 30)
                    .background(project.displayColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    ProjectTitle(project: project, size: 17)
                    Button { store.toggleFavorite(project) } label: {
                        Image(systemName: store.setting(for: project).favorite ? "star.fill" : "star")
                            .foregroundStyle(store.setting(for: project).favorite ? .yellow : .secondary)
                    }.buttonStyle(.plain)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            TechStack(technologies: project.technologies).frame(width: TableColumns.tech, alignment: .leading)
            RepoBadge(project: project).frame(width: TableColumns.repository, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                if store.command(for: project) == nil && !status.isRunning {
                    Text("-").foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 7) { Circle().fill(status.ready ? .green : status.isRunning ? .orange : .gray).frame(width: 8, height: 8); Text(status.ready ? "Running" : status.isRunning ? "Starting" : status.portBusy ? "Port in use" : "Stopped") }
                }
                if status.isRunning || store.recentOutput[project.id]?.isEmpty == false {
                    HStack(spacing: 10) {
                        if status.ready, let port = status.port {
                            Button("localhost:\(port)") { store.openURL(for: project) }.buttonStyle(.link)
                        }
                        Button("Logs") { showingLogs = true }.buttonStyle(.link)
                    }.font(.caption)
                }
            }.frame(width: TableColumns.webServer, alignment: .leading)
            HStack(spacing: 8) {
                Button { store.openInAI(project) } label: { Label("Open with \(store.aiToolLabel)", systemImage: "terminal") }.buttonStyle(SecondaryButton())
                Button { store.openInEditor(project) } label: { Image(systemName: "arrow.up.forward.app") }.buttonStyle(SecondaryButton()).help("Open in \(store.settings.preferredEditor)")
                Button { showingConfigure = true } label: { Image(systemName: "gearshape") }.buttonStyle(SecondaryButton())
                if status.managed {
                    Button { store.stop(project) } label: { Label("Stop", systemImage: "stop.fill") }
                        .buttonStyle(PrimaryButton(active: true))
                } else if store.command(for: project) != nil {
                    Button { store.start(project) } label: { Label("Start", systemImage: "play.fill") }
                        .buttonStyle(PrimaryButton(active: false))
                } else {
                    Button { store.openInFinder(project) } label: { Label("Open Folder", systemImage: "folder") }
                        .buttonStyle(SecondaryButton())
                }
            }
            .frame(width: TableColumns.actions, alignment: .leading)
            .popover(isPresented: $showingConfigure) { ConfigureProject(project: project, isPresented: $showingConfigure) }
        }
        .padding(.horizontal, 18).padding(.vertical, 15)
        .sheet(isPresented: $showingLogs) { ServiceLogsView(project: project) }
    }
}

struct ConfigureProject: View {
    @EnvironmentObject private var store: ProjectStore
    let project: Project
    @Binding var isPresented: Bool
    @State private var command: String = ""
    @State private var port: Int = 3000
    @State private var favorite = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configure \(project.name)").font(.headline)
            Text("Use {port} where the selected free port belongs. Project Hub will choose the next available port if needed.").font(.caption).foregroundStyle(.secondary)
            TextField("Command, e.g. npm run dev -- --port {port}", text: $command)
            Stepper("Preferred port: \(port)", value: $port, in: 1024...65500)
            Toggle("Favorite", isOn: $favorite)
            HStack { Spacer(); Button("Cancel") { isPresented = false }; Button("Save") { store.save(project: project, command: command, port: port, favorite: favorite); isPresented = false }.buttonStyle(.borderedProminent) }
        }
        .padding(20).frame(width: 430)
        .onAppear { let item = store.setting(for: project); command = item.command ?? project.defaultCommand ?? ""; port = item.preferredPort ?? project.defaultPort; favorite = item.favorite }
    }
}

private struct SecondaryButton: ButtonStyle { func makeBody(configuration: Configuration) -> some View { configuration.label.font(.caption.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 9).background(.white.opacity(configuration.isPressed ? 0.15 : 0.07), in: RoundedRectangle(cornerRadius: 7)).overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.12))) } }
struct PrimaryButton: ButtonStyle { let active: Bool; func makeBody(configuration: Configuration) -> some View { configuration.label.font(.caption.weight(.bold)).padding(.horizontal, 12).padding(.vertical, 9).foregroundStyle(active ? Color.white : Color.black).background(active ? Color.red.opacity(configuration.isPressed ? 0.75 : 0.9) : Color(red: 0.60, green: 0.94, blue: 0.37).opacity(configuration.isPressed ? 0.75 : 0.95), in: RoundedRectangle(cornerRadius: 7)) } }

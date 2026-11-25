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
                .onAppear {
                    appDelegate.store = store
                    DispatchQueue.main.async { store.refreshProjectsIfStale() }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    store.refreshProjectsIfStale()
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
                .sheet(isPresented: $store.needsWelcome) {
                    ProjectSourceView(welcome: true)
                        .environmentObject(store)
                        .interactiveDismissDisabled()
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
    weak var store: ProjectStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProjectHubWindowLayout.apply(after: 0.2)
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.stopAll()
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
    @AppStorage("sidebarCollapsed") private var sidebarCollapsed = false
    @AppStorage("projectLayout") private var projectLayout = "List"
    @AppStorage("cardColumns") private var cardColumns = "Auto"

    var body: some View {
        GeometryReader { window in
        HStack(spacing: 0) {
            Sidebar()
                .zIndex(1)
            Divider().overlay(Color.white.opacity(0.08))
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(store.selectedFilter.rawValue).font(.system(size: 32, weight: .bold))
                                Text("\(store.visibleProjects.count) projects  •  \(store.projects.filter { store.status(for: $0).isRunning }.count) running")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            SearchLine()
                                .frame(width: 320)
                                .padding(.top, 8)
                        }
                        HStack {
                            Text("View").foregroundStyle(.secondary)
                            ViewModeButton(mode: "List", symbol: "list.bullet", selection: $projectLayout)
                            ViewModeButton(mode: "Cards", symbol: "square.grid.2x2", selection: $projectLayout)
                            if projectLayout == "Cards" {
                                Picker("Columns", selection: $cardColumns) {
                                    ForEach(["Auto", "2", "3", "4"], id: \.self) { Text($0).tag($0) }
                                }.frame(width: 150)
                            }
                            Spacer()
                            Menu {
                                Button("Add Project…") { chooseProject() }
                                Button("Choose Folder…") { chooseFolder() }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle.fill").font(.system(size: 20))
                                    Text("Add")
                                }
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                        if store.projects.isEmpty && store.isScanning {
                            ProgressView("Scanning project folders…")
                                .padding(.vertical, 30)
                        } else if store.projects.isEmpty {
                            ProjectSourceView(welcome: false)
                                .environmentObject(store)
                        } else if store.visibleProjects.isEmpty {
                            Text("No projects match your search or filter.")
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 30)
                        } else if projectLayout == "Cards" {
                            ProjectCards(projects: store.visibleProjects, width: geometry.size.width - 60, columns: cardColumns)
                        } else {
                            ScrollView(.horizontal) {
                                ProjectTable(projects: store.visibleProjects)
                                    .frame(minWidth: max(1050, geometry.size.width - 60))
                            }
                            .id(sidebarCollapsed)
                        }
                        }
                        .padding(30)
                    }
                }
            }
            .frame(width: window.size.width - (sidebarCollapsed ? 76 : 225) - 1)
            .id(sidebarCollapsed)
        }
        }
        .background(Color(red: 0.055, green: 0.068, blue: 0.078))
    }

    private func chooseFolder() {
        for folder in ProjectPicker.chooseFolders(multiple: true, prompt: "Choose") {
            store.addScanFolder(folder)
        }
    }

    private func chooseProject() {
        guard let folder = ProjectPicker.chooseFolders(multiple: false, prompt: "Add Project").first else { return }
        store.addProject(folder)
    }
}

private struct Sidebar: View {
    @EnvironmentObject private var store: ProjectStore
    @AppStorage("sidebarCollapsed") private var collapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().interpolation(.high).frame(width: 35, height: 35).clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.leading, collapsed ? 0 : 4)
                    .accessibilityLabel("Project Hub")
                    .modifier(SidebarTooltip(title: "Project Hub", enabled: collapsed))
                if !collapsed {
                    Text("Project Hub").font(.system(size: 18, weight: .bold)).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
            .padding(.top, 25)
            VStack(spacing: 5) {
                NavRow(filter: .all, icon: "rectangle.stack", collapsed: collapsed)
                NavRow(filter: .favorites, icon: "heart", collapsed: collapsed)
                NavRow(filter: .running, icon: "play.circle", collapsed: collapsed)
            }
            Divider().overlay(Color.white.opacity(0.1))
            VStack(alignment: collapsed ? .center : .leading, spacing: 14) {
                Button { store.refreshProjects() } label: {
                    SidebarActionLabel(symbol: "arrow.clockwise", title: "Refresh projects", collapsed: collapsed)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh projects")
                .modifier(SidebarTooltip(title: "Refresh projects", enabled: collapsed))
                SettingsLink {
                    SidebarActionLabel(symbol: "gearshape", title: "Settings", collapsed: collapsed)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
                .modifier(SidebarTooltip(title: "Settings", enabled: collapsed))
            }
            .foregroundStyle(.secondary)
            .padding(.leading, collapsed ? 0 : 12)
            .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
            if !collapsed {
                Text("A calmer desk builds a sharper you.").font(.caption).italic().foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            Button { collapsed.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 20, height: 20)
                    if !collapsed { Text("Minimize sidebar") }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(collapsed ? "Maximize sidebar" : "Minimize sidebar")
            .modifier(SidebarTooltip(title: "Maximize sidebar", enabled: collapsed))
            .padding(.leading, collapsed ? 0 : 12)
            .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
            .padding(.bottom, 18)
        }
        .padding(.horizontal, collapsed ? 10 : 18)
        .frame(width: collapsed ? 76 : 225)
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
                Image(systemName: icon).font(.system(size: 17, weight: .medium)).frame(width: 20)
                if !collapsed {
                    Text(filter.rawValue)
                    Spacer(minLength: 0)
                    Text("\(count)").font(.caption).padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.white.opacity(0.09), in: Capsule())
                }
            }
                .padding(.horizontal, collapsed ? 8 : 12).padding(.vertical, 9).background(store.selectedFilter == filter ? Color.white.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(filter.rawValue), \(count)")
        .modifier(SidebarTooltip(title: "\(filter.rawValue) · \(count)", enabled: collapsed))
    }
}

private struct SidebarActionLabel: View {
    let symbol: String
    let title: String
    let collapsed: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 20)
            if !collapsed { Text(title) }
        }
    }
}

private struct SidebarTooltip: ViewModifier {
    let title: String
    let enabled: Bool
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering = $0 }
            .overlay(alignment: .leading) {
                if enabled && hovering {
                    Text(title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(red: 0.16, green: 0.18, blue: 0.20), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.18)))
                        .fixedSize()
                        .offset(x: 48)
                        .allowsHitTesting(false)
                }
            }
    }
}

private struct SearchLine: View {
    @EnvironmentObject private var store: ProjectStore

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search projects…", text: $store.search)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search projects, technologies, or tags")
            }
            Rectangle().fill(.white.opacity(0.25)).frame(height: 1)
        }
    }
}

private struct ViewModeButton: View {
    let mode: String
    let symbol: String
    @Binding var selection: String
    @State private var hovering = false

    var body: some View {
        Button { selection = mode } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 32, height: 28)
                .background(selection == mode ? Color.white.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode) view")
        .onHover { hovering = $0 }
        .overlay(alignment: .top) {
            if hovering {
                Text("\(mode) view")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.16, green: 0.18, blue: 0.20), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.18)))
                    .fixedSize()
                    .offset(y: 33)
                    .allowsHitTesting(false)
            }
        }
    }
}

private enum TableColumns {
    static let tech: CGFloat = 120
    static let repository: CGFloat = 72
    static let webServer: CGFloat = 80
    static let hosted: CGFloat = 76
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
                Text("GIT / REPO").frame(width: TableColumns.repository)
                Text("WebServer").frame(width: TableColumns.webServer)
                Text("EXTERNAL").frame(width: TableColumns.hosted)
                Text("ACTIONS").frame(width: TableColumns.actions, alignment: .leading)
            }
                .font(.caption.weight(.medium)).foregroundStyle(.secondary).padding(.vertical, 12)
            ForEach(projects) { project in ProjectRow(project: project); Divider().overlay(Color.white.opacity(0.08)) }
        }
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
            RepoBadge(project: project).frame(width: TableColumns.repository)
            ServerIndicator(project: project)
                .frame(width: TableColumns.webServer)
            HostedBadge(project: project).frame(width: TableColumns.hosted)
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
                if status.isRunning || store.serviceExits[project.id] != nil || store.recentOutput[project.id]?.isEmpty == false {
                    Menu {
                        if status.ready {
                            Button("Open site") { store.openURL(for: project) }
                        }
                        Button("View logs") { showingLogs = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("Server actions for \(project.name)")
                }
            }
            .frame(width: TableColumns.actions, alignment: .leading)
            .popover(isPresented: $showingConfigure) { ConfigureProject(project: project, isPresented: $showingConfigure) }
        }
        .padding(.vertical, 15)
        .sheet(isPresented: $showingLogs) { ServiceLogsView(project: project) }
    }
}

struct ConfigureProject: View {
    @EnvironmentObject private var store: ProjectStore
    let project: Project
    @Binding var isPresented: Bool
    @State private var command: String = ""
    @State private var favorite = false
    @State private var hostingProvider: HostingProvider = .none
    @State private var hostedURL = ""

    private var validHostedURL: Bool {
        guard hostingProvider != .none else { return true }
        guard let url = URL(string: hostedURL.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configure \(project.name)").font(.headline)
            Text("Project Hub chooses an available local port when starting the server. Use {port} in custom commands that accept a port.").font(.caption).foregroundStyle(.secondary)
            TextField("Command, e.g. npm run dev -- --port {port}", text: $command)
            Picker("External hosting", selection: $hostingProvider) {
                ForEach(HostingProvider.allCases) { provider in Text(provider.rawValue).tag(provider) }
            }
            if hostingProvider != .none {
                TextField("Site URL, e.g. https://example.vercel.app", text: $hostedURL)
                    .textFieldStyle(.roundedBorder)
                if !hostedURL.isEmpty && !validHostedURL {
                    Text("Enter a full http or https URL.").font(.caption).foregroundStyle(.red)
                }
            }
            Toggle("Favorite", isOn: $favorite)
            HStack { Spacer(); Button("Cancel") { isPresented = false }; Button("Save") { store.save(project: project, command: command, favorite: favorite, hostingProvider: hostingProvider, hostedURL: hostedURL); isPresented = false }.buttonStyle(.borderedProminent).disabled(!validHostedURL) }
        }
        .padding(20).frame(width: 430)
        .onAppear { let item = store.setting(for: project); command = item.command ?? project.defaultCommand ?? ""; favorite = item.favorite; hostingProvider = item.hostingProvider; hostedURL = item.hostedURL ?? "" }
    }
}

private struct SecondaryButton: ButtonStyle { func makeBody(configuration: Configuration) -> some View { configuration.label.font(.caption.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 9).background(.white.opacity(configuration.isPressed ? 0.15 : 0.07), in: RoundedRectangle(cornerRadius: 7)).overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.12))) } }
struct PrimaryButton: ButtonStyle { let active: Bool; func makeBody(configuration: Configuration) -> some View { configuration.label.font(.caption.weight(.bold)).padding(.horizontal, 12).padding(.vertical, 9).foregroundStyle(active ? Color.white : Color.black).background(active ? Color.red.opacity(configuration.isPressed ? 0.75 : 0.9) : Color(red: 0.60, green: 0.94, blue: 0.37).opacity(configuration.isPressed ? 0.75 : 0.95), in: RoundedRectangle(cornerRadius: 7)) } }

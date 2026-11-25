import AppKit
import SwiftUI

struct HostedBadge: View {
    @EnvironmentObject private var store: ProjectStore
    let project: Project
    @State private var showingDetails = false

    var body: some View {
        let setting = store.setting(for: project)
        if setting.hostingProvider == .none {
            Text("-").foregroundStyle(.secondary)
        } else {
            let detail = "\(setting.hostingProvider.rawValue)\n\(setting.hostedURL ?? "No site URL")"
            Group {
                if let address = setting.hostedURL, let url = URL(string: address), url.host != nil {
                    Link(destination: url) { icon(for: setting.hostingProvider) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open \(project.name) on \(setting.hostingProvider.rawValue)")
                } else {
                    icon(for: setting.hostingProvider)
                }
            }
            .help(detail)
            .onHover { showingDetails = $0 }
            .popover(isPresented: $showingDetails, arrowEdge: .bottom) {
                Text(detail).padding(12).frame(width: 220, alignment: .leading)
            }
        }
    }

    private func icon(for provider: HostingProvider) -> some View {
        Group {
            if let name = provider.iconName,
               let url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "HostIcons"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Image(systemName: "globe")
            }
        }
        .frame(width: 20, height: 20)
        .frame(width: 24, height: 24)
        .contentShape(Rectangle())
    }
}

import AppKit
import SwiftUI

struct ProjectTitle: View {
    let project: Project
    let size: CGFloat
    @State private var showingDetails = false

    var body: some View {
        Button { showingDetails = true } label: {
            Text(project.name)
                .font(.system(size: size, weight: .semibold))
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .help(project.hoverDetail)
        .onHover { showingDetails = $0 }
        .popover(isPresented: $showingDetails, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text(project.name).font(.headline)
                Text(project.hoverDetail).textSelection(.enabled)
            }
            .padding(16)
            .frame(width: 320, alignment: .leading)
        }
    }
}

struct RepoBadge: View {
    let project: Project
    @State private var showingDetails = false

    private var changeSummary: String {
        guard let count = project.changedFiles else { return "Git status unavailable" }
        if count == 0 { return "Clean working tree" }
        return "\(count) changed \(count == 1 ? "file" : "files")"
    }

    private var detail: String {
        let branch = project.branch ?? "No branch"
        let remote = project.repositoryURL?.absoluteString ?? "No GitHub remote"
        return "Branch: \(branch)\n\(changeSummary)\n\(remote)"
    }

    var body: some View {
        if project.changedFiles != nil {
            indicator
            .help(detail)
            .onHover { showingDetails = $0 }
            .popover(isPresented: $showingDetails, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(project.name).font(.headline)
                    Label(project.branch ?? "No branch", systemImage: "arrow.triangle.branch")
                    Text(changeSummary)
                    if let url = project.repositoryURL {
                        Text(url.absoluteString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    } else {
                        Text("No GitHub remote").foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .frame(width: 240, alignment: .leading)
            }
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var indicator: some View {
        if let url = project.repositoryURL {
            Link(destination: url) {
                RepoIcon(name: "github")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(project.name) on GitHub")
        } else {
            RepoIcon(name: "git")
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .accessibilityLabel("Local Git repository. \(detail)")
        }
    }
}

private struct RepoIcon: View {
    let name: String

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "RepoIcons"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
            }
        }
        .frame(width: 18, height: 18)
    }
}

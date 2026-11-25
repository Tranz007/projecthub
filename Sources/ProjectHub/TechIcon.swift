import AppKit
import SwiftUI

struct TechIcon: View {
    let name: String

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "TechIcons"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Image(systemName: "cpu")
            }
        }
        .frame(width: 20, height: 20)
    }
}

struct TechStack: View {
    let technologies: [String]

    var body: some View {
        if technologies.isEmpty {
            Text("-").foregroundStyle(.secondary)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 6), count: 4), alignment: .leading, spacing: 4) {
                ForEach(technologies, id: \.self) { technology in
                    TechnologyBadge(name: technology)
                }
            }
        }
    }
}

private struct TechnologyBadge: View {
    let name: String
    @State private var showingDetails = false

    private var assetName: String {
        switch name {
        case "FastAPI": "fastapi"
        case "Next.js": "nextdotjs"
        case "Node.js": "nodedotjs"
        case "Python": "python"
        case "React": "react"
        case "TypeScript": "typescript"
        case "Vite": "vite"
        default: "other"
        }
    }

    var body: some View {
        TechIcon(name: assetName)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
            .help(name)
            .accessibilityLabel(name)
            .onHover { showingDetails = $0 }
            .popover(isPresented: $showingDetails, arrowEdge: .bottom) {
                Text(name).padding(10)
            }
    }
}

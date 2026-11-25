import SwiftUI

struct ServerIndicator: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let project: Project
    var size: CGFloat = 17

    @State private var showingDetail = false

    var body: some View {
        let health = store.serverHealth(for: project)
        Group {
            switch health {
            case .unavailable:
                Text("-").foregroundStyle(.secondary)
            case .stopped:
                Image(systemName: "square.fill").foregroundStyle(.gray)
            case .starting:
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
            case .running:
                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
                    let phase = timeline.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 2) / 2
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.green)
                        .rotationEffect(.degrees(reduceMotion ? 0 : phase * 360))
                }
            case .warning:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
        }
        .font(.system(size: size, weight: .semibold))
        .frame(width: size + 6, height: size + 6)
        .contentShape(Rectangle())
        .accessibilityLabel(health.detail)
        .help(health.detail)
        .onHover { showingDetail = $0 }
        .popover(isPresented: $showingDetail, arrowEdge: .bottom) {
            Text(health.detail)
                .padding(12)
                .frame(width: 230, alignment: .leading)
        }
    }
}

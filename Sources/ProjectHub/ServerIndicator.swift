import AppKit
import QuartzCore
import SwiftUI

struct ServerIndicator: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let project: Project
    var size: CGFloat = 17

    private var targetSize: CGFloat { max(30, size + 16) }

    var body: some View {
        let health = store.serverHealth(for: project)
        Group {
            switch health {
            case .unavailable:
                Text("-").foregroundStyle(.secondary)
                    .accessibilityLabel(health.detail)
            case .stopped:
                Image(systemName: "square.fill").foregroundStyle(.gray)
                    .accessibilityLabel(health.detail)
            case .starting:
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                    .accessibilityLabel(health.detail)
            case .running(let port):
                Button { store.openURL(for: project) } label: {
                    Color.clear
                        .frame(width: targetSize, height: targetSize)
                        .contentShape(Rectangle())
                        .overlay {
                            SpinningServerIcon(size: size, reduceMotion: reduceMotion)
                                .frame(width: size + 6, height: size + 6)
                                .allowsHitTesting(false)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(project.name) at localhost:\(String(port))")
            case .warning:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .accessibilityLabel(health.detail)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    .accessibilityLabel(health.detail)
            }
        }
        .font(.system(size: size, weight: .semibold))
        .frame(width: targetSize, height: targetSize)
        .help(health.detail)
    }
}

private struct SpinningServerIcon: NSViewRepresentable {
    let size: CGFloat
    let reduceMotion: Bool

    func makeNSView(context: Context) -> SpinnerContainer {
        SpinnerContainer(symbolSize: size)
    }

    func updateNSView(_ view: SpinnerContainer, context: Context) {
        if reduceMotion {
            view.symbolLayer.removeAnimation(forKey: "continuousRotation")
            view.symbolLayer.transform = CATransform3DIdentity
        } else if view.symbolLayer.animation(forKey: "continuousRotation") == nil {
            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.fromValue = 0
            rotation.toValue = -2 * Double.pi
            rotation.duration = 2
            rotation.repeatCount = .infinity
            rotation.timingFunction = CAMediaTimingFunction(name: .linear)
            view.symbolLayer.add(rotation, forKey: "continuousRotation")
        }
    }
}

private final class SpinnerContainer: NSView {
    let symbolLayer = CALayer()

    init(symbolSize: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        let side = symbolSize + 6
        let symbol = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: symbolSize, weight: .semibold))
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            symbol?.draw(in: rect)
            NSGraphicsContext.current?.compositingOperation = .sourceAtop
            NSColor.systemGreen.setFill()
            NSBezierPath(rect: rect).fill()
            return true
        }
        symbolLayer.contents = image
        symbolLayer.contentsGravity = .resizeAspect
        layer?.addSublayer(symbolLayer)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        symbolLayer.bounds = bounds
        symbolLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }
}

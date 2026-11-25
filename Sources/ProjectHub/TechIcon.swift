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

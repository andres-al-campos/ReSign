import SwiftUI
import AppKit

struct StatusIconView: View {
    let store: ProjectStore

    var body: some View {
        if let nsImage = NSImage(named: "MenuBarIcon") {
            let tinted = nsImage.tinted(with: NSColor(iconColor))
            Image(nsImage: tinted)
        }
    }

    private var iconColor: Color {
        // A build in flight shows regardless of section — a hidden project only
        // builds because the user pressed Rebuild, so it's worth surfacing.
        if store.projects.contains(where: { $0.isBuilding }) { return .blue.opacity(0.8) }
        // Everything else reflects active projects only. Hiding a project is how
        // you say "stop telling me about this one", so it must not keep the icon
        // red or orange forever.
        let active = store.projects.filter { !$0.isHidden }
        if active.contains(where: { $0.lastError != nil }) { return .red.opacity(0.8) }
        if active.contains(where: { $0.isDue }) { return .orange.opacity(0.8) }
        return .green.opacity(0.8)
    }
}

private extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let image = self.copy() as! NSImage
        image.lockFocus()
        color.set()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

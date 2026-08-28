import AppKit
import SwiftUI

private struct OverlayContent: View {
    let lines: [GlintLine]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.prefix(3).enumerated()), id: \.element.id) { index, line in
                HStack(spacing: 8) {
                    if !line.key.isEmpty {
                        Text(line.key).font(.system(.callout, design: .monospaced).weight(.bold))
                        Text(line.state.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    Text(line.title).font(.callout).lineLimit(1)
                    Spacer(minLength: 0)
                }.padding(.horizontal, 12).frame(height: 38)
                if index < min(lines.count, 3) - 1 { Divider().padding(.horizontal, 8) }
            }
        }.frame(width: 540)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.16)))
    }
}

@MainActor final class OverlayController {
    private let panel: NSPanel
    private var displayedLines: [GlintLine] = []
    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
        panel.sharingType = .none
    }
    func show(_ lines: [GlintLine], near mouse: CGPoint) {
        guard !lines.isEmpty else { hide(); return }
        let shown = Array(lines.prefix(3)); let size = CGSize(width: 540, height: CGFloat(shown.count * 38 + max(0, shown.count - 1)))
        let visible = (NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        var origin = CGPoint(x: mouse.x + 18, y: mouse.y - size.height - 18)
        if origin.x + size.width > visible.maxX { origin.x = mouse.x - size.width - 18 }
        if origin.y < visible.minY { origin.y = mouse.y + 18 }
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width); origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        let frame = CGRect(origin: origin, size: size)
        if displayedLines == shown, panel.isVisible {
            if panel.frame != frame { panel.setFrame(frame, display: true) }
            return
        }
        displayedLines = shown
        panel.contentView = NSHostingView(rootView: OverlayContent(lines: shown)); panel.setFrame(frame, display: true); panel.orderFrontRegardless()
    }
    func hide() { panel.orderOut(nil) }
}

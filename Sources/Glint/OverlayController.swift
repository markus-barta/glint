import AppKit
import SwiftUI

private enum OverlayMetrics {
    static let width: CGFloat = 590

    static func height(for lines: [GlintLine], sticky: Bool) -> CGFloat {
        guard let first = lines.first else { return 0 }
        let primary: CGFloat = first.detail.isEmpty ? 138 : 198
        let secondaryCount = min(max(0, lines.count - 1), sticky ? 4 : 2)
        let secondary = secondaryCount == 0 ? 0 : 34 + CGFloat(secondaryCount * 48)
        let footer: CGFloat = (sticky || lines.count > 1) ? 32 : 0
        return primary + secondary + footer + 20
    }
}

private struct StatusPill: View {
    let state: String

    private var color: Color {
        switch state.lowercased() {
        case "done", "accepted", "merged", "closed": return .green
        case "in-progress", "in_progress", "open": return .blue
        case "blocked", "cancelled": return .red
        default: return .secondary
        }
    }

    var body: some View {
        Text(state.replacingOccurrences(of: "_", with: " ").uppercased())
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private struct PrimaryResultCard: View {
    let line: GlintLine

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(line.key)
                    .font(.system(.headline, design: .monospaced).weight(.bold))
                    .foregroundStyle(.tint)
                StatusPill(state: line.state)
                Spacer(minLength: 8)
                Text(line.source.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(line.title)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if !line.detail.isEmpty {
                Text(line.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !line.metadata.isEmpty {
                Text(line.metadata)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.82))
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.accentColor)
                .frame(width: 4)
                .padding(.vertical, 10)
        }
    }
}

private struct SecondaryResultRow: View {
    let line: GlintLine

    var body: some View {
        HStack(spacing: 9) {
            Text(line.key)
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .foregroundStyle(.tint)
                .frame(minWidth: 86, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.title).font(.callout.weight(.medium)).lineLimit(1)
                if !line.metadata.isEmpty {
                    Text(line.metadata).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            StatusPill(state: line.state)
        }
        .padding(.horizontal, 8)
        .frame(height: 47)
    }
}

private struct OverlayContent: View {
    let lines: [GlintLine]
    let sticky: Bool
    let shortcutLabel: String

    private var secondary: [GlintLine] { Array(lines.dropFirst()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let first = lines.first { PrimaryResultCard(line: first) }
            if !secondary.isEmpty {
                HStack {
                    Text("MORE MATCHES").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    Text("\(secondary.count)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                    Spacer()
                    if !sticky && secondary.count > 2 {
                        Text("Pin to see all").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                ScrollView(.vertical, showsIndicators: sticky) {
                    LazyVStack(spacing: 0) {
                        ForEach(secondary) { line in
                            SecondaryResultRow(line: line)
                            if line.id != secondary.last?.id { Divider().padding(.leading, 8) }
                        }
                    }
                }
                .frame(maxHeight: sticky ? 192 : 96)
                .allowsHitTesting(sticky)
            }
            if sticky || lines.count > 1 {
                HStack(spacing: 6) {
                    Image(systemName: sticky ? "pin.fill" : "pin")
                    Text(sticky ? "Pinned · scroll for more · \(shortcutLabel) closes" : "\(shortcutLabel) pins and enables scrolling")
                }
                .font(.caption)
                .foregroundStyle(sticky ? Color.accentColor : .secondary)
                .padding(.horizontal, 8)
            }
        }
        .padding(10)
        .frame(width: OverlayMetrics.width, height: OverlayMetrics.height(for: lines, sticky: sticky), alignment: .top)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.18)))
    }
}

@MainActor final class OverlayController {
    private let panel: NSPanel
    private var displayedLines: [GlintLine] = []
    private var anchorMouse = CGPoint.zero
    private var shortcutLabel = "⌥ twice"
    private(set) var isSticky = false

    var isVisible: Bool { panel.isVisible }

    init(allowsCapture: Bool = false) {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.sharingType = allowsCapture ? .readOnly : .none
        panel.becomesKeyOnlyIfNeeded = true
    }

    func show(_ lines: [GlintLine], near mouse: CGPoint, shortcutLabel: String = "⌥ twice") {
        guard !lines.isEmpty else { hide(); return }
        guard !isSticky else { return }
        displayedLines = Array(lines.prefix(HoverResultPolicy.maximumResults))
        anchorMouse = mouse
        self.shortcutLabel = shortcutLabel
        render()
        panel.orderFrontRegardless()
    }

    func pin(shortcutLabel: String) {
        guard panel.isVisible, !displayedLines.isEmpty else { return }
        isSticky = true
        self.shortcutLabel = shortcutLabel
        panel.ignoresMouseEvents = false
        render()
        panel.orderFrontRegardless()
    }

    func closePinned() {
        guard isSticky else { return }
        hide()
    }

    func hide() {
        panel.orderOut(nil)
        isSticky = false
        panel.ignoresMouseEvents = true
    }

    private func render() {
        let size = CGSize(width: OverlayMetrics.width, height: OverlayMetrics.height(for: displayedLines, sticky: isSticky))
        let visible = (NSScreen.screens.first(where: { $0.frame.contains(anchorMouse) }) ?? NSScreen.main)?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        var origin = CGPoint(x: anchorMouse.x + 18, y: anchorMouse.y - size.height - 18)
        if origin.x + size.width > visible.maxX { origin.x = anchorMouse.x - size.width - 18 }
        if origin.y < visible.minY { origin.y = anchorMouse.y + 18 }
        let edgeInset: CGFloat = 8
        origin.x = min(max(origin.x, visible.minX + edgeInset), visible.maxX - size.width - edgeInset)
        origin.y = min(max(origin.y, visible.minY + edgeInset), visible.maxY - size.height - edgeInset)
        panel.contentView = NSHostingView(rootView: OverlayContent(lines: displayedLines, sticky: isSticky, shortcutLabel: shortcutLabel))
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
    }
}

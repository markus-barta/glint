import AppKit
import SwiftUI

struct ScanFeedbackAnchor: Hashable, Identifiable, Sendable {
    let id: UUID
    let literal: String
    let bounds: CGRect

    init(id: UUID = UUID(), literal: String, bounds: CGRect) {
        self.id = id
        self.literal = literal
        self.bounds = bounds.standardized
    }

    /// Maps the parser's stable source order back to the exact Vision span.
    /// This keeps integration free of coordinate-space or range arithmetic.
    init?(token: NearbyToken, fragments: [RecognizedTextFragment]) {
        let fragmentIndex = token.sourceOrder / 1_000_000
        let utf16Location = token.sourceOrder % 1_000_000
        guard fragments.indices.contains(fragmentIndex),
              let bounds = fragments[fragmentIndex].screenBounds(
                forUTF16Range: NSRange(location: utf16Location, length: (token.raw as NSString).length),
                literal: token.raw
              ) else { return nil }
        self.init(literal: token.raw, bounds: bounds)
    }
}

private enum ScanFeedbackPhase: Equatable {
    case invoked(point: CGPoint)
    case recognized(anchors: [ScanFeedbackAnchor], selectedID: UUID?)
    case resolved(anchor: ScanFeedbackAnchor)
    case noMatch(point: CGPoint)
}

private final class ScanFeedbackPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct ScanFeedbackView: View {
    let phase: ScanFeedbackPhase
    let panelFrame: CGRect
    let reduceMotion: Bool
    @State private var animated = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            switch phase {
            case let .invoked(point):
                ripple(at: local(point), color: .accentColor)
            case let .recognized(anchors, selectedID):
                ForEach(anchors) { anchor in
                    anchorView(anchor, selected: anchor.id == selectedID, resolved: false)
                }
            case let .resolved(anchor):
                anchorView(anchor, selected: true, resolved: true)
            case let .noMatch(point):
                noMatchView(at: local(point))
            }
        }
        .onAppear { beginAnimation() }
        .accessibilityHidden(true)
        .frame(width: panelFrame.width, height: panelFrame.height)
    }

    private func local(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - panelFrame.minX, y: panelFrame.maxY - point.y)
    }

    private func local(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX - panelFrame.minX,
            y: panelFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private func ripple(at point: CGPoint, color: Color) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(reduceMotion ? 0.7 : (animated ? 0 : 0.9)), lineWidth: 2)
                .frame(width: reduceMotion ? 38 : (animated ? 66 : 22), height: reduceMotion ? 38 : (animated ? 66 : 22))
            Circle().fill(color).frame(width: 7, height: 7)
            Image(systemName: "viewfinder")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(color)
                .opacity(reduceMotion ? (animated ? 1 : 0.45) : 0.95)
        }
        .position(point)
    }

    private func anchorView(_ anchor: ScanFeedbackAnchor, selected: Bool, resolved: Bool) -> some View {
        let rect = local(anchor.bounds).insetBy(dx: -4, dy: -3)
        let color: Color = resolved ? .green : .accentColor
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(color.opacity(selected ? 0.13 : 0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(color.opacity(selected ? 0.95 : 0.48), lineWidth: selected ? 2 : 1)
                }
                .frame(width: max(14, rect.width), height: max(12, rect.height))
                .position(x: rect.midX, y: rect.midY)

            if selected {
                HStack(spacing: 5) {
                    Image(systemName: resolved ? "checkmark" : "viewfinder")
                    Text(anchor.literal)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(color.opacity(0.94), in: Capsule())
                .shadow(color: .black.opacity(0.24), radius: 3, y: 1)
                .fixedSize()
                .position(x: labelX(for: rect), y: max(13, rect.minY - 14))
            }
        }
        .opacity(reduceMotion ? (animated ? 1 : 0.45) : 1)
        .scaleEffect(!reduceMotion && selected && !animated ? 0.96 : 1)
    }

    private func labelX(for rect: CGRect) -> CGFloat {
        min(max(rect.midX, 46), panelFrame.width - 46)
    }

    private func noMatchView(at point: CGPoint) -> some View {
        ZStack {
            Circle()
                .stroke(Color.orange.opacity(animated ? 0.15 : 0.85), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                .frame(width: 38, height: 38)
            Image(systemName: "questionmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.orange)
        }
        .scaleEffect(reduceMotion ? 1 : (animated ? 1.08 : 0.92))
        .opacity(reduceMotion ? (animated ? 1 : 0.5) : 1)
        .position(point)
    }

    private func beginAnimation() {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.16)) { animated = true }
        } else {
            withAnimation(.easeOut(duration: 0.38)) { animated = true }
        }
    }
}

/// A capture-excluded, nonactivating visual acknowledgement for the scan
/// lifecycle. Calls are intentionally synchronous and cheap; OCR and lookup
/// should begin immediately after `invoked(at:)` returns.
@MainActor
final class ScanFeedbackController {
    private let panel: ScanFeedbackPanel
    private var phase: ScanFeedbackPhase?
    private var lastPoint = CGPoint.zero
    private var disappearanceTask: Task<Void, Never>?
    private var displayOptionsObserver: NSObjectProtocol?
    private var reduceMotion: Bool

    init() {
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel = ScanFeedbackPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configurePanel()
        displayOptionsObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.displayOptionsChanged() }
        }
    }

    deinit {
        disappearanceTask?.cancel()
        if let displayOptionsObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(displayOptionsObserver)
        }
    }

    func invoked(at point: CGPoint) {
        lastPoint = point
        present(.invoked(point: point), around: CGRect(origin: point, size: .zero), lifetime: 1.5)
    }

    func recognized(anchors: [ScanFeedbackAnchor], selected: ScanFeedbackAnchor?) {
        let visible = deduplicated(anchors)
        guard !visible.isEmpty else { return }
        if let selected { lastPoint = CGPoint(x: selected.bounds.midX, y: selected.bounds.midY) }
        else if let first = visible.first { lastPoint = CGPoint(x: first.bounds.midX, y: first.bounds.midY) }
        present(
            .recognized(anchors: visible, selectedID: selected?.id),
            around: visible.map(\.bounds).reduce(CGRect.null) { $0.union($1) },
            lifetime: 8
        )
    }

    func resolved(anchor: ScanFeedbackAnchor) {
        lastPoint = CGPoint(x: anchor.bounds.midX, y: anchor.bounds.midY)
        present(.resolved(anchor: anchor), around: anchor.bounds, lifetime: 0.7)
    }

    func noMatch() {
        present(.noMatch(point: lastPoint), around: CGRect(origin: lastPoint, size: .zero), lifetime: 0.85)
    }

    func cancel() {
        disappearanceTask?.cancel()
        disappearanceTask = nil
        phase = nil
        panel.orderOut(nil)
    }

    private func configurePanel() {
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.sharingType = .none
        panel.isReleasedWhenClosed = false
    }

    private func present(_ phase: ScanFeedbackPhase, around contentBounds: CGRect, lifetime: TimeInterval) {
        disappearanceTask?.cancel()
        self.phase = phase
        let frame = panelFrame(around: contentBounds)
        let contentView = NSHostingView(rootView: ScanFeedbackView(
            phase: phase,
            panelFrame: frame,
            reduceMotion: reduceMotion
        ))
        contentView.frame = CGRect(origin: .zero, size: frame.size)
        panel.contentView = contentView
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()
        scheduleDisappearance(after: lifetime)
    }

    private func scheduleDisappearance(after delay: TimeInterval) {
        disappearanceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.cancel() }
        }
    }

    private func displayOptionsChanged() {
        let updated = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard updated != reduceMotion else { return }
        reduceMotion = updated
        guard let phase else { return }
        let contentBounds: CGRect
        switch phase {
        case let .invoked(point), let .noMatch(point): contentBounds = CGRect(origin: point, size: .zero)
        case let .recognized(anchors, _): contentBounds = anchors.map(\.bounds).reduce(CGRect.null) { $0.union($1) }
        case let .resolved(anchor): contentBounds = anchor.bounds
        }
        let frame = panelFrame(around: contentBounds)
        panel.contentView = NSHostingView(rootView: ScanFeedbackView(phase: phase, panelFrame: frame, reduceMotion: reduceMotion))
    }

    private func panelFrame(around rawBounds: CGRect) -> CGRect {
        let point = rawBounds.isNull
            ? lastPoint
            : CGPoint(x: rawBounds.midX, y: rawBounds.midY)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) })
            ?? NSScreen.screens.first(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(point) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let desired = (rawBounds.isNull ? CGRect(origin: point, size: .zero) : rawBounds)
            .insetBy(dx: -72, dy: -52)
            .union(CGRect(x: point.x - 54, y: point.y - 54, width: 108, height: 108))
        return desired.intersection(screen.frame)
    }

    private func deduplicated(_ anchors: [ScanFeedbackAnchor]) -> [ScanFeedbackAnchor] {
        var seen = Set<String>()
        return anchors.filter { anchor in
            let key = "\(anchor.literal.lowercased())|\(Int(anchor.bounds.midX.rounded()))|\(Int(anchor.bounds.midY.rounded()))"
            return seen.insert(key).inserted
        }
    }
}

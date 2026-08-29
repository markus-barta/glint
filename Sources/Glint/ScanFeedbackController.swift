import AppKit
import SwiftUI

struct ScanFeedbackAnchorID: Hashable, Sendable {
    let literal: String
    let minX: Int
    let minY: Int
    let width: Int
    let height: Int

    init(literal: String, bounds: CGRect) {
        self.literal = literal
        minX = Self.quantized(bounds.minX)
        minY = Self.quantized(bounds.minY)
        width = Self.quantized(bounds.width)
        height = Self.quantized(bounds.height)
    }

    private static func quantized(_ value: CGFloat) -> Int {
        guard value.isFinite else { return 0 }
        return Int((value * 2).rounded())
    }
}

struct ScanFeedbackAnchor: Hashable, Identifiable, Sendable {
    let id: ScanFeedbackAnchorID
    let literal: String
    let bounds: CGRect

    init(literal: String, bounds: CGRect) {
        self.literal = literal
        self.bounds = bounds.standardized
        id = ScanFeedbackAnchorID(literal: literal, bounds: self.bounds)
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

enum ScanFeedbackPhase: Equatable {
    case invoked(point: CGPoint)
    case recognized(anchors: [ScanFeedbackAnchor], selectedID: ScanFeedbackAnchorID?)
    case resolved(anchor: ScanFeedbackAnchor)
    case noMatch(point: CGPoint)
}

private final class ScanFeedbackPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

enum ScanFeedbackGeometry {
    static func panelFrame(
        around rawBounds: CGRect,
        lastPoint: CGPoint,
        screenFrames: [CGRect],
        mainScreenFrame: CGRect?
    ) -> CGRect? {
        guard !screenFrames.isEmpty else { return nil }
        let point = rawBounds.isNull
            ? lastPoint
            : CGPoint(x: rawBounds.midX, y: rawBounds.midY)
        let screenFrame = screenFrames.first(where: { $0.contains(point) })
            ?? screenFrames.first(where: { $0.insetBy(dx: -1, dy: -1).contains(point) })
            ?? mainScreenFrame
            ?? screenFrames.first
        guard let screenFrame else { return nil }

        let desired = (rawBounds.isNull ? CGRect(origin: point, size: .zero) : rawBounds)
            .insetBy(dx: -72, dy: -52)
            .union(CGRect(x: point.x - 54, y: point.y - 54, width: 108, height: 108))
        let visible = desired.intersection(screenFrame)
        if !visible.isNull, !visible.isEmpty { return visible }

        let safePoint = CGPoint(
            x: min(max(point.x, screenFrame.minX), screenFrame.maxX),
            y: min(max(point.y, screenFrame.minY), screenFrame.maxY)
        )
        return CGRect(x: safePoint.x - 54, y: safePoint.y - 54, width: 108, height: 108)
            .intersection(screenFrame)
    }
}

enum ScanFeedbackDisappearancePolicy {
    static func shouldExpire(scheduledGeneration: Int, currentGeneration: Int) -> Bool {
        scheduledGeneration == currentGeneration
    }
}

enum ScanFeedbackPresentationAction: Equatable {
    case refreshExpiry
    case rebuild
}

struct ScanFeedbackPresentationDecision: Equatable {
    let action: ScanFeedbackPresentationAction
    let generation: Int
}

enum ScanFeedbackPresentationPolicy {
    static func decision(
        current: ScanFeedbackPhase?,
        incoming: ScanFeedbackPhase,
        generation: Int
    ) -> ScanFeedbackPresentationDecision {
        ScanFeedbackPresentationDecision(
            action: representsSamePresentation(current, incoming) ? .refreshExpiry : .rebuild,
            generation: generation &+ 1
        )
    }

    private static func representsSamePresentation(
        _ current: ScanFeedbackPhase?,
        _ incoming: ScanFeedbackPhase
    ) -> Bool {
        switch (current, incoming) {
        case let (.invoked(lhs)?, .invoked(rhs)), let (.noMatch(lhs)?, .noMatch(rhs)):
            return lhs == rhs
        case let (.recognized(lhsAnchors, lhsSelected)?, .recognized(rhsAnchors, rhsSelected)):
            return lhsAnchors.map(\.id) == rhsAnchors.map(\.id) && lhsSelected == rhsSelected
        case let (.resolved(lhs)?, .resolved(rhs)):
            return lhs.id == rhs.id
        default:
            return false
        }
    }
}

enum ScanFeedbackTiming {
    static let invokedLifetime: TimeInterval = 1.5
    static let recognizedLifetime: TimeInterval = 2.2
    static let resolvedLifetime: TimeInterval = 0.7
    static let noMatchLifetime: TimeInterval = 0.85
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
    private var presentationGeneration = 0
    private var displayOptionsObserver: NSObjectProtocol?
    private var reduceMotion: Bool

    init(allowsCapture: Bool = false) {
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel = ScanFeedbackPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configurePanel(allowsCapture: allowsCapture)
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
        present(.invoked(point: point), around: CGRect(origin: point, size: .zero), lifetime: ScanFeedbackTiming.invokedLifetime)
    }

    func recognized(anchors: [ScanFeedbackAnchor], selected: ScanFeedbackAnchor?) {
        let visible = deduplicated(anchors)
        guard !visible.isEmpty else { return }
        if let selected { lastPoint = CGPoint(x: selected.bounds.midX, y: selected.bounds.midY) }
        else if let first = visible.first { lastPoint = CGPoint(x: first.bounds.midX, y: first.bounds.midY) }
        present(
            .recognized(anchors: visible, selectedID: selected?.id),
            around: visible.map(\.bounds).reduce(CGRect.null) { $0.union($1) },
            lifetime: ScanFeedbackTiming.recognizedLifetime
        )
    }

    func resolved(anchor: ScanFeedbackAnchor) {
        lastPoint = CGPoint(x: anchor.bounds.midX, y: anchor.bounds.midY)
        present(.resolved(anchor: anchor), around: anchor.bounds, lifetime: ScanFeedbackTiming.resolvedLifetime)
    }

    func noMatch() {
        present(.noMatch(point: lastPoint), around: CGRect(origin: lastPoint, size: .zero), lifetime: ScanFeedbackTiming.noMatchLifetime)
    }

    func cancel() {
        presentationGeneration += 1
        disappearanceTask?.cancel()
        disappearanceTask = nil
        phase = nil
        panel.orderOut(nil)
    }

    private func configurePanel(allowsCapture: Bool) {
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
#if DEBUG
        panel.sharingType = allowsCapture ? .readOnly : .none
#else
        // Release feedback can never be captured, even if a caller passes the
        // debug seam's flag by mistake.
        panel.sharingType = .none
#endif
        panel.isReleasedWhenClosed = false
    }

    private func present(_ phase: ScanFeedbackPhase, around contentBounds: CGRect, lifetime: TimeInterval) {
        disappearanceTask?.cancel()
        let decision = ScanFeedbackPresentationPolicy.decision(
            current: self.phase,
            incoming: phase,
            generation: presentationGeneration
        )
        presentationGeneration = decision.generation
        let generation = decision.generation
        if decision.action == .refreshExpiry {
            scheduleDisappearance(after: lifetime, generation: generation)
            return
        }
        self.phase = phase
        guard let frame = panelFrame(around: contentBounds) else {
            cancel()
            return
        }
        let contentView = NSHostingView(rootView: ScanFeedbackView(
            phase: phase,
            panelFrame: frame,
            reduceMotion: reduceMotion
        ))
        contentView.frame = CGRect(origin: .zero, size: frame.size)
        panel.contentView = contentView
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()
        scheduleDisappearance(after: lifetime, generation: generation)
    }

    private func scheduleDisappearance(after delay: TimeInterval, generation: Int) {
        disappearanceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      ScanFeedbackDisappearancePolicy.shouldExpire(
                          scheduledGeneration: generation,
                          currentGeneration: self.presentationGeneration
                      ) else { return }
                self.cancel()
            }
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
        guard let frame = panelFrame(around: contentBounds) else {
            cancel()
            return
        }
        panel.contentView = NSHostingView(rootView: ScanFeedbackView(phase: phase, panelFrame: frame, reduceMotion: reduceMotion))
    }

    private func panelFrame(around rawBounds: CGRect) -> CGRect? {
        ScanFeedbackGeometry.panelFrame(
            around: rawBounds,
            lastPoint: lastPoint,
            screenFrames: NSScreen.screens.map(\.frame),
            mainScreenFrame: NSScreen.main?.frame
        )
    }

    private func deduplicated(_ anchors: [ScanFeedbackAnchor]) -> [ScanFeedbackAnchor] {
        var seen = Set<ScanFeedbackAnchorID>()
        return anchors.filter { seen.insert($0.id).inserted }
    }

#if DEBUG
    func showDebugInvoked(at point: CGPoint) {
        reduceMotion = true
        lastPoint = point
        present(.invoked(point: point), around: CGRect(origin: point, size: .zero), lifetime: 60)
    }

    func showDebugRecognized(anchors: [ScanFeedbackAnchor], selected: ScanFeedbackAnchor) {
        lastPoint = CGPoint(x: selected.bounds.midX, y: selected.bounds.midY)
        present(
            .recognized(anchors: anchors, selectedID: selected.id),
            around: anchors.map(\.bounds).reduce(CGRect.null) { $0.union($1) },
            lifetime: 60
        )
    }

    func showDebugResolved(anchor: ScanFeedbackAnchor) {
        lastPoint = CGPoint(x: anchor.bounds.midX, y: anchor.bounds.midY)
        present(.resolved(anchor: anchor), around: anchor.bounds, lifetime: 60)
    }
#endif
}

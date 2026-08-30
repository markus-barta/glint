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
    case lookup(
        anchors: [ScanFeedbackAnchor],
        selectedID: ScanFeedbackAnchorID,
        celebratesFound: Bool
    )
    case noMatch(point: CGPoint)
}

enum LookupHighlightPolicy {
    static func visibleAnchors(
        _ anchors: [ScanFeedbackAnchor],
        selected: ScanFeedbackAnchor,
        showAll: Bool
    ) -> [ScanFeedbackAnchor] {
        guard showAll else { return [selected] }
        var seen = Set<ScanFeedbackAnchorID>()
        let visible = anchors.filter { seen.insert($0.id).inserted }
        return seen.contains(selected.id) ? visible : visible + [selected]
    }
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
        case let (
            .lookup(lhsAnchors, lhsSelected, lhsCelebrates)?,
            .lookup(rhsAnchors, rhsSelected, rhsCelebrates)
        ):
            return lhsAnchors.map(\.id) == rhsAnchors.map(\.id)
                && lhsSelected == rhsSelected
                && lhsCelebrates == rhsCelebrates
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

enum ScanFeedbackStyleMetrics {
    static let sourceInset: CGFloat = 4
    static let sourceCornerRadius: CGFloat = 6
    static let labelHeight: CGFloat = 26
    static let labelGap: CGFloat = 6
    static let labelHorizontalPadding: CGFloat = 8
    static let labelBorderWidth: CGFloat = 1
    static let foundAnimationDuration: TimeInterval = 0.92
}

struct FoundLockOnAnimationState: Equatable {
    let sweep: Double
    let sweepOpacity: Double
    let confirmation: Double
    let confirmationOpacity: Double
    let particleOpacity: Double

    static func at(progress rawProgress: Double) -> FoundLockOnAnimationState {
        let progress = min(max(rawProgress, 0), 1)
        let sweep = easeOut(min(progress / 0.58, 1))
        let sweepOpacity = 1 - easeOut(min(max((progress - 0.64) / 0.36, 0), 1))
        let confirmation = min(max((progress - 0.34) / 0.54, 0), 1)
        return FoundLockOnAnimationState(
            sweep: sweep,
            sweepOpacity: sweepOpacity,
            confirmation: confirmation,
            confirmationOpacity: max(0, 1 - confirmation),
            particleOpacity: confirmation >= 1
                ? 0
                : max(0, sin(confirmation * .pi)) * 0.82
        )
    }

    private static func easeOut(_ value: Double) -> Double {
        1 - pow(1 - value, 3)
    }
}

struct ScanFeedbackView: View {
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
            case let .lookup(anchors, selectedID, celebratesFound):
                ForEach(anchors) { anchor in
                    anchorView(
                        anchor,
                        selected: anchor.id == selectedID,
                        resolved: false,
                        alwaysLabel: true
                    )
                }
                if celebratesFound,
                   let selected = anchors.first(where: { $0.id == selectedID }),
                   !reduceMotion {
                    FoundLockOnEffect(
                        rect: local(selected.bounds).insetBy(
                            dx: -ScanFeedbackStyleMetrics.sourceInset,
                            dy: -ScanFeedbackStyleMetrics.sourceInset
                        )
                    )
                }
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

    private func anchorView(
        _ anchor: ScanFeedbackAnchor,
        selected: Bool,
        resolved: Bool,
        alwaysLabel: Bool = false
    ) -> some View {
        let rect = local(anchor.bounds).insetBy(
            dx: -ScanFeedbackStyleMetrics.sourceInset,
            dy: -ScanFeedbackStyleMetrics.sourceInset
        )
        let color: Color = resolved ? .green : .accentColor
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: ScanFeedbackStyleMetrics.sourceCornerRadius, style: .continuous)
                .fill(color.opacity(selected ? 0.13 : 0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: ScanFeedbackStyleMetrics.sourceCornerRadius, style: .continuous)
                        .stroke(color.opacity(selected ? 0.95 : 0.48), lineWidth: selected ? 2 : 1)
                }
                .frame(width: max(14, rect.width), height: max(12, rect.height))
                .position(x: rect.midX, y: rect.midY)

            if selected || alwaysLabel {
                HStack(spacing: 5) {
                    Image(systemName: resolved ? "checkmark" : (selected ? "viewfinder" : "circle.fill"))
                        .font(.system(size: selected || resolved ? 11 : 5, weight: .semibold))
                    Text(anchor.literal)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, ScanFeedbackStyleMetrics.labelHorizontalPadding)
                .frame(height: ScanFeedbackStyleMetrics.labelHeight)
                .background(selected || resolved ? color.opacity(0.96) : Color.black.opacity(0.76), in: Capsule())
                .overlay {
                    Capsule().stroke(
                        selected || resolved ? Color.white.opacity(0.20) : color.opacity(0.72),
                        lineWidth: ScanFeedbackStyleMetrics.labelBorderWidth
                    )
                }
                .shadow(color: .black.opacity(0.24), radius: 3, y: 1)
                .fixedSize()
                .position(
                    x: labelX(for: rect),
                    y: max(
                        ScanFeedbackStyleMetrics.labelHeight / 2,
                        rect.minY - ScanFeedbackStyleMetrics.labelGap - ScanFeedbackStyleMetrics.labelHeight / 2
                    )
                )
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

private struct FoundLockOnEffect: View {
    let rect: CGRect
    @State private var startedAt = Date()
    @State private var finished = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: finished)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startedAt)
            let progress = min(max(elapsed / ScanFeedbackStyleMetrics.foundAnimationDuration, 0), 1)
            Canvas { context, _ in
                drawEffect(in: &context, progress: progress)
            }
        }
        .allowsHitTesting(false)
        .task {
            startedAt = Date()
            try? await Task.sleep(
                nanoseconds: UInt64(ScanFeedbackStyleMetrics.foundAnimationDuration * 1_000_000_000)
            )
            guard !Task.isCancelled else { return }
            finished = true
        }
    }

    private func drawEffect(in context: inout GraphicsContext, progress: Double) {
        let state = FoundLockOnAnimationState.at(progress: progress)
        let outline = Path(
            roundedRect: rect.insetBy(dx: -1.5, dy: -1.5),
            cornerRadius: ScanFeedbackStyleMetrics.sourceCornerRadius + 2
        )
        let trailStart = max(0, state.sweep - 0.22)

        if state.sweepOpacity > 0.001 {
            context.addFilter(.shadow(
                color: Color.cyan.opacity(0.68 * state.sweepOpacity),
                radius: 7
            ))
            context.stroke(
                outline.trimmedPath(from: trailStart, to: state.sweep),
                with: .linearGradient(
                    Gradient(colors: [
                        .blue.opacity(0.18 * state.sweepOpacity),
                        .cyan.opacity(state.sweepOpacity),
                        .white.opacity(state.sweepOpacity)
                    ]),
                    startPoint: CGPoint(x: rect.minX, y: rect.minY),
                    endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
                ),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
            )
        }

        if state.confirmation > 0, state.confirmationOpacity > 0 {
            let expansion = 2 + (state.confirmation * 12)
            let pulseRect = rect.insetBy(dx: -expansion, dy: -expansion)
            let pulse = Path(
                roundedRect: pulseRect,
                cornerRadius: ScanFeedbackStyleMetrics.sourceCornerRadius + expansion
            )
            context.stroke(
                pulse,
                with: .color(.green.opacity(0.62 * state.confirmationOpacity)),
                lineWidth: 2
            )
            drawParticles(in: &context, state: state)
        }
    }

    private func drawParticles(
        in context: inout GraphicsContext,
        state: FoundLockOnAnimationState
    ) {
        let origins = [
            (CGPoint(x: rect.minX, y: rect.minY), CGVector(dx: -8, dy: -7)),
            (CGPoint(x: rect.maxX, y: rect.minY), CGVector(dx: 8, dy: -7)),
            (CGPoint(x: rect.minX, y: rect.maxY), CGVector(dx: -8, dy: 7)),
            (CGPoint(x: rect.maxX, y: rect.maxY), CGVector(dx: 8, dy: 7))
        ]
        for (index, particle) in origins.enumerated() {
            let distance = CGFloat(state.confirmation)
            let center = CGPoint(
                x: particle.0.x + particle.1.dx * distance,
                y: particle.0.y + particle.1.dy * distance
            )
            let diameter: CGFloat = index.isMultiple(of: 2) ? 3.5 : 2.5
            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - diameter / 2,
                    y: center.y - diameter / 2,
                    width: diameter,
                    height: diameter
                )),
                with: .color(
                    (index.isMultiple(of: 2) ? Color.cyan : Color.green)
                        .opacity(state.particleOpacity)
                )
            )
        }
    }
}

#if DEBUG
struct LookupHighlightReleaseProbe: View {
    static let canvasSize = CGSize(width: 920, height: 380)

    private let primary = ScanFeedbackAnchor(
        literal: "NUNCID-52",
        bounds: CGRect(x: 54, y: 158, width: 78, height: 18)
    )
    private let secondary = ScanFeedbackAnchor(
        literal: "HAUSV-38",
        bounds: CGRect(x: 290, y: 90, width: 70, height: 18)
    )
    private let pullRequest = ScanFeedbackAnchor(
        literal: "#14",
        bounds: CGRect(x: 594, y: 158, width: 28, height: 18)
    )

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(red: 0.025, green: 0.055, blue: 0.10), Color(red: 0.045, green: 0.11, blue: 0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 4) {
                Text("FOUND IN PLACE")
                    .font(.caption2.weight(.bold)).tracking(1.4).foregroundStyle(.blue)
                Text("The current lookup stays clear. Pin to keep every detected ID in view.")
                    .font(.title3.weight(.semibold)).foregroundStyle(.white)
                Text("Markers ignore the mouse and never appear in Nuncid’s own captures.")
                    .font(.callout).foregroundStyle(.white.opacity(0.58))
            }
            .padding(.leading, 34)
            .padding(.top, 28)

            sourceRow(
                key: "NUNCID-52",
                detail: "Keep detected IDs visible beside their source",
                width: 520
            )
                .position(x: 300, y: 213)
            sourceRow(
                key: "HAUSV-38",
                detail: "The next ticket remains readable and secondary",
                width: 520
            )
                .position(x: 536, y: 281)
            sourceRow(key: "#14", detail: "Open the current pull request", width: 300)
                .position(x: 730, y: 213)

            ScanFeedbackView(
                phase: .lookup(
                    anchors: [primary, secondary, pullRequest],
                    selectedID: primary.id,
                    celebratesFound: false
                ),
                panelFrame: CGRect(origin: .zero, size: Self.canvasSize),
                reduceMotion: true
            )
        }
        .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.14)))
    }

    private func sourceRow(key: String, detail: String, width: CGFloat) -> some View {
        HStack(spacing: 12) {
            Text(key)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .fixedSize()
            Text(detail)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(width: width, height: 48)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08)))
    }
}
#endif

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

    func highlight(
        anchors: [ScanFeedbackAnchor],
        selected: ScanFeedbackAnchor,
        showAll: Bool,
        animateFound: Bool = false
    ) {
        lastPoint = CGPoint(x: selected.bounds.midX, y: selected.bounds.midY)
        let visible = LookupHighlightPolicy.visibleAnchors(anchors, selected: selected, showAll: showAll)
        present(
            .lookup(
                anchors: visible,
                selectedID: selected.id,
                celebratesFound: animateFound
            ),
            around: visible.map(\.bounds).reduce(CGRect.null) { $0.union($1) },
            lifetime: nil
        )
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

    private func present(_ phase: ScanFeedbackPhase, around contentBounds: CGRect, lifetime: TimeInterval?) {
        disappearanceTask?.cancel()
        let decision = ScanFeedbackPresentationPolicy.decision(
            current: self.phase,
            incoming: phase,
            generation: presentationGeneration
        )
        presentationGeneration = decision.generation
        let generation = decision.generation
        if decision.action == .refreshExpiry {
            if let lifetime { scheduleDisappearance(after: lifetime, generation: generation) }
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
        if let lifetime { scheduleDisappearance(after: lifetime, generation: generation) }
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
        let displayPhase: ScanFeedbackPhase
        if case let .lookup(anchors, selectedID, true) = phase {
            displayPhase = .lookup(
                anchors: anchors,
                selectedID: selectedID,
                celebratesFound: false
            )
            self.phase = displayPhase
        } else {
            displayPhase = phase
        }
        let contentBounds: CGRect
        switch displayPhase {
        case let .invoked(point), let .noMatch(point): contentBounds = CGRect(origin: point, size: .zero)
        case let .recognized(anchors, _): contentBounds = anchors.map(\.bounds).reduce(CGRect.null) { $0.union($1) }
        case let .resolved(anchor): contentBounds = anchor.bounds
        case let .lookup(anchors, _, _): contentBounds = anchors.map(\.bounds).reduce(CGRect.null) { $0.union($1) }
        }
        guard let frame = panelFrame(around: contentBounds) else {
            cancel()
            return
        }
        panel.contentView = NSHostingView(rootView: ScanFeedbackView(
            phase: displayPhase,
            panelFrame: frame,
            reduceMotion: reduceMotion
        ))
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

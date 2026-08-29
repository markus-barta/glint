import AppKit
import CoreGraphics
import Vision

/// Describes the captured Quartz rectangle and the display coordinate spaces it
/// belongs to. Quartz uses a top-left global origin while AppKit uses a
/// bottom-left global origin; keeping both display frames makes conversion
/// deterministic even when a display has a negative origin.
struct CapturePlan: Sendable {
    let rect: CGRect
    let displayBounds: CGRect
    let screenFrame: CGRect
    let focus: CGPoint

    init(rect: CGRect, displayBounds: CGRect, screenFrame: CGRect, focus: CGPoint? = nil) {
        self.rect = rect
        self.displayBounds = displayBounds
        self.screenFrame = screenFrame
        self.focus = focus ?? CGPoint(x: rect.midX, y: rect.midY)
    }

    @MainActor
    static func around(_ mouse: CGPoint, size: CGSize = CGSize(width: 620, height: 240)) -> CapturePlan? {
        guard let screen = screen(containing: mouse),
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        let displayBounds = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
        let quartzFocus = CGPoint(
            x: displayBounds.minX + mouse.x - screen.frame.minX,
            y: displayBounds.minY + screen.frame.maxY - mouse.y
        )
        let proposed = CGRect(
            x: quartzFocus.x - size.width / 2,
            y: quartzFocus.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        let bounded = proposed.intersection(displayBounds)
        guard bounded.width > 20, bounded.height > 20 else { return nil }
        return CapturePlan(rect: bounded, displayBounds: displayBounds, screenFrame: screen.frame, focus: quartzFocus)
    }

    /// Converts a Vision normalized bounding box (bottom-left image origin) to
    /// the Quartz global coordinate space used by CGWindowListCreateImage.
    func quartzRect(forVisionNormalized normalized: CGRect) -> CGRect {
        let normalized = normalized.standardized
        return CGRect(
            x: rect.minX + normalized.minX * rect.width,
            y: rect.maxY - normalized.maxY * rect.height,
            width: normalized.width * rect.width,
            height: normalized.height * rect.height
        ).standardized
    }

    /// Converts a Quartz global rectangle to AppKit's global screen space.
    func appKitRect(forQuartz quartzRect: CGRect) -> CGRect {
        Self.appKitRect(quartzRect: quartzRect, displayBounds: displayBounds, screenFrame: screenFrame)
    }

    func appKitRect(forVisionNormalized normalized: CGRect) -> CGRect {
        appKitRect(forQuartz: quartzRect(forVisionNormalized: normalized))
    }

    static func appKitRect(quartzRect: CGRect, displayBounds: CGRect, screenFrame: CGRect) -> CGRect {
        let quartzRect = quartzRect.standardized
        return CGRect(
            x: screenFrame.minX + quartzRect.minX - displayBounds.minX,
            y: screenFrame.maxY - (quartzRect.maxY - displayBounds.minY),
            width: quartzRect.width,
            height: quartzRect.height
        ).standardized
    }

    /// Normalized point used to keep the existing nearest-to-pointer ordering
    /// correct when the crop is clipped by a screen edge.
    var normalizedFocus: CGPoint {
        guard rect.width > 0, rect.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(
            x: (focus.x - rect.minX) / rect.width,
            y: (rect.maxY - focus.y) / rect.height
        )
    }

    @MainActor
    private static func screen(containing point: CGPoint) -> NSScreen? {
        if let exact = NSScreen.screens.first(where: { $0.frame.contains(point) }) { return exact }
        // CGRect excludes its maximum edge. A tiny expansion avoids losing a
        // hotkey invocation exactly on the seam between two displays.
        return NSScreen.screens.first(where: { $0.frame.insetBy(dx: -0.5, dy: -0.5).contains(point) })
    }
}

struct RecognizedTextSpan: Hashable, Sendable {
    let literal: String
    let utf16Range: NSRange
    let normalizedBounds: CGRect
    let screenBounds: CGRect
}

/// A Vision result with its confidence and geometry preserved after the
/// request finishes. `spans` contains exact boxes for identifier-like pieces,
/// while `screenBounds(for:)` falls back to the full observation when needed.
struct RecognizedTextFragment: Hashable, Sendable {
    let text: String
    let confidence: Float
    let normalizedBounds: CGRect
    let screenBounds: CGRect
    let spans: [RecognizedTextSpan]

    func screenBounds(for literal: String, occurrence: Int = 0) -> CGRect? {
        guard occurrence >= 0 else { return nil }
        let matching = spans.filter { $0.literal.caseInsensitiveCompare(literal) == .orderedSame }
        if matching.indices.contains(occurrence) { return matching[occurrence].screenBounds }

        // Vision occasionally inserts or removes surrounding punctuation. A
        // contained span is still more truthful than highlighting the line.
        if let contained = spans.first(where: {
            $0.literal.range(of: literal, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }) {
            return contained.screenBounds
        }
        return text.range(of: literal, options: [.caseInsensitive, .diacriticInsensitive]) == nil ? nil : screenBounds
    }

    func screenBounds(forUTF16Range range: NSRange, literal: String) -> CGRect? {
        if let exact = spans.first(where: {
            $0.utf16Range == range && $0.literal.caseInsensitiveCompare(literal) == .orderedSame
        }) {
            return exact.screenBounds
        }
        return screenBounds(for: literal)
    }
}

actor ScreenOCR {
    /// Compatibility API used by the current resolver pipeline.
    func recognize(plan: CapturePlan) -> [String] {
        performRecognition(plan: plan, preservingIdentifierGeometry: false).map(\.text)
    }

    /// Geometry-preserving API for anchored scan feedback.
    func recognizeFragments(plan: CapturePlan) -> [RecognizedTextFragment] {
        performRecognition(plan: plan, preservingIdentifierGeometry: true)
    }

    private func performRecognition(
        plan: CapturePlan,
        preservingIdentifierGeometry: Bool
    ) -> [RecognizedTextFragment] {
        guard let image = CGWindowListCreateImage(
            plan.rect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.boundsIgnoreFraming, .bestResolution]
        ) else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US", "de-DE"]
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.018
        do { try VNImageRequestHandler(cgImage: image).perform([request]) } catch { return [] }

        let focus = plan.normalizedFocus
        return (request.results ?? []).compactMap { observation -> (RecognizedTextFragment, CGFloat)? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let normalizedBounds = observation.boundingBox.standardized
            let fragment = RecognizedTextFragment(
                text: candidate.string,
                confidence: candidate.confidence,
                normalizedBounds: normalizedBounds,
                screenBounds: plan.appKitRect(forVisionNormalized: normalizedBounds),
                spans: preservingIdentifierGeometry ? identifierSpans(in: candidate, plan: plan) : []
            )
            let distance = hypot(normalizedBounds.midX - focus.x, normalizedBounds.midY - focus.y)
            return (fragment, distance)
        }
        .sorted { $0.1 < $1.1 }
        .map(\.0)
    }

    private func identifierSpans(in candidate: VNRecognizedText, plan: CapturePlan) -> [RecognizedTextSpan] {
        let string = candidate.string
        let nsString = string as NSString
        // This deliberately recognizes shapes rather than projects/sources.
        // Project inference remains the resolver's responsibility.
        let pattern = #"[A-Za-z][A-Za-z0-9]{1,31}-[0-9]+|#[0-9]+|[0-9]+(?:\.[0-9]+){2,}|[0-9]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        var occupied: [NSRange] = []
        var spans: [RecognizedTextSpan] = []
        for match in regex.matches(in: string, range: NSRange(location: 0, length: nsString.length)) {
            guard !occupied.contains(where: { NSIntersectionRange($0, match.range).length > 0 }),
                  let swiftRange = Range(match.range, in: string),
                  let box = try? candidate.boundingBox(for: swiftRange) else { continue }
            let normalizedBounds = box.boundingBox.standardized
            spans.append(RecognizedTextSpan(
                literal: nsString.substring(with: match.range),
                utf16Range: match.range,
                normalizedBounds: normalizedBounds,
                screenBounds: plan.appKitRect(forVisionNormalized: normalizedBounds)
            ))
            occupied.append(match.range)
        }
        return spans
    }
}

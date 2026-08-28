import AppKit
import CoreGraphics
import Vision

struct CapturePlan {
    let rect: CGRect
    @MainActor static func around(_ mouse: CGPoint, size: CGSize = CGSize(width: 620, height: 240)) -> CapturePlan? {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }),
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        let bounds = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
        let center = CGPoint(x: bounds.minX + mouse.x - screen.frame.minX, y: bounds.minY + screen.frame.maxY - mouse.y)
        let proposed = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        let bounded = proposed.intersection(bounds)
        return bounded.width > 20 && bounded.height > 20 ? CapturePlan(rect: bounded) : nil
    }
}

actor ScreenOCR {
    func recognize(plan: CapturePlan) -> [String] {
        guard let image = CGWindowListCreateImage(plan.rect, .optionOnScreenOnly, kCGNullWindowID, [.boundsIgnoreFraming, .bestResolution]) else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US", "de-DE"]
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.018
        do { try VNImageRequestHandler(cgImage: image).perform([request]) } catch { return [] }
        return (request.results ?? []).compactMap { observation -> (String, CGFloat)? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return (text, hypot(observation.boundingBox.midX - 0.5, observation.boundingBox.midY - 0.5))
        }.sorted { $0.1 < $1.1 }.map(\.0)
    }
}

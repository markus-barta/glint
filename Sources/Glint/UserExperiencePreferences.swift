import AppKit
import Foundation

enum HoverActivationMode: String, CaseIterable, Identifiable, Codable {
    case off
    case dwell
    case hold
    case continuous

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .dwell: return "After dwell"
        case .hold: return "While holding"
        case .continuous: return "Continuously"
        }
    }

    var subtitle: String {
        switch self {
        case .off: return "Only scan when you use the Inspect shortcut."
        case .dwell: return "Scan after the pointer rests over a ticket."
        case .hold: return "Scan while your chosen modifier keys are held."
        case .continuous: return "Follow tickets beneath the pointer automatically."
        }
    }
}

enum ContinuousResponsiveness: String, CaseIterable, Identifiable, Codable {
    case calm
    case balanced
    case fast

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var interval: TimeInterval {
        switch self {
        case .calm: return 1.0
        case .balanced: return 0.65
        case .fast: return 0.35
        }
    }
    var detail: String {
        switch self {
        case .calm: return "1.0 s"
        case .balanced: return "0.65 s"
        case .fast: return "0.35 s"
        }
    }
}

struct ActivationPreferences: Equatable {
    static let dwellRange = 150...1500
    static let defaults = ActivationPreferences(
        mode: .dwell,
        dwellMilliseconds: 300,
        holdModifiers: [.option],
        responsiveness: .balanced,
        scanFeedbackEnabled: true
    )

    var mode: HoverActivationMode
    var dwellMilliseconds: Int
    var holdModifiers: HotKeyModifiers
    var responsiveness: ContinuousResponsiveness
    var scanFeedbackEnabled: Bool

    var dwellSeconds: TimeInterval { TimeInterval(dwellMilliseconds) / 1_000 }
    var scanInterval: TimeInterval { responsiveness.interval }

    /// Compatibility hook while the coordinator migrates to `mode` directly.
    var legacyTriggerMode: TriggerMode {
        switch mode {
        case .dwell, .off: return .dwell
        case .hold: return .option
        case .continuous: return .always
        }
    }

    func effectiveSummary(inspectHotKey: HotKey?) -> String {
        let manual = inspectHotKey.map { "Press \($0.label) anytime" } ?? "Set an Inspect shortcut to scan on demand"
        switch mode {
        case .off:
            return manual + "."
        case .dwell:
            return manual + ", or pause for \(dwellMilliseconds) ms over a ticket."
        case .hold:
            return manual + ", or hold \(holdModifiers.readableName) while pointing."
        case .continuous:
            return manual + "; GLINT also follows the pointer every \(responsiveness.detail)."
        }
    }

    static func load(defaults: UserDefaults = .standard) -> ActivationPreferences {
        let prefix = "activation."
        if defaults.object(forKey: prefix + "mode") == nil {
            let legacy = TriggerMode(rawValue: defaults.string(forKey: "triggerMode") ?? "dwell") ?? .dwell
            let migratedMode: HoverActivationMode
            switch legacy {
            case .dwell: migratedMode = .dwell
            case .option: migratedMode = .hold
            case .always: migratedMode = .continuous
            }
            var migrated = ActivationPreferences.defaults
            migrated.mode = migratedMode
            migrated.persist(defaults: defaults)
            return migrated
        }
        var value = ActivationPreferences(
            mode: HoverActivationMode(rawValue: defaults.string(forKey: prefix + "mode") ?? "hold") ?? .hold,
            dwellMilliseconds: defaults.integer(forKey: prefix + "dwellMilliseconds"),
            holdModifiers: HotKeyModifiers(rawValue: UInt32(defaults.integer(forKey: prefix + "holdModifiers"))),
            responsiveness: ContinuousResponsiveness(rawValue: defaults.string(forKey: prefix + "responsiveness") ?? "balanced") ?? .balanced,
            scanFeedbackEnabled: defaults.object(forKey: prefix + "scanFeedbackEnabled") == nil ? true : defaults.bool(forKey: prefix + "scanFeedbackEnabled")
        )
        value.dwellMilliseconds = min(max(value.dwellMilliseconds == 0 ? 300 : value.dwellMilliseconds, dwellRange.lowerBound), dwellRange.upperBound)
        if value.holdModifiers.isEmpty { value.holdModifiers = [.option] }
        return value
    }

    func persist(defaults: UserDefaults = .standard) {
        let prefix = "activation."
        defaults.set(mode.rawValue, forKey: prefix + "mode")
        defaults.set(dwellMilliseconds, forKey: prefix + "dwellMilliseconds")
        defaults.set(Int(holdModifiers.rawValue), forKey: prefix + "holdModifiers")
        defaults.set(responsiveness.rawValue, forKey: prefix + "responsiveness")
        defaults.set(scanFeedbackEnabled, forKey: prefix + "scanFeedbackEnabled")
        defaults.set(legacyTriggerMode.rawValue, forKey: "triggerMode")
    }
}

extension HotKeyModifiers {
    var readableName: String {
        var names: [String] = []
        if contains(.control) { names.append("Control") }
        if contains(.option) { names.append("Option") }
        if contains(.shift) { names.append("Shift") }
        if contains(.command) { names.append("Command") }
        return names.isEmpty ? "a modifier" : names.joined(separator: " + ")
    }
}

enum CardTextSize: String, CaseIterable, Identifiable, Codable {
    case small, standard, large, extraLarge
    var id: String { rawValue }
    var title: String {
        switch self { case .small: return "Small"; case .standard: return "Standard"; case .large: return "Large"; case .extraLarge: return "Extra Large" }
    }
    var scale: CGFloat {
        switch self { case .small: return 0.88; case .standard: return 1; case .large: return 1.14; case .extraLarge: return 1.28 }
    }
}

enum CardWidth: String, CaseIterable, Identifiable, Codable {
    case compact, standard, wide
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var points: CGFloat { switch self { case .compact: return 480; case .standard: return 590; case .wide: return 700 } }
}

enum CardDensity: String, CaseIterable, Identifiable, Codable {
    case compact, comfortable, detailed
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var showsDetail: Bool { self != .compact }
    var showsMetadata: Bool { self == .detailed }
    var detailLines: Int { switch self { case .compact: return 0; case .comfortable: return 2; case .detailed: return 4 } }
    var verticalPadding: CGFloat { switch self { case .compact: return 10; case .comfortable: return 14; case .detailed: return 16 } }
}

enum CardSurface: String, CaseIterable, Identifiable, Codable {
    case system, solid
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct PresentationPreferences: Equatable {
    static let defaults = PresentationPreferences(alternativePreviews: 2, textSize: .standard, width: .standard, density: .comfortable, surface: .system)

    var alternativePreviews: Int
    var textSize: CardTextSize
    var width: CardWidth
    var density: CardDensity
    var surface: CardSurface

    static func load(defaults: UserDefaults = .standard) -> PresentationPreferences {
        let prefix = "presentation."
        let previews = defaults.object(forKey: prefix + "alternativePreviews") == nil ? 2 : defaults.integer(forKey: prefix + "alternativePreviews")
        return PresentationPreferences(
            alternativePreviews: min(max(previews, 0), 5),
            textSize: CardTextSize(rawValue: defaults.string(forKey: prefix + "textSize") ?? "standard") ?? .standard,
            width: CardWidth(rawValue: defaults.string(forKey: prefix + "width") ?? "standard") ?? .standard,
            density: CardDensity(rawValue: defaults.string(forKey: prefix + "density") ?? "comfortable") ?? .comfortable,
            surface: CardSurface(rawValue: defaults.string(forKey: prefix + "surface") ?? "system") ?? .system
        )
    }

    func persist(defaults: UserDefaults = .standard) {
        let prefix = "presentation."
        defaults.set(min(max(alternativePreviews, 0), 5), forKey: prefix + "alternativePreviews")
        defaults.set(textSize.rawValue, forKey: prefix + "textSize")
        defaults.set(width.rawValue, forKey: prefix + "width")
        defaults.set(density.rawValue, forKey: prefix + "density")
        defaults.set(surface.rawValue, forKey: prefix + "surface")
        NotificationCenter.default.post(name: .glintPresentationPreferencesDidChange, object: nil)
    }

    func circularAlternativeIndices(count: Int, selectedIndex: Int) -> [Int] {
        guard count > 1, alternativePreviews > 0 else { return [] }
        let limit = min(alternativePreviews, count - 1)
        let selected = ((selectedIndex % count) + count) % count
        return (1...limit).map { (selected + $0) % count }
    }
}

extension Notification.Name {
    static let glintPresentationPreferencesDidChange = Notification.Name("glint.presentationPreferencesDidChange")
}

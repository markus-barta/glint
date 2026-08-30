import AppKit
import Foundation

private enum LegacyActivationMode: String {
    case off, dwell, option
}

enum HoverActivationMode: String, CaseIterable, Identifiable, Codable {
    case off
    case toggleHover
    case pressToScan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .toggleHover: return "Toggle Hover"
        case .pressToScan: return "Press to Scan"
        }
    }

    var subtitle: String {
        switch self {
        case .off: return "The activation shortcut does nothing."
        case .toggleHover: return "Press the shortcut to turn hover scanning on or off. Each new pointer location scans once."
        case .pressToScan: return "Press the shortcut for one scan beneath the pointer."
        }
    }
}

enum ActivationShortcutAction: Equatable {
    case none
    case toggleHover
    case scanOnce
}

enum ActivationShortcutPolicy {
    static func action(for mode: HoverActivationMode) -> ActivationShortcutAction {
        switch mode {
        case .off: return .none
        case .toggleHover: return .toggleHover
        case .pressToScan: return .scanOnce
        }
    }
}

enum HoverMenuBarState: Equatable {
    case inactive
    case active
    case matchFound

    static func resolve(mode: HoverActivationMode, hoverEnabled: Bool, matchFound: Bool) -> HoverMenuBarState {
        guard mode == .toggleHover, hoverEnabled else { return .inactive }
        return matchFound ? .matchFound : .active
    }
}

struct ActivationPreferences: Equatable {
    static let hoverSettleDuration: TimeInterval = 0.3
    static let defaults = ActivationPreferences(
        mode: .pressToScan,
        scanFeedbackEnabled: true
    )

    var mode: HoverActivationMode
    var scanFeedbackEnabled: Bool

    /// Downgrade compatibility for builds that still read `triggerMode`.
    private var legacyMode: LegacyActivationMode {
        switch mode {
        case .off: return .off
        case .toggleHover: return .dwell
        case .pressToScan: return .option
        }
    }

    static func load(defaults: UserDefaults = .standard) -> ActivationPreferences {
        let prefix = "activation."
        let storedMode = defaults.string(forKey: prefix + "mode")
            ?? defaults.string(forKey: "triggerMode")
        let value = ActivationPreferences(
            mode: migratedMode(from: storedMode),
            scanFeedbackEnabled: defaults.object(forKey: prefix + "scanFeedbackEnabled") == nil ? true : defaults.bool(forKey: prefix + "scanFeedbackEnabled")
        )
        value.persist(defaults: defaults)
        return value
    }

    static func migratedMode(from rawValue: String?) -> HoverActivationMode {
        switch rawValue {
        case HoverActivationMode.off.rawValue:
            return .off
        case HoverActivationMode.toggleHover.rawValue, "dwell", "continuous", "always":
            return .toggleHover
        case HoverActivationMode.pressToScan.rawValue, "hold", "option":
            return .pressToScan
        default:
            return Self.defaults.mode
        }
    }

    func persist(defaults: UserDefaults = .standard) {
        let prefix = "activation."
        defaults.set(mode.rawValue, forKey: prefix + "mode")
        defaults.set(scanFeedbackEnabled, forKey: prefix + "scanFeedbackEnabled")
        defaults.set(legacyMode.rawValue, forKey: "triggerMode")
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
        NotificationCenter.default.post(name: .nuncidPresentationPreferencesDidChange, object: nil)
    }

    func circularAlternativeIndices(count: Int, selectedIndex: Int) -> [Int] {
        guard count > 1, alternativePreviews > 0 else { return [] }
        let limit = min(alternativePreviews, count - 1)
        let selected = ((selectedIndex % count) + count) % count
        return (1...limit).map { (selected + $0) % count }
    }
}

enum AppearanceResetPolicy {
    static func shouldKeepUndo(previous: PresentationPreferences?, current: PresentationPreferences) -> Bool {
        guard let previous, previous != .defaults else { return false }
        return current == .defaults
    }
}

enum PreferenceFeedbackSeverity: Equatable {
    case success
    case problem
}

struct PreferenceFeedback: Equatable {
    let message: String
    let severity: PreferenceFeedbackSeverity

    static func success(_ message: String) -> PreferenceFeedback { PreferenceFeedback(message: message, severity: .success) }
    static func problem(_ message: String) -> PreferenceFeedback { PreferenceFeedback(message: message, severity: .problem) }

    /// Global registration failures always win over a local success message.
    static func resolved(local: PreferenceFeedback?, globalError: String?) -> PreferenceFeedback? {
        if let globalError { return .problem(globalError) }
        return local
    }
}

extension Notification.Name {
    static let nuncidPresentationPreferencesDidChange = Notification.Name("nuncid.presentationPreferencesDidChange")
}

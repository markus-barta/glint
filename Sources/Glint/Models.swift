import Foundation

enum Tracker: String, Codable, CaseIterable {
    case ppm
    case pma
    var other: Tracker { self == .ppm ? .pma : .ppm }
}

enum TriggerMode: String, CaseIterable, Identifiable {
    case dwell, option, always
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dwell: return "Dwell (300 ms)"
        case .option: return "Hold Option"
        case .always: return "Always follow"
        }
    }
}

enum StickyModifier: String, CaseIterable, Identifiable {
    case option, control, command, shift

    var id: String { rawValue }
    var label: String {
        switch self {
        case .option: return "Option"
        case .control: return "Control"
        case .command: return "Command"
        case .shift: return "Shift"
        }
    }
    var symbol: String {
        switch self {
        case .option: return "⌥"
        case .control: return "⌃"
        case .command: return "⌘"
        case .shift: return "⇧"
        }
    }
}

struct GlintPreferences: Equatable {
    var triggerMode: TriggerMode
    var stickyModifier: StickyModifier
    var stickyDoublePressInterval: Double

    static let defaultStickyDoublePressInterval = 0.40

    static func load(defaults: UserDefaults = .standard) -> GlintPreferences {
        let storedInterval = defaults.object(forKey: "stickyDoublePressInterval") as? Double
        return GlintPreferences(
            triggerMode: TriggerMode(rawValue: defaults.string(forKey: "triggerMode") ?? "dwell") ?? .dwell,
            stickyModifier: StickyModifier(rawValue: defaults.string(forKey: "stickyModifier") ?? "option") ?? .option,
            stickyDoublePressInterval: min(max(storedInterval ?? defaultStickyDoublePressInterval, 0.20), 0.80)
        )
    }
}

struct RapidPressDetector {
    private(set) var previousPressAt: Date?

    mutating func registerPress(at date: Date = Date(), maximumInterval: TimeInterval) -> Bool {
        guard let previousPressAt, date.timeIntervalSince(previousPressAt) <= maximumInterval else {
            self.previousPressAt = date
            return false
        }
        self.previousPressAt = nil
        return true
    }

    mutating func reset() { previousPressAt = nil }
}

struct GlintLine: Codable, Hashable, Identifiable {
    let id: String
    let key: String
    let state: String
    let title: String
    let source: String
    let metadata: String
    let detail: String

    init(key: String, state: String, title: String, source: String, metadata: String = "", detail: String = "") {
        self.id = "\(source):\(key)"
        self.key = key
        self.state = state
        self.title = title
        self.source = source
        self.metadata = metadata
        self.detail = detail
    }
}

enum HoverResultPolicy {
    static let maximumResults = 12

    static func visible(from attempts: [GlintLine?], limit: Int = maximumResults) -> [GlintLine] {
        var seen = Set<String>()
        return attempts.compactMap { $0 }
            .filter { !$0.key.isEmpty && seen.insert($0.id).inserted }
            .prefix(max(0, limit))
            .map { $0 }
    }
}

struct ResolutionContext: Equatable {
    var lastSeenTracker: Tracker
    var ppmProject: String
    var pmaProject: String

    static func load(defaults: UserDefaults = .standard) -> ResolutionContext {
        ResolutionContext(
            lastSeenTracker: Tracker(rawValue: defaults.string(forKey: "lastSeenTracker") ?? "ppm") ?? .ppm,
            ppmProject: defaults.string(forKey: "lastPPMProject") ?? "PAI",
            pmaProject: defaults.string(forKey: "lastPMAProject") ?? "START"
        )
    }

    func project(for tracker: Tracker) -> String { tracker == .ppm ? ppmProject : pmaProject }

    mutating func saw(project: String, on tracker: Tracker, defaults: UserDefaults = .standard) {
        lastSeenTracker = tracker
        if tracker == .ppm { ppmProject = project } else { pmaProject = project }
        defaults.set(tracker.rawValue, forKey: "lastSeenTracker")
        defaults.set(ppmProject, forKey: "lastPPMProject")
        defaults.set(pmaProject, forKey: "lastPMAProject")
    }
}

enum CandidateSpec: Hashable {
    case issue(tracker: Tracker, key: String)
    case pullRequest(number: Int, repo: String)
    var cacheKey: String {
        switch self {
        case let .issue(tracker, key): return "issue:\(tracker.rawValue):\(key)"
        case let .pullRequest(number, repo): return "pr:\(repo):\(number)"
        }
    }
}

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

struct GlintLine: Codable, Hashable, Identifiable {
    let id: String
    let key: String
    let state: String
    let title: String
    let source: String

    init(key: String, state: String, title: String, source: String) {
        self.id = "\(source):\(key)"
        self.key = key
        self.state = state
        self.title = title
        self.source = source
    }

    static func miss(_ raw: String) -> GlintLine {
        GlintLine(key: "", state: "", title: "maybe just \(raw)", source: "miss:\(raw)")
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

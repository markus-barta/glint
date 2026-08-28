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

struct HotKeyModifiers: OptionSet, Codable, Hashable {
    let rawValue: UInt32

    static let command = HotKeyModifiers(rawValue: 1 << 0)
    static let option = HotKeyModifiers(rawValue: 1 << 1)
    static let control = HotKeyModifiers(rawValue: 1 << 2)
    static let shift = HotKeyModifiers(rawValue: 1 << 3)

    var label: String {
        var value = ""
        if contains(.control) { value += "⌃" }
        if contains(.option) { value += "⌥" }
        if contains(.shift) { value += "⇧" }
        if contains(.command) { value += "⌘" }
        return value
    }
}

struct HotKey: Codable, Hashable {
    let keyCode: UInt32
    let modifiers: HotKeyModifiers
    let keyLabel: String

    static let inspect = HotKey(keyCode: 49, modifiers: [.option], keyLabel: "Space")
    static let pin = HotKey(keyCode: 49, modifiers: [.option, .shift], keyLabel: "Space")

    var label: String { modifiers.label + keyLabel }

    var isSafeGlobalShortcut: Bool {
        let functionKeys: Set<UInt32> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        return functionKeys.contains(keyCode) || !modifiers.intersection([.command, .option, .control]).isEmpty
    }
}

struct GlintPreferences: Equatable {
    var triggerMode: TriggerMode
    var inspectHotKey: HotKey?
    var pinHotKey: HotKey?

    static func load(defaults: UserDefaults = .standard) -> GlintPreferences {
        return GlintPreferences(
            triggerMode: TriggerMode(rawValue: defaults.string(forKey: "triggerMode") ?? "dwell") ?? .dwell,
            inspectHotKey: decodeHotKey(key: "inspectHotKey", fallback: .inspect, defaults: defaults),
            pinHotKey: decodeHotKey(key: "pinHotKey", fallback: .pin, defaults: defaults)
        )
    }

    static func save(_ hotKey: HotKey?, key: String, defaults: UserDefaults = .standard) {
        if let hotKey, let data = try? JSONEncoder().encode(hotKey) {
            defaults.set(data, forKey: key)
        } else {
            defaults.set(Data(), forKey: key)
        }
    }

    private static func decodeHotKey(key: String, fallback: HotKey, defaults: UserDefaults) -> HotKey? {
        guard defaults.object(forKey: key) != nil else { return fallback }
        guard let data = defaults.data(forKey: key), !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(HotKey.self, from: data)
    }
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

enum PinnedInputEvent {
    case digits(String)
    case letters(String)
    case backspace
    case submit
    case escape
    case paste(String)
}

struct ProjectDescriptor: Hashable, Identifiable {
    let key: String
    let name: String
    let aliases: [String]
    let tracker: Tracker
    var id: String { key }

    static let known: [ProjectDescriptor] = [
        .init(key: "GLINT", name: "Glint", aliases: ["glint", "ticket lens"], tracker: .ppm),
        .init(key: "HAUSV", name: "Hausverwaltung", aliases: ["hausv", "hausverwaltung"], tracker: .ppm),
        .init(key: "INSPR", name: "Inspr", aliases: ["inspr", "inspire"], tracker: .ppm),
        .init(key: "JANUS", name: "Janus", aliases: ["janus"], tracker: .ppm),
        .init(key: "PAI", name: "Paimos", aliases: ["pai", "paimos", "ppm"], tracker: .ppm),
        .init(key: "PHAROS", name: "Pharos", aliases: ["pharos", "pharos crm"], tracker: .ppm),
        .init(key: "START", name: "Start AGM", aliases: ["start", "start agm"], tracker: .pma),
    ]
}

enum ProjectMatcher {
    static func bestMatch(for rawQuery: String, projects: [ProjectDescriptor] = ProjectDescriptor.known, current: String? = nil) -> ProjectDescriptor? {
        let query = normalize(rawQuery)
        guard !query.isEmpty else { return projects.first(where: { $0.key == current }) ?? projects.first }
        return projects.max { lhs, rhs in
            score(lhs, query: query, current: current) < score(rhs, query: query, current: current)
        }
    }

    private static func score(_ project: ProjectDescriptor, query: String, current: String?) -> Int {
        let terms = ([project.key, project.name] + project.aliases).map(normalize)
        var best = Int.min
        for term in terms {
            let distance = damerauLevenshtein(query, term)
            var value = max(0, 1_000 - distance * 85 - abs(term.count - query.count) * 8)
            if term == query { value += 10_000 }
            else if term.hasPrefix(query) { value += 5_000 - (term.count - query.count) * 10 }
            else if isSubsequence(query, of: term) { value += 2_000 }
            best = max(best, value)
        }
        if project.key == current { best += 5 }
        return best
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .filter(\.isLetter)
            .lowercased()
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var remainder = needle[...]
        for character in haystack where !remainder.isEmpty && character == remainder.first { remainder.removeFirst() }
        return remainder.isEmpty
    }

    static func damerauLevenshtein(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs), b = Array(rhs)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var matrix = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { matrix[i][0] = i }
        for j in 0...b.count { matrix[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let substitution = a[i - 1] == b[j - 1] ? 0 : 1
                matrix[i][j] = min(matrix[i - 1][j] + 1, matrix[i][j - 1] + 1, matrix[i - 1][j - 1] + substitution)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    matrix[i][j] = min(matrix[i][j], matrix[i - 2][j - 2] + 1)
                }
            }
        }
        return matrix[a.count][b.count]
    }
}

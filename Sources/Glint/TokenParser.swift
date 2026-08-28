import Foundation

struct NearbyToken: Hashable {
    enum Kind: Hashable {
        case issueKey(project: String, number: Int)
        case hashNumber(Int)
        case bareNumber(Int)
        case version
    }
    let raw: String
    let kind: Kind
    let sourceOrder: Int
}

enum TokenParser {
    private static let keyPattern = #"\b([A-Z][A-Z0-9]{1,11})-([0-9]+)\b"#
    private static let hashPattern = #"(?<![A-Z0-9])#([0-9]+)\b"#
    private static let versionPattern = #"\b[0-9]+\.[0-9]+(?:\.[0-9]+)+\b"#
    private static let barePattern = #"(?<![A-Z0-9#.-])\b[0-9]+\b(?![.-])"#

    static func parse(_ strings: [String]) -> [NearbyToken] {
        var result: [NearbyToken] = []
        for (stringIndex, string) in strings.enumerated() {
            let ns = string as NSString
            var occupied: [NSRange] = []
            func add(_ pattern: String, _ make: (NSTextCheckingResult, String) -> NearbyToken.Kind?) {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
                for match in regex.matches(in: string, range: NSRange(location: 0, length: ns.length)) {
                    guard !occupied.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else { continue }
                    let raw = ns.substring(with: match.range)
                    guard let kind = make(match, raw) else { continue }
                    result.append(NearbyToken(
                        raw: raw,
                        kind: kind,
                        sourceOrder: stringIndex * 1_000_000 + match.range.location
                    ))
                    occupied.append(match.range)
                }
            }
            add(keyPattern) { match, _ in
                guard let n = Int(ns.substring(with: match.range(at: 2))) else { return nil }
                return .issueKey(project: ns.substring(with: match.range(at: 1)), number: n)
            }
            add(hashPattern) { match, _ in Int(ns.substring(with: match.range(at: 1))).map(NearbyToken.Kind.hashNumber) }
            add(versionPattern) { _, _ in .version }
            add(barePattern) { _, raw in Int(raw).map(NearbyToken.Kind.bareNumber) }
        }
        var seen = Set<String>()
        return result.sorted { $0.sourceOrder < $1.sourceOrder }
            .filter { seen.insert("\($0.kind):\($0.raw)").inserted }
    }
}

enum CandidatePlanner {
    static let ppmProjects: Set<String> = ["GLINT", "HAUSV", "JANUS", "PHAROS", "PAI", "INSPR"]
    static let pmaProjects: Set<String> = ["START"]

    static func tracker(for project: String, context: ResolutionContext) -> Tracker {
        if pmaProjects.contains(project) { return .pma }
        if ppmProjects.contains(project) { return .ppm }
        return context.lastSeenTracker
    }

    static func candidates(for token: NearbyToken, context: ResolutionContext) -> [CandidateSpec] {
        switch token.kind {
        case let .issueKey(project, number):
            let key = "\(project)-\(number)"
            let primary = tracker(for: project, context: context)
            if ppmProjects.contains(project) || pmaProjects.contains(project) { return [.issue(tracker: primary, key: key)] }
            return [.issue(tracker: primary, key: key), .issue(tracker: primary.other, key: key)]
        case let .hashNumber(number), let .bareNumber(number):
            let first = context.lastSeenTracker
            let second = first.other
            let firstProject = context.project(for: first)
            let secondProject = context.project(for: second)
            var candidates: [CandidateSpec] = [
                .issue(tracker: first, key: "\(firstProject)-\(number)"),
                .issue(tracker: second, key: "\(secondProject)-\(number)"),
            ]
            if let repo = repo(for: firstProject) {
                candidates.append(.pullRequest(number: number, repo: repo))
            }
            return candidates
        case .version: return []
        }
    }

    static func repo(for project: String) -> String? {
        switch project {
        case "PAI": return "inspr-at/paimos"
        case "HAUSV": return "inspr-at/hausv-org"
        case "PHAROS": return "inspr-at/pharos"
        case "JANUS": return "inspr-at/janus"
        case "START": return "augmentoring-team/start-agm-com"
        case "INSPR": return "inspr-at/inspr"
        default: return nil
        }
    }
}

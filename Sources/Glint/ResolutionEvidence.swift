import AppKit
import CoreGraphics
import Foundation

struct ForegroundApplicationContext: Hashable, Sendable {
    let bundleIdentifier: String?
    let applicationName: String?
    let windowTitle: String?

    /// Uses only the frontmost process and the title already exposed by CoreGraphics. It never
    /// asks for Accessibility access and deliberately returns nil when the title is unavailable.
    static func capture() -> ForegroundApplicationContext? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        let windowTitle = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]])?
            .first(where: {
                ($0[kCGWindowOwnerPID as String] as? pid_t) == pid &&
                ($0[kCGWindowLayer as String] as? Int) == 0
            })?[kCGWindowName as String] as? String
        return ForegroundApplicationContext(
            bundleIdentifier: app.bundleIdentifier,
            applicationName: app.localizedName,
            windowTitle: windowTitle?.isEmpty == false ? windowTitle : nil
        )
    }
}

enum EvidenceStrength: Int, Hashable, Sendable {
    case fallback
    case weak
    case strong
    case decisive
}

struct ResolutionReason: Hashable, Sendable {
    let code: String
    let label: String
    let weight: Int
    let strength: EvidenceStrength
}

enum ResolutionLearningEligibility: Int, Hashable, Sendable {
    case never
    case userConfirmation
    case strongContext
    case explicit
}

struct CandidateProposal: Hashable, Sendable {
    let spec: CandidateSpec
    let score: Int
    let reasons: [ResolutionReason]
    let sourceOrder: Int
    let inferredProject: String?
    let learningEligibility: ResolutionLearningEligibility

    var provenanceSummary: String {
        reasons.sorted {
            if $0.weight != $1.weight { return $0.weight > $1.weight }
            return $0.code < $1.code
        }.map(\.label).joined(separator: " · ")
    }
}

struct ResolutionPlan: Hashable, Sendable {
    static let closeScoreThreshold = 120
    // Keep enough evidence-ranked collision alternatives for the pinned navigator;
    // TicketResolver still runs no more than four external lookups concurrently.
    static let maximumCandidates = 16

    let proposals: [CandidateProposal]

    var isAmbiguous: Bool {
        guard proposals.count > 1 else { return false }
        return proposals[0].score - proposals[1].score <= Self.closeScoreThreshold
    }

    func learningDecision(for selected: CandidateProposal, userConfirmed: Bool = false) -> ResolutionLearningDecision? {
        if userConfirmed { return ResolutionLearningDecision(proposal: selected, basis: .userConfirmed) }
        guard proposals.first?.spec == selected.spec else { return nil }
        switch selected.learningEligibility {
        case .explicit:
            return ResolutionLearningDecision(proposal: selected, basis: .explicit)
        case .strongContext where !isAmbiguous:
            return ResolutionLearningDecision(proposal: selected, basis: .strongContext)
        case .never, .userConfirmation, .strongContext:
            return nil
        }
    }
}

struct ResolutionLearningDecision: Hashable, Sendable {
    enum Basis: String, Hashable, Sendable { case explicit, strongContext, userConfirmed }
    let proposal: CandidateProposal
    let basis: Basis
}

struct ApplicationResolutionHistory: Codable, Hashable, Sendable {
    struct Entry: Codable, Hashable, Sendable {
        let bundleIdentifier: String
        let project: String?
        let tracker: Tracker?
        let repo: String?
        let savedAt: Date
    }

    var entries: [Entry] = []

    func signals(for bundleIdentifier: String?, now: Date = Date()) -> [WeightedHistorySignal] {
        guard let bundleIdentifier else { return [] }
        let halfLife: TimeInterval = 7 * 24 * 60 * 60
        return entries
            .filter { $0.bundleIdentifier == bundleIdentifier && now.timeIntervalSince($0.savedAt) >= 0 }
            .map { entry in
                let age = now.timeIntervalSince(entry.savedAt)
                let weight = max(1, Int((220 * exp(-log(2) * age / halfLife)).rounded()))
                return WeightedHistorySignal(project: entry.project, tracker: entry.tracker, repo: entry.repo, weight: weight)
            }
            .sorted {
                if $0.weight != $1.weight { return $0.weight > $1.weight }
                return ($0.project ?? $0.repo ?? "") < ($1.project ?? $1.repo ?? "")
            }
    }

    mutating func record(
        _ decision: ResolutionLearningDecision,
        bundleIdentifier: String?,
        now: Date = Date()
    ) {
        guard let bundleIdentifier else { return }
        let tracker: Tracker?
        let repo: String?
        switch decision.proposal.spec {
        case let .issue(value, _): tracker = value; repo = nil
        case let .pullRequest(_, value): tracker = nil; repo = value
        }
        let entry = Entry(
            bundleIdentifier: bundleIdentifier,
            project: decision.proposal.inferredProject,
            tracker: tracker,
            repo: repo,
            savedAt: now
        )
        entries.removeAll {
            $0.bundleIdentifier == bundleIdentifier &&
            $0.project == entry.project && $0.tracker == entry.tracker && $0.repo == entry.repo
        }
        entries.append(entry)
        entries = entries
            .filter { now.timeIntervalSince($0.savedAt) < 60 * 24 * 60 * 60 }
            .sorted { $0.savedAt > $1.savedAt }
            .prefix(50).map { $0 }
    }
}

struct WeightedHistorySignal: Hashable, Sendable {
    let project: String?
    let tracker: Tracker?
    let repo: String?
    let weight: Int
}

enum ResolutionHistoryStore {
    private static let defaultsKey = "applicationResolutionHistoryV1"

    static func load(defaults: UserDefaults = .standard) -> ApplicationResolutionHistory {
        guard let data = defaults.data(forKey: defaultsKey),
              let value = try? JSONDecoder().decode(ApplicationResolutionHistory.self, from: data) else { return .init() }
        return value
    }

    /// The caller must supply a policy decision from the plan. Merely resolving a candidate is
    /// intentionally insufficient, which prevents ambiguous bare numbers from poisoning context.
    static func record(
        _ decision: ResolutionLearningDecision,
        bundleIdentifier: String?,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) {
        var history = load(defaults: defaults)
        history.record(decision, bundleIdentifier: bundleIdentifier, now: now)
        if let data = try? JSONEncoder().encode(history) { defaults.set(data, forKey: defaultsKey) }
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}

enum LearnedContextStore {
    static func clear(defaults: UserDefaults = .standard) {
        ResolutionHistoryStore.clear(defaults: defaults)
        ResolutionContext.clear(defaults: defaults)
    }
}

enum EvidenceCandidatePlanner {
    private static let canonicalRepos = Set(ProjectDescriptor.known.compactMap {
        CandidatePlanner.repo(for: $0.key)?.lowercased()
    })
    private static let githubURLRegex = try! NSRegularExpression(
        pattern: #"(?i)https?://(?:www\.)?github\.com/([a-z0-9_.-]+)/([a-z0-9_.-]+?)(?:\.git)?(?:/pull/([0-9]+))?(?=[/?#\s]|$)"#
    )
    private static let repoSlugRegex = try! NSRegularExpression(
        pattern: #"(?i)(?<![a-z0-9_.-])([a-z0-9_.-]+)/([a-z0-9_.-]+)(?![a-z0-9_.-])"#
    )
    private static let pullRequestLanguageRegex = try! NSRegularExpression(
        pattern: #"\b(?:PR|pull[ -]?request)\b"#,
        options: [.caseInsensitive]
    )

    private struct ProjectMention: Hashable {
        let project: ProjectDescriptor
        let fragmentIndex: Int
        let lineIndex: Int
        let characterOffset: Int
    }

    private struct RepoMention: Hashable {
        let repo: String
        let fragmentIndex: Int
        let lineIndex: Int
        let characterOffset: Int
        let pullRequestNumber: Int?
        let isGitHubURL: Bool
    }

    private struct Draft {
        var spec: CandidateSpec
        var score: Int
        var reasons: [ResolutionReason]
        var sourceOrder: Int
        var anchorWeight: Int
        var inferredProject: String?
        var eligibility: ResolutionLearningEligibility
    }

    static func plan(
        input: OCRContextInput,
        context: ResolutionContext,
        pinned: PinnedTicketContext? = nil,
        foreground: ForegroundApplicationContext? = nil,
        history: ApplicationResolutionHistory = .init(),
        now: Date = Date(),
        maximumCandidates: Int = ResolutionPlan.maximumCandidates
    ) -> ResolutionPlan {
        let tokens = Array(TokenParser.parse(input).prefix(12))
        guard !tokens.isEmpty else { return ResolutionPlan(proposals: []) }
        let projectMentions = findProjectMentions(in: input)
        let repoMentions = findRepoMentions(in: input)
        let prLanguageLines = linesMatching(pullRequestLanguageRegex, in: input)
        let foregroundText = [foreground?.bundleIdentifier, foreground?.applicationName, foreground?.windowTitle]
            .compactMap { $0 }.joined(separator: " ")
        let foregroundProjects = projectsMentioned(in: foregroundText)
        let foregroundRepos = reposMentioned(in: foregroundText)
        let historySignals = history.signals(for: foreground?.bundleIdentifier, now: now)
        var drafts: [CandidateSpec: Draft] = [:]

        func add(
            _ spec: CandidateSpec,
            token: NearbyToken,
            project: String?,
            reason: ResolutionReason,
            eligibility: ResolutionLearningEligibility
        ) {
            if var existing = drafts[spec] {
                existing.score += reason.weight
                if !existing.reasons.contains(where: { $0.code == reason.code && $0.label == reason.label }) {
                    existing.reasons.append(reason)
                }
                // The visible anchor must point at the evidence that actually
                // drove this proposal. A weak earlier fallback must not steal
                // the highlight from a later explicit key or repository URL.
                if reason.weight > existing.anchorWeight ||
                    (reason.weight == existing.anchorWeight && token.sourceOrder < existing.sourceOrder) {
                    existing.sourceOrder = token.sourceOrder
                    existing.anchorWeight = reason.weight
                }
                if existing.inferredProject == nil { existing.inferredProject = project }
                if eligibility.rawValue > existing.eligibility.rawValue { existing.eligibility = eligibility }
                drafts[spec] = existing
            } else {
                drafts[spec] = Draft(
                    spec: spec,
                    score: reason.weight,
                    reasons: [reason],
                    sourceOrder: token.sourceOrder,
                    anchorWeight: reason.weight,
                    inferredProject: project,
                    eligibility: eligibility
                )
            }
        }

        for token in tokens {
            switch token.kind {
            case let .issueKey(project, number):
                let key = "\(project)-\(number)"
                let primary = CandidatePlanner.tracker(for: project, context: context)
                let reason = ResolutionReason(code: "explicit-key", label: "explicit \(key)", weight: 10_000, strength: .decisive)
                add(.issue(tracker: primary, key: key), token: token, project: project, reason: reason, eligibility: .explicit)
                if !CandidatePlanner.ppmProjects.contains(project), !CandidatePlanner.pmaProjects.contains(project) {
                    add(
                        .issue(tracker: primary.other, key: key), token: token, project: project,
                        reason: ResolutionReason(code: "unknown-key-fallback", label: "alternate tracker", weight: 9_700, strength: .strong),
                        eligibility: .explicit
                    )
                }

            case let .hashNumber(number), let .bareNumber(number):
                let isHash: Bool
                if case .hashNumber = token.kind { isHash = true } else { isHash = false }
                let nearbyProjects = scoreProjects(near: token, mentions: projectMentions)
                let nearbyRepos = scoreRepos(near: token, mentions: repoMentions)
                let hasNearbyPRLanguage = prLanguageLines.contains(where: { abs($0 - token.lineIndex) <= 1 })

                for (mention, weight) in nearbyProjects {
                    let key = "\(mention.project.key)-\(number)"
                    add(
                        .issue(tracker: mention.project.tracker, key: key), token: token, project: mention.project.key,
                        reason: ResolutionReason(
                            code: "nearby-project", label: "near \(mention.project.key)", weight: weight,
                            strength: weight >= 900 ? .strong : .weak
                        ),
                        eligibility: weight >= 900 ? .strongContext : .userConfirmation
                    )
                    if let repo = CandidatePlanner.repo(for: mention.project.key) {
                        add(
                            .pullRequest(number: number, repo: repo), token: token, project: mention.project.key,
                            reason: ResolutionReason(
                                code: "project-repo", label: "\(mention.project.key) repository", weight: isHash ? weight + 350 : max(20, weight - 450),
                                strength: isHash && weight >= 900 ? .strong : .weak
                            ),
                            eligibility: isHash && weight >= 900 ? .strongContext : .userConfirmation
                        )
                    }
                }

                for (mention, proximityWeight) in nearbyRepos {
                    let exactURL = mention.isGitHubURL && mention.pullRequestNumber == number
                    let weight = exactURL ? 10_000 : proximityWeight + (isHash ? 700 : 200) + (hasNearbyPRLanguage ? 500 : 0)
                    add(
                        .pullRequest(number: number, repo: mention.repo), token: token,
                        project: project(forRepo: mention.repo),
                        reason: ResolutionReason(
                            code: exactURL ? "github-url" : "nearby-repo",
                            label: exactURL ? "explicit GitHub pull request URL" : "near \(mention.repo)",
                            weight: weight,
                            strength: exactURL ? .decisive : (weight >= 1_200 ? .strong : .weak)
                        ),
                        eligibility: exactURL ? .explicit : (weight >= 1_200 ? .strongContext : .userConfirmation)
                    )
                }

                if isHash, hasNearbyPRLanguage {
                    for repo in fallbackRepos(
                        nearbyProjects: nearbyProjects.map(\.0.project),
                        foregroundProjects: foregroundProjects,
                        foregroundRepos: foregroundRepos,
                        pinned: pinned,
                        context: context
                    ) {
                        add(
                            .pullRequest(number: number, repo: repo), token: token, project: project(forRepo: repo),
                            reason: ResolutionReason(code: "hash-pr-language", label: "#number near PR language", weight: 900, strength: .strong),
                            eligibility: .strongContext
                        )
                    }
                } else if isHash {
                    for repo in fallbackRepos(
                        nearbyProjects: nearbyProjects.map(\.0.project),
                        foregroundProjects: foregroundProjects,
                        foregroundRepos: foregroundRepos,
                        pinned: pinned,
                        context: context
                    ).prefix(3) {
                        add(
                            .pullRequest(number: number, repo: repo), token: token, project: project(forRepo: repo),
                            reason: ResolutionReason(code: "hash-syntax", label: "GitHub-style #number", weight: 560, strength: .weak),
                            eligibility: .userConfirmation
                        )
                    }
                }

                for project in foregroundProjects {
                    let key = "\(project.key)-\(number)"
                    add(
                        .issue(tracker: project.tracker, key: key), token: token, project: project.key,
                        reason: ResolutionReason(code: "foreground-project", label: "foreground \(project.key)", weight: 480, strength: .weak),
                        eligibility: .userConfirmation
                    )
                }
                for repo in foregroundRepos {
                    add(
                        .pullRequest(number: number, repo: repo), token: token, project: project(forRepo: repo),
                        reason: ResolutionReason(code: "foreground-repo", label: "foreground \(repo)", weight: isHash ? 720 : 260, strength: .weak),
                        eligibility: .userConfirmation
                    )
                }
                for signal in historySignals.prefix(4) {
                    if let projectKey = signal.project,
                       let project = ProjectDescriptor.known.first(where: { $0.key == projectKey }) {
                        add(
                            .issue(tracker: signal.tracker ?? project.tracker, key: "\(project.key)-\(number)"),
                            token: token, project: project.key,
                            reason: ResolutionReason(code: "per-app-history", label: "recent in this app", weight: signal.weight, strength: .weak),
                            eligibility: .userConfirmation
                        )
                    }
                    if let repo = signal.repo, canonicalRepos.contains(repo.lowercased()) {
                        add(
                            .pullRequest(number: number, repo: repo), token: token, project: signal.project,
                            reason: ResolutionReason(code: "per-app-repo-history", label: "recent repository in this app", weight: signal.weight, strength: .weak),
                            eligibility: .userConfirmation
                        )
                    }
                }
                if let pinned,
                   let project = ProjectDescriptor.known.first(where: { $0.key == pinned.project }) {
                    add(
                        .issue(tracker: project.tracker, key: "\(project.key)-\(number)"), token: token, project: project.key,
                        reason: ResolutionReason(code: "pinned-project", label: "pinned \(project.key)", weight: 180, strength: .weak),
                        eligibility: .userConfirmation
                    )
                    if isHash, let repo = CandidatePlanner.repo(for: project.key) {
                        add(
                            .pullRequest(number: number, repo: repo), token: token, project: project.key,
                            reason: ResolutionReason(code: "pinned-repo", label: "pinned \(project.key) repository", weight: 240, strength: .weak),
                            eligibility: .userConfirmation
                        )
                    }
                }

                // Search all known issue namespaces so a real collision remains visible as an
                // alternate. Global history only breaks this final fallback tie; it never learns.
                for project in ProjectDescriptor.known {
                    let isGlobal = project.key == context.project(for: context.lastSeenTracker)
                    add(
                        .issue(tracker: project.tracker, key: "\(project.key)-\(number)"), token: token, project: project.key,
                        reason: ResolutionReason(
                            code: isGlobal ? "global-last-context" : "known-project-fallback",
                            label: isGlobal ? "last global project" : "possible \(project.key)",
                            weight: isGlobal ? 12 : 1,
                            strength: .fallback
                        ),
                        eligibility: .never
                    )
                }

            case .version:
                break
            }
        }

        let proposals = drafts.values.map {
            CandidateProposal(
                spec: $0.spec,
                score: $0.score,
                reasons: $0.reasons,
                sourceOrder: $0.sourceOrder,
                inferredProject: $0.inferredProject,
                learningEligibility: $0.eligibility
            )
        }.sorted(by: stableOrder).prefix(max(0, maximumCandidates)).map { $0 }
        return ResolutionPlan(proposals: proposals)
    }

    private static func stableOrder(_ lhs: CandidateProposal, _ rhs: CandidateProposal) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.sourceOrder != rhs.sourceOrder { return lhs.sourceOrder < rhs.sourceOrder }
        return lhs.spec.cacheKey < rhs.spec.cacheKey
    }

    private static func findProjectMentions(in input: OCRContextInput) -> [ProjectMention] {
        input.fragments.enumerated().flatMap { fragmentIndex, fragment in
            ProjectDescriptor.known.compactMap { project in
                let terms = [project.key, project.name] + project.aliases
                guard let offset = terms.compactMap({ wordOffset(of: $0, in: fragment.text) }).min() else { return nil }
                return ProjectMention(
                    project: project, fragmentIndex: fragmentIndex,
                    lineIndex: fragment.lineIndex, characterOffset: offset
                )
            }
        }
    }

    private static func findRepoMentions(in input: OCRContextInput) -> [RepoMention] {
        return input.fragments.enumerated().flatMap { fragmentIndex, fragment -> [RepoMention] in
            let ns = fragment.text as NSString
            var mentions: [RepoMention] = []
            for match in githubURLRegex.matches(in: fragment.text, range: NSRange(location: 0, length: ns.length)) {
                let repo = "\(ns.substring(with: match.range(at: 1)))/\(ns.substring(with: match.range(at: 2)))"
                let number = match.range(at: 3).location == NSNotFound ? nil : Int(ns.substring(with: match.range(at: 3)))
                mentions.append(.init(repo: repo.lowercased(), fragmentIndex: fragmentIndex, lineIndex: fragment.lineIndex, characterOffset: match.range.location, pullRequestNumber: number, isGitHubURL: true))
            }
            for match in repoSlugRegex.matches(in: fragment.text, range: NSRange(location: 0, length: ns.length)) {
                let repo = "\(ns.substring(with: match.range(at: 1)))/\(ns.substring(with: match.range(at: 2)))".lowercased()
                // A bare owner/name shape is commonly a source path,
                // date, or prose such as “and/or”. Only canonical repos
                // are trusted without explicit github.com URL evidence.
                guard !repo.hasPrefix("github.com/"), canonicalRepos.contains(repo) else { continue }
                mentions.append(.init(repo: repo, fragmentIndex: fragmentIndex, lineIndex: fragment.lineIndex, characterOffset: match.range.location, pullRequestNumber: nil, isGitHubURL: false))
            }
            return mentions
        }
    }

    private static func scoreProjects(near token: NearbyToken, mentions: [ProjectMention]) -> [(ProjectMention, Int)] {
        mentions.map { mention in
            let lineDistance = abs(mention.lineIndex - token.lineIndex)
            let weight: Int
            if lineDistance == 0 {
                weight = max(900, 1_450 - abs(mention.characterOffset - token.characterOffset) * 4)
            } else if lineDistance == 1 { weight = 820 }
            else if lineDistance == 2 { weight = 480 }
            else { weight = max(80, 280 - lineDistance * 40) }
            return (mention, weight)
        }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.project.key < $1.0.project.key
        }
    }

    private static func scoreRepos(near token: NearbyToken, mentions: [RepoMention]) -> [(RepoMention, Int)] {
        mentions.map { mention in
            let lineDistance = abs(mention.lineIndex - token.lineIndex)
            let weight = lineDistance == 0 ? 1_100 : (lineDistance == 1 ? 700 : max(100, 420 - lineDistance * 60))
            return (mention, weight)
        }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.repo < $1.0.repo
        }
    }

    private static func linesMatching(_ regex: NSRegularExpression, in input: OCRContextInput) -> Set<Int> {
        return Set(input.fragments.compactMap { fragment in
            let range = NSRange(location: 0, length: (fragment.text as NSString).length)
            return regex.firstMatch(in: fragment.text, range: range) == nil ? nil : fragment.lineIndex
        })
    }

    private static func projectsMentioned(in text: String) -> [ProjectDescriptor] {
        ProjectDescriptor.known.filter { project in
            ([project.key, project.name] + project.aliases).contains { wordOffset(of: $0, in: text) != nil }
        }
    }

    private static func reposMentioned(in text: String) -> [String] {
        let lower = text.lowercased()
        return ProjectDescriptor.known.compactMap { CandidatePlanner.repo(for: $0.key)?.lowercased() }
            .filter { lower.contains($0) }
    }

    private static func fallbackRepos(
        nearbyProjects: [ProjectDescriptor],
        foregroundProjects: [ProjectDescriptor],
        foregroundRepos: [String],
        pinned: PinnedTicketContext?,
        context: ResolutionContext
    ) -> [String] {
        var values = foregroundRepos
        values += (nearbyProjects + foregroundProjects).compactMap { CandidatePlanner.repo(for: $0.key)?.lowercased() }
        if let pinned,
           let repo = CandidatePlanner.repo(for: pinned.project)?.lowercased() { values.append(repo) }
        if let repo = CandidatePlanner.repo(for: context.project(for: context.lastSeenTracker))?.lowercased() { values.append(repo) }
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func project(forRepo repo: String) -> String? {
        ProjectDescriptor.known.first { CandidatePlanner.repo(for: $0.key)?.caseInsensitiveCompare(repo) == .orderedSame }?.key
    }

    private static func wordOffset(of term: String, in text: String) -> Int? {
        guard !term.isEmpty else { return nil }
        let ns = text as NSString
        var search = NSRange(location: 0, length: ns.length)
        while search.length > 0 {
            let found = ns.range(of: term, options: [.caseInsensitive], range: search)
            guard found.location != NSNotFound else { return nil }
            let word = CharacterSet.alphanumerics
            let beforeScalar = found.location > 0 ? UnicodeScalar(ns.character(at: found.location - 1)) : nil
            let beforeIsWord = beforeScalar.map(word.contains) ?? false
            let after = NSMaxRange(found)
            let afterScalar = after < ns.length ? UnicodeScalar(ns.character(at: after)) : nil
            let afterIsWord = afterScalar.map(word.contains) ?? false
            if !beforeIsWord && !afterIsWord { return found.location }
            let next = found.location + max(found.length, 1)
            search = NSRange(location: next, length: ns.length - next)
        }
        return nil
    }
}

actor TicketEvidencePlanner {
    func plan(
        input: OCRContextInput,
        context: ResolutionContext,
        pinned: PinnedTicketContext?,
        foreground: ForegroundApplicationContext?,
        history: ApplicationResolutionHistory
    ) -> ResolutionPlan {
        EvidenceCandidatePlanner.plan(
            input: input,
            context: context,
            pinned: pinned,
            foreground: foreground,
            history: history
        )
    }
}

enum ResolverDeterministicChecks {
    static func run() -> [String] {
        var failures: [String] = []
        let context = ResolutionContext(lastSeenTracker: .ppm, ppmProject: "PAI", pmaProject: "START")

        let explicit = EvidenceCandidatePlanner.plan(input: .init(lines: ["GLINT-20"]), context: context)
        if explicit.proposals.first?.spec != .issue(tracker: .ppm, key: "GLINT-20") ||
            explicit.proposals.first?.learningEligibility != .explicit { failures.append("explicit key") }

        let pr = EvidenceCandidatePlanner.plan(input: .init(lines: ["markus-barta/glint PR #20"]), context: context)
        if pr.proposals.first?.spec != .pullRequest(number: 20, repo: "markus-barta/glint") { failures.append("#PR syntax") }

        let customURL = EvidenceCandidatePlanner.plan(
            input: .init(lines: ["https://github.com/example/custom/pull/42"]),
            context: context
        )
        if customURL.proposals.first?.spec != .pullRequest(number: 42, repo: "example/custom") {
            failures.append("explicit GitHub URL")
        }

        let canonicalRepos = Set(ProjectDescriptor.known.compactMap {
            CandidatePlanner.repo(for: $0.key)?.lowercased()
        })
        for unsafeText in ["Sources/Glint #42", "2026/08/29 #42", "and/or #42"] {
            let unsafePlan = EvidenceCandidatePlanner.plan(input: .init(lines: [unsafeText]), context: context)
            let untrustedRepo = unsafePlan.proposals.contains { proposal in
                guard case let .pullRequest(_, repo) = proposal.spec else { return false }
                return !canonicalRepos.contains(repo.lowercased())
            }
            if untrustedRepo { failures.append("untrusted repo shape: \(unsafeText)") }
        }
        var legacyHistory = ApplicationResolutionHistory()
        let legacyCustomRepo = CandidateProposal(
            spec: .pullRequest(number: 7, repo: "sources/glint"),
            score: 10_000,
            reasons: [],
            sourceOrder: 0,
            inferredProject: nil,
            learningEligibility: .explicit
        )
        legacyHistory.record(
            .init(proposal: legacyCustomRepo, basis: .explicit),
            bundleIdentifier: "com.example.editor",
            now: Date(timeIntervalSince1970: 1_000_000)
        )
        let legacyPlan = EvidenceCandidatePlanner.plan(
            input: .init(lines: ["#42"]),
            context: context,
            foreground: .init(bundleIdentifier: "com.example.editor", applicationName: "Editor", windowTitle: nil),
            history: legacyHistory,
            now: Date(timeIntervalSince1970: 1_000_001)
        )
        if legacyPlan.proposals.contains(where: { $0.spec == .pullRequest(number: 42, repo: "sources/glint") }) {
            failures.append("legacy untrusted repo history")
        }

        let duplicateInput = OCRContextInput(fragments: [
            .init(text: "24", lineIndex: 0, order: 0),
            .init(text: "GLINT-24", lineIndex: 1, order: 1),
        ])
        let duplicateTokens = TokenParser.parse(duplicateInput)
        let explicitSourceOrder = duplicateTokens.first {
            if case .issueKey(project: "GLINT", number: 24) = $0.kind { return true }
            return false
        }?.sourceOrder
        let duplicate = EvidenceCandidatePlanner.plan(input: duplicateInput, context: context)
        let duplicateProposal = duplicate.proposals.first { $0.spec == .issue(tracker: .ppm, key: "GLINT-24") }
        if duplicateProposal?.sourceOrder != explicitSourceOrder { failures.append("highest-weight evidence anchor") }

        let bare = EvidenceCandidatePlanner.plan(input: .init(lines: ["300"]), context: context)
        if bare.proposals.count < 2 || bare.learningDecision(for: bare.proposals[0]) != nil { failures.append("bare collision learning") }

        let alias = EvidenceCandidatePlanner.plan(input: .init(lines: ["Pharos issue 203"]), context: context)
        if alias.proposals.first?.inferredProject != "PHAROS" { failures.append("nearby alias") }

        var history = ApplicationResolutionHistory()
        let recent = CandidateProposal(spec: .issue(tracker: .ppm, key: "GLINT-20"), score: 1, reasons: [], sourceOrder: 0, inferredProject: "GLINT", learningEligibility: .explicit)
        history.record(.init(proposal: recent, basis: .explicit), bundleIdentifier: "com.example.editor", now: Date(timeIntervalSince1970: 1_000_000))
        let recentWeight = history.signals(for: "com.example.editor", now: Date(timeIntervalSince1970: 1_000_001)).first?.weight ?? 0
        let oldWeight = history.signals(for: "com.example.editor", now: Date(timeIntervalSince1970: 1_000_000 + 14 * 24 * 60 * 60)).first?.weight ?? 0
        if recentWeight <= oldWeight { failures.append("per-app decay") }

        let tie = EvidenceCandidatePlanner.plan(input: .init(lines: ["300"]), context: context)
        if tie.learningDecision(for: tie.proposals[0]) != nil { failures.append("ambiguous tie") }

        let glintWindow = ForegroundApplicationContext(bundleIdentifier: "com.apple.Safari", applicationName: "Safari", windowTitle: "GLINT Settings")
        let falseContext = EvidenceCandidatePlanner.plan(input: .init(lines: ["300"]), context: context, foreground: glintWindow)
        if falseContext.proposals.first?.inferredProject != "GLINT" ||
            falseContext.proposals.first?.learningEligibility != .userConfirmation ||
            falseContext.proposals.first.flatMap({ falseContext.learningDecision(for: $0) }) != nil {
            failures.append("weak foreground context must require confirmation")
        }
        return failures
    }
}

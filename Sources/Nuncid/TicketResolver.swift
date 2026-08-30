import Darwin
import Foundation

private struct PaimosIssue: Decodable {
    let issueKey: String
    let title: String
    let status: String
    let type: String?
    let priority: String?
    let description: String?
    enum CodingKeys: String, CodingKey { case issueKey = "issue_key", title, status, type, priority, description }
}
private struct PullRequest: Decodable {
    struct Author: Decodable { let login: String }
    let number: Int
    let title: String
    let state: String
    let body: String?
    let isDraft: Bool
    let reviewDecision: String?
    let author: Author?
    let url: String?
}
private struct CacheEntry: Codable { let line: TicketLine?; let savedAt: Date }

private final class ProcessCancellationHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    func install(_ process: Process) {
        lock.lock(); self.process = process; lock.unlock()
    }

    func clear() {
        lock.lock(); process = nil; lock.unlock()
    }

    func requestTermination() {
        lock.lock(); let running = process; lock.unlock()
        if running?.isRunning == true { running?.terminate() }
    }
}

private final class ProcessOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock(); data.append(chunk); lock.unlock()
    }

    func snapshot(appending tail: Data) -> Data {
        lock.lock(); data.append(tail); let value = data; lock.unlock()
        return value
    }
}

struct ResolvedCandidate: Hashable, Sendable {
    let proposal: CandidateProposal
    let line: TicketLine
}

actor TicketResolver {
    private var cache: [String: CacheEntry] = [:]
    private let defaultsKey = "resolutionCacheV1"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([String: CacheEntry].self, from: data) { cache = decoded }
    }

    func resolve(_ spec: CandidateSpec) async -> TicketLine? {
        guard !Task.isCancelled else { return nil }
        if let entry = cache[spec.cacheKey] {
            let ttl: TimeInterval = entry.line == nil ? 60 : 15 * 60
            if Date().timeIntervalSince(entry.savedAt) < ttl { return Task.isCancelled ? nil : entry.line }
        }
        let line: TicketLine?
        switch spec {
        case let .issue(tracker, key): line = await resolveIssue(tracker: tracker, key: key)
        case let .pullRequest(number, repo): line = await resolvePullRequest(number: number, repo: repo)
        }
        // Cancellation is not a negative lookup and must never poison the miss cache.
        guard !Task.isCancelled else { return nil }
        cache[spec.cacheKey] = CacheEntry(line: line, savedAt: Date())
        persist()
        return line
    }

    /// Resolves evidence-backed candidates first. The weight-1 namespace sweep is launched only
    /// when that phase produced no real ticket, keeping common scans from fanning out broadly.
    func resolve(_ plan: ResolutionPlan) async -> [ResolvedCandidate] {
        guard !Task.isCancelled else { return [] }
        let phases = plan.lookupPhases
        let maximumResults = HoverResultPolicy.maximumResults
        let primary = await resolvePhase(phases.primary, maximumResults: maximumResults)
        guard !Task.isCancelled else { return [] }
        guard ResolutionLookupPolicy.shouldResolveFallback(primaryResolvedCount: primary.count) else { return primary }
        return await resolvePhase(phases.fallback, maximumResults: maximumResults)
    }

    private func resolvePhase(
        _ proposals: [CandidateProposal],
        maximumResults: Int
    ) async -> [ResolvedCandidate] {
        let bounded = Array(proposals.prefix(ResolutionPlan.maximumCandidates))
        guard !bounded.isEmpty, !Task.isCancelled else { return [] }
        let resolved = await withTaskGroup(of: (Int, TicketLine?).self, returning: [(Int, TicketLine?)].self) { group in
            var launched = ResolutionLookupPolicy.initialCount(total: bounded.count)
            for index in 0..<launched {
                let proposal = bounded[index]
                group.addTask { [weak self] in
                    guard let self, !Task.isCancelled else { return (index, nil) }
                    return (index, await self.resolve(proposal.spec))
                }
            }
            var values: [(Int, TicketLine?)] = []
            var realIDs = Set<String>()
            while let value = await group.next() {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    break
                }
                values.append(value)
                if let line = value.1 { realIDs.insert(line.id) }
                if ResolutionLookupPolicy.shouldLaunchNext(
                    launched: launched,
                    total: bounded.count,
                    resolvedCount: realIDs.count,
                    maximumResults: maximumResults,
                    isCancelled: Task.isCancelled
                ) {
                    let index = launched
                    let proposal = bounded[index]
                    launched += 1
                    group.addTask { [weak self] in
                        guard let self, !Task.isCancelled else { return (index, nil) }
                        return (index, await self.resolve(proposal.spec))
                    }
                }
            }
            return values
        }
        var seen = Set<String>()
        return resolved
            .sorted { $0.0 < $1.0 }
            .compactMap { index, line -> ResolvedCandidate? in
                guard let line, seen.insert(line.id).inserted else { return nil }
                return ResolvedCandidate(proposal: bounded[index], line: line)
            }
            .prefix(maximumResults)
            .map { $0 }
    }

    func clearCache() { cache.removeAll(); UserDefaults.standard.removeObject(forKey: defaultsKey) }

    private func resolveIssue(tracker: Tracker, key: String) async -> TicketLine? {
        guard let executable = Self.findExecutable(named: "paimos"),
              let data = await Self.run(executable, ["--instance", tracker.rawValue, "--json", "issue", "get", key]),
              let issue = try? JSONDecoder().decode(PaimosIssue.self, from: data) else { return nil }
        let metadata = [
            issue.type?.replacingOccurrences(of: "_", with: " "),
            issue.priority.map { "\($0) priority" },
        ].compactMap { $0 }.joined(separator: " · ")
        return TicketLine(
            key: issue.issueKey,
            state: issue.status,
            title: issue.title,
            source: tracker.rawValue,
            metadata: metadata,
            detail: Self.excerpt(issue.description),
            destination: "\(tracker == .ppm ? "https://pm.barta.cm" : "https://paimos.agm.ng")/issues/\(issue.issueKey)"
        )
    }

    private func resolvePullRequest(number: Int, repo: String) async -> TicketLine? {
        guard let executable = Self.findExecutable(named: "gh"),
              let data = await Self.run(executable, ["pr", "view", "\(number)", "--repo", repo, "--json", "author,body,isDraft,number,reviewDecision,state,title,url"]),
              let pr = try? JSONDecoder().decode(PullRequest.self, from: data) else { return nil }
        let metadata = [
            repo,
            pr.author.map { "@\($0.login)" },
            pr.reviewDecision?.lowercased().replacingOccurrences(of: "_", with: " "),
        ].compactMap { $0 }.joined(separator: " · ")
        return TicketLine(
            key: "#\(pr.number)",
            state: pr.isDraft ? "draft" : pr.state.lowercased(),
            title: pr.title,
            source: "gh",
            metadata: metadata,
            detail: Self.excerpt(pr.body),
            destination: pr.url
        )
    }

    private func persist() {
        let recent = cache.filter { Date().timeIntervalSince($0.value.savedAt) < 86_400 }
        if let data = try? JSONEncoder().encode(recent) { UserDefaults.standard.set(data, forKey: defaultsKey) }
    }

    private static func findExecutable(named name: String) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = ["\(home)/.nix-profile/bin/\(name)", "/etc/profiles/per-user/\(NSUserName())/bin/\(name)", "/run/current-system/sw/bin/\(name)", "/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"]
        return paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map(URL.init(fileURLWithPath:))
    }

    private static func excerpt(_ raw: String?, limit: Int = 280) -> String {
        guard let raw else { return "" }
        let condensed = raw.split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
        guard condensed.count > limit else { return condensed }
        return String(condensed.prefix(limit - 1)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    static func runProcessForTesting(_ executable: URL, _ arguments: [String]) async -> Data? {
        await run(executable, arguments)
    }

    private static func run(_ executable: URL, _ arguments: [String]) async -> Data? {
        guard !Task.isCancelled else { return nil }
        let process = Process()
        let stdout = Pipe()
        let cancellationHandle = ProcessCancellationHandle()
        let output = ProcessOutputBuffer()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            output.append(chunk)
        }
        do { try process.run() } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            return nil
        }
        cancellationHandle.install(process)
        let startedAt = Date()
        let succeeded = await withTaskCancellationHandler(operation: {
            while process.isRunning,
                  !ProcessExecutionPolicy.shouldStop(
                    isCancelled: Task.isCancelled,
                    elapsed: Date().timeIntervalSince(startedAt)
                  ) {
                try? await Task.sleep(nanoseconds: ProcessExecutionPolicy.pollNanoseconds)
            }
            if process.isRunning { await terminate(process) }
            return !Task.isCancelled && !process.isRunning && process.terminationStatus == 0
        }, onCancel: {
            cancellationHandle.requestTermination()
        })
        cancellationHandle.clear()
        stdout.fileHandleForReading.readabilityHandler = nil
        guard succeeded else {
            try? stdout.fileHandleForReading.close()
            return nil
        }
        let tail = stdout.fileHandleForReading.readDataToEndOfFile()
        let data = output.snapshot(appending: tail)
        return data
    }

    private static func terminate(_ process: Process) async {
        if process.isRunning { process.terminate() }
        if process.isRunning { await uncancelledPause(nanoseconds: ProcessExecutionPolicy.terminationGraceNanoseconds) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        if process.isRunning { await uncancelledPause(nanoseconds: ProcessExecutionPolicy.killGraceNanoseconds) }
    }

    private static func uncancelledPause(nanoseconds: UInt64) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .nanoseconds(Int(nanoseconds))) {
                continuation.resume()
            }
        }
    }
}

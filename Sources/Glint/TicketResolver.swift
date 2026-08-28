import Darwin
import Foundation

private struct PaimosIssue: Decodable {
    let issueKey: String
    let title: String
    let status: String
    enum CodingKeys: String, CodingKey { case issueKey = "issue_key", title, status }
}
private struct PullRequest: Decodable { let number: Int; let title: String; let state: String }
private struct CacheEntry: Codable { let line: GlintLine?; let savedAt: Date }

actor TicketResolver {
    private var cache: [String: CacheEntry] = [:]
    private let defaultsKey = "resolutionCacheV1"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([String: CacheEntry].self, from: data) { cache = decoded }
    }

    func resolve(_ spec: CandidateSpec) async -> GlintLine? {
        if let entry = cache[spec.cacheKey] {
            let ttl: TimeInterval = entry.line == nil ? 60 : 15 * 60
            if Date().timeIntervalSince(entry.savedAt) < ttl { return entry.line }
        }
        let line: GlintLine?
        switch spec {
        case let .issue(tracker, key): line = await resolveIssue(tracker: tracker, key: key)
        case let .pullRequest(number, repo): line = await resolvePullRequest(number: number, repo: repo)
        }
        cache[spec.cacheKey] = CacheEntry(line: line, savedAt: Date())
        persist()
        return line
    }

    func clearCache() { cache.removeAll(); UserDefaults.standard.removeObject(forKey: defaultsKey) }

    private func resolveIssue(tracker: Tracker, key: String) async -> GlintLine? {
        guard let executable = Self.findExecutable(named: "paimos"),
              let data = await Self.run(executable, ["--instance", tracker.rawValue, "--json", "issue", "get", key]),
              let issue = try? JSONDecoder().decode(PaimosIssue.self, from: data) else { return nil }
        return GlintLine(key: issue.issueKey, state: issue.status, title: issue.title, source: tracker.rawValue)
    }

    private func resolvePullRequest(number: Int, repo: String) async -> GlintLine? {
        guard let executable = Self.findExecutable(named: "gh"),
              let data = await Self.run(executable, ["pr", "view", "\(number)", "--repo", repo, "--json", "number,title,state"]),
              let pr = try? JSONDecoder().decode(PullRequest.self, from: data) else { return nil }
        return GlintLine(key: "#\(pr.number)", state: pr.state.lowercased(), title: pr.title, source: "gh")
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

    private static func run(_ executable: URL, _ arguments: [String]) async -> Data? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process(); let stdout = Pipe()
                process.executableURL = executable; process.arguments = arguments
                process.standardOutput = stdout; process.standardError = FileHandle.nullDevice
                let finished = DispatchSemaphore(value: 0)
                let outputLock = NSLock()
                var output = Data()
                stdout.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    guard !chunk.isEmpty else { return }
                    outputLock.lock(); output.append(chunk); outputLock.unlock()
                }
                process.terminationHandler = { _ in finished.signal() }
                do {
                    try process.run()
                    if finished.wait(timeout: .now() + 3) == .timedOut {
                        process.terminate()
                        if finished.wait(timeout: .now() + 1) == .timedOut {
                            kill(process.processIdentifier, SIGKILL)
                            _ = finished.wait(timeout: .now() + 1)
                        }
                    }
                    stdout.fileHandleForReading.readabilityHandler = nil
                    let tail = stdout.fileHandleForReading.readDataToEndOfFile()
                    outputLock.lock(); output.append(tail); let data = output; outputLock.unlock()
                    guard !process.isRunning, process.terminationStatus == 0 else { continuation.resume(returning: nil); return }
                    continuation.resume(returning: data)
                } catch { continuation.resume(returning: nil) }
            }
        }
    }
}

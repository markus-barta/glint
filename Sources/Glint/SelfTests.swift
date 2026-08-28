import Darwin
import Foundation

enum SelfTests {
    static func runAndExit() -> Never {
        let tokens = TokenParser.parse([
            "HAUSV-578 PAI-843 START-186 PHAROS-203 JANUS-455",
            "collision #130 bare 130 release 0.99.12",
        ])
        guard tokens.map(\.raw) == [
            "HAUSV-578", "PAI-843", "START-186", "PHAROS-203", "JANUS-455",
            "#130", "130", "0.99.12",
        ] else {
            fputs("self-test failed: token parsing: \(tokens.map(\.raw))\n", stderr)
            exit(1)
        }

        let context = ResolutionContext(lastSeenTracker: .pma, ppmProject: "PHAROS", pmaProject: "START")
        guard CandidatePlanner.tracker(for: "HAUSV", context: context) == .ppm,
              CandidatePlanner.tracker(for: "START", context: context) == .pma else {
            fputs("self-test failed: tracker routing\n", stderr)
            exit(1)
        }
        guard TriggerMode.allCases.map(\.rawValue) == ["dwell", "option", "always"],
              TriggerMode.dwell.label.contains("300") else {
            fputs("self-test failed: trigger modes\n", stderr)
            exit(1)
        }
        let bare = NearbyToken(raw: "203", kind: .bareNumber(203), sourceOrder: 0)
        guard CandidatePlanner.candidates(for: bare, context: context) == [
            .issue(tracker: .pma, key: "START-203"),
            .issue(tracker: .ppm, key: "PHAROS-203"),
            .pullRequest(number: 203, repo: "augmentoring-team/start-agm-com"),
        ] else {
            fputs("self-test failed: collision ordering\n", stderr)
            exit(1)
        }
        guard CandidatePlanner.repo(for: "PAI") == "inspr-at/paimos",
              CandidatePlanner.repo(for: "UNKNOWN") == nil else {
            fputs("self-test failed: canonical repo routing\n", stderr)
            exit(1)
        }
        let first = GlintLine(key: "GLINT-7", state: "in-progress", title: "First", source: "ppm")
        let second = GlintLine(key: "#7", state: "open", title: "Second", source: "gh")
        guard HoverResultPolicy.visible(from: [nil, nil]).isEmpty,
              HoverResultPolicy.visible(from: [nil, first, nil, second, first]) == [first, second],
              HoverResultPolicy.visible(from: (1...20).map {
                  GlintLine(key: "PAI-\($0)", state: "open", title: "Result \($0)", source: "ppm")
              }).count == HoverResultPolicy.maximumResults else {
            fputs("self-test failed: visible result policy\n", stderr)
            exit(1)
        }
        let suite = "GlintSelfTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fputs("self-test failed: isolated preferences\n", stderr)
            exit(1)
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("always", forKey: "triggerMode")
        defaults.set("command", forKey: "stickyModifier")
        defaults.set(0.55, forKey: "stickyDoublePressInterval")
        guard GlintPreferences.load(defaults: defaults) == GlintPreferences(
            triggerMode: .always,
            stickyModifier: .command,
            stickyDoublePressInterval: 0.55
        ) else {
            fputs("self-test failed: persisted preferences\n", stderr)
            exit(1)
        }
        var rapidPress = RapidPressDetector()
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        guard !rapidPress.registerPress(at: start, maximumInterval: 0.40),
              rapidPress.registerPress(at: start.addingTimeInterval(0.35), maximumInterval: 0.40),
              !rapidPress.registerPress(at: start.addingTimeInterval(1.0), maximumInterval: 0.40),
              !rapidPress.registerPress(at: start.addingTimeInterval(1.5), maximumInterval: 0.40) else {
            fputs("self-test failed: rapid modifier sequence\n", stderr)
            exit(1)
        }
        print("GLINT self-tests passed")
        exit(0)
    }
}

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
        let customInspect = HotKey(keyCode: 2, modifiers: [.command, .control], keyLabel: "D")
        GlintPreferences.save(customInspect, key: "inspectHotKey", defaults: defaults)
        GlintPreferences.save(nil, key: "pinHotKey", defaults: defaults)
        guard GlintPreferences.load(defaults: defaults) == GlintPreferences(
            triggerMode: .always,
            inspectHotKey: customInspect,
            pinHotKey: nil
        ) else {
            fputs("self-test failed: persisted preferences\n", stderr)
            exit(1)
        }
        guard HotKey.inspect.label == "⌥Space", HotKey.pin.label == "⌥⇧Space",
              HotKey.inspect.isSafeGlobalShortcut,
              HotKey(keyCode: 120, modifiers: [], keyLabel: "F2").isSafeGlobalShortcut,
              !HotKey(keyCode: 123, modifiers: [], keyLabel: "←").isSafeGlobalShortcut,
              !HotKey(keyCode: 0, modifiers: [.shift], keyLabel: "A").isSafeGlobalShortcut else {
            fputs("self-test failed: global shortcuts\n", stderr)
            exit(1)
        }
        guard ProjectMatcher.bestMatch(for: "phraos")?.key == "PHAROS",
              ProjectMatcher.bestMatch(for: "pamo")?.key == "PAI",
              ProjectMatcher.bestMatch(for: "haus")?.key == "HAUSV",
              ProjectMatcher.damerauLevenshtein("phraos", "pharos") == 1 else {
            fputs("self-test failed: fuzzy project matching\n", stderr)
            exit(1)
        }
        let pinned = PinnedTicketContext(project: "PAI", number: 843)
        pinned.persist(defaults: defaults)
        guard PinnedTicketContext.load(defaults: defaults, fallback: context) == pinned else {
            fputs("self-test failed: pinned ticket context\n", stderr)
            exit(1)
        }
        print("GLINT self-tests passed")
        exit(0)
    }
}

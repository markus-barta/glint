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
              !HotKey(keyCode: 0, modifiers: [.shift], keyLabel: "A").isSafeGlobalShortcut,
              GlintPreferences.shortcutsConflict(inspect: .inspect, pin: .inspect),
              !GlintPreferences.shortcutsConflict(inspect: .inspect, pin: .pin),
              !GlintPreferences.shortcutsConflict(inspect: nil, pin: .pin) else {
            fputs("self-test failed: global shortcuts\n", stderr)
            exit(1)
        }
        guard PinCommandPolicy.action(for: .hidden) == .openPinned,
              PinCommandPolicy.action(for: .temporary) == .pinTemporary,
              PinCommandPolicy.action(for: .pinnedInactive) == .focusPinned,
              PinCommandPolicy.action(for: .pinnedActive) == .closePinned else {
            fputs("self-test failed: pin command state transitions\n", stderr)
            exit(1)
        }
        guard CircularNavigation.advancedIndex(current: 0, direction: -1, count: 3) == 2,
              CircularNavigation.advancedIndex(current: 2, direction: 1, count: 3) == 0,
              CircularNavigation.advancedIndex(current: 1, direction: 1, count: 3) == 2,
              CircularNavigation.advancedIndex(current: 7, direction: 1, count: 0) == 0 else {
            fputs("self-test failed: circular result navigation\n", stderr)
            exit(1)
        }
        let visibleFrame = CGRect(x: 100, y: 200, width: 800, height: 600)
        guard PanelPlacement.clamped(origin: CGPoint(x: -500, y: 2_000), size: CGSize(width: 300, height: 200), visibleFrame: visibleFrame) == CGPoint(x: 108, y: 592),
              PanelPlacement.clamped(origin: CGPoint(x: 400, y: 350), size: CGSize(width: 300, height: 200), visibleFrame: visibleFrame) == CGPoint(x: 400, y: 350) else {
            fputs("self-test failed: screen clamping\n", stderr)
            exit(1)
        }
        var editing = PinnedEditState()
        editing.appendDigits("2"); editing.appendDigits("03")
        guard editing.numberBuffer == "203", editing.projectQuery.isEmpty,
              editing.backspace() == .number, editing.numberBuffer == "20" else {
            fputs("self-test failed: rapid numeric editing\n", stderr)
            exit(1)
        }
        editing.appendLetters("ph", currentProject: "START")
        editing.appendLetters("raos", currentProject: "START")
        guard editing.numberBuffer == nil, editing.projectQuery == "phraos", editing.projectBeforeQuery == "START",
              editing.backspace() == .project, editing.projectQuery == "phrao" else {
            fputs("self-test failed: project edit/revert state\n", stderr)
            exit(1)
        }
        editing.clear()
        guard !editing.hasInput else {
            fputs("self-test failed: clearing pinned input\n", stderr)
            exit(1)
        }
        let pasteTokens = TokenParser.parse(["PHAROS-203", "#123", "456"])
        guard pasteTokens.map(\.kind) == [.issueKey(project: "PHAROS", number: 203), .hashNumber(123), .bareNumber(456)] else {
            fputs("self-test failed: pasted ticket forms\n", stderr)
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
        var activation = ActivationPreferences.defaults
        activation.mode = .dwell
        activation.dwellMilliseconds = 475
        activation.holdModifiers = [.control, .option]
        activation.responsiveness = .fast
        activation.scanFeedbackEnabled = false
        activation.persist(defaults: defaults)
        guard ActivationPreferences.load(defaults: defaults) == activation else {
            fputs("self-test failed: activation preference persistence\n", stderr)
            exit(1)
        }
        guard !HoverInvocationPolicy.shouldTrigger(
            preferences: .init(mode: .off, dwellMilliseconds: 300, holdModifiers: [.option], responsiveness: .balanced, scanFeedbackEnabled: true),
            stableDuration: 10, dwellAlreadyScanned: false, heldModifiers: [.option], elapsedSinceLastScan: 10
        ), !HoverInvocationPolicy.shouldTrigger(
            preferences: activation,
            stableDuration: 0.474, dwellAlreadyScanned: false, heldModifiers: [], elapsedSinceLastScan: 10
        ), HoverInvocationPolicy.shouldTrigger(
            preferences: activation,
            stableDuration: 0.475, dwellAlreadyScanned: false, heldModifiers: [], elapsedSinceLastScan: 10
        ) else {
            fputs("self-test failed: off/dwell invocation policy\n", stderr)
            exit(1)
        }
        var holdActivation = activation
        holdActivation.mode = .hold
        guard !HoverInvocationPolicy.shouldTrigger(
            preferences: holdActivation,
            stableDuration: 0, dwellAlreadyScanned: false, heldModifiers: [.option], elapsedSinceLastScan: 1
        ), HoverInvocationPolicy.shouldTrigger(
            preferences: holdActivation,
            stableDuration: 0, dwellAlreadyScanned: false, heldModifiers: [.control, .option, .shift], elapsedSinceLastScan: 1
        ) else {
            fputs("self-test failed: custom hold modifier invocation policy\n", stderr)
            exit(1)
        }
        var continuousActivation = activation
        continuousActivation.mode = .continuous
        continuousActivation.responsiveness = .fast
        guard !HoverInvocationPolicy.shouldTrigger(
            preferences: continuousActivation,
            stableDuration: 0, dwellAlreadyScanned: false, heldModifiers: [], elapsedSinceLastScan: 0.349
        ), HoverInvocationPolicy.shouldTrigger(
            preferences: continuousActivation,
            stableDuration: 0, dwellAlreadyScanned: false, heldModifiers: [], elapsedSinceLastScan: 0.35
        ) else {
            fputs("self-test failed: continuous responsiveness invocation policy\n", stderr)
            exit(1)
        }
        let presentation = PresentationPreferences(
            alternativePreviews: 5,
            textSize: .extraLarge,
            width: .wide,
            density: .detailed,
            surface: .solid
        )
        presentation.persist(defaults: defaults)
        guard PresentationPreferences.load(defaults: defaults) == presentation,
              presentation.circularAlternativeIndices(count: 4, selectedIndex: 3) == [0, 1, 2] else {
            fputs("self-test failed: ticket appearance persistence/navigation\n", stderr)
            exit(1)
        }
        let anchorBounds = CGRect(x: 120, y: 340, width: 72, height: 18)
        let fragment = RecognizedTextFragment(
            text: "Open GLINT-24 now",
            confidence: 0.98,
            normalizedBounds: CGRect(x: 0.1, y: 0.2, width: 0.4, height: 0.1),
            screenBounds: CGRect(x: 100, y: 330, width: 220, height: 28),
            spans: [RecognizedTextSpan(
                literal: "GLINT-24",
                utf16Range: NSRange(location: 5, length: 8),
                normalizedBounds: CGRect(x: 0.2, y: 0.2, width: 0.15, height: 0.08),
                screenBounds: anchorBounds
            )]
        )
        let anchorInput = OCRContextInput(fragments: [
            OCRContextFragment(text: fragment.text, lineIndex: 0, order: 0, confidence: 0.98)
        ])
        guard let anchorToken = TokenParser.parse(anchorInput).first,
              ScanFeedbackAnchor(token: anchorToken, fragments: [fragment])?.bounds == anchorBounds else {
            fputs("self-test failed: token-anchored scan feedback\n", stderr)
            exit(1)
        }
        let resolverFailures = ResolverDeterministicChecks.run()
        guard resolverFailures.isEmpty else {
            fputs("self-test failed: evidence resolver: \(resolverFailures.joined(separator: ", "))\n", stderr)
            exit(1)
        }
        print("GLINT self-tests passed")
        exit(0)
    }
}

import Darwin
import Foundation

private final class SelfTestAsyncResult: @unchecked Sendable {
    private let lock = NSLock()
    private var succeeded = false

    func set(_ value: Bool) {
        lock.lock(); succeeded = value; lock.unlock()
    }

    func get() -> Bool {
        lock.lock(); let value = succeeded; lock.unlock(); return value
    }
}

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
              PinCommandPolicy.action(for: .pinnedActive) == .closePinned,
              PinCommandPolicy.clearsManualInspection(for: .openPinned),
              PinCommandPolicy.clearsManualInspection(for: .pinTemporary),
              !PinCommandPolicy.clearsManualInspection(for: .focusPinned),
              !PinCommandPolicy.clearsManualInspection(for: .closePinned) else {
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
        let compactPRTokens = TokenParser.parse(["PR#42", "pr#43"])
        guard compactPRTokens.map(\.kind) == [.hashNumber(42), .hashNumber(43)] else {
            fputs("self-test failed: case-symmetric compact PR parsing\n", stderr); exit(1)
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
        for (legacy, expected) in [("dwell", HoverActivationMode.dwell), ("option", .hold), ("always", .continuous)] {
            let migrationSuite = "GlintSelfTests.Migration.\(legacy).\(UUID().uuidString)"
            guard let migrationDefaults = UserDefaults(suiteName: migrationSuite) else { exit(1) }
            migrationDefaults.set(legacy, forKey: "triggerMode")
            let migrated = ActivationPreferences.load(defaults: migrationDefaults)
            guard migrated.mode == expected,
                  migrationDefaults.string(forKey: "activation.mode") == expected.rawValue else {
                fputs("self-test failed: legacy activation migration \(legacy)\n", stderr); exit(1)
            }
            migrationDefaults.removePersistentDomain(forName: migrationSuite)
        }
        let corruptSuite = "GlintSelfTests.CorruptActivation.\(UUID().uuidString)"
        guard let corruptDefaults = UserDefaults(suiteName: corruptSuite) else { exit(1) }
        corruptDefaults.set("not-a-mode", forKey: "activation.mode")
        guard ActivationPreferences.load(defaults: corruptDefaults).mode == ActivationPreferences.defaults.mode else {
            fputs("self-test failed: corrupt activation mode fallback\n", stderr); exit(1)
        }
        corruptDefaults.removePersistentDomain(forName: corruptSuite)
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
        guard ScanFeedbackLifecycleEvent.allCases.allSatisfy({
            ScanFeedbackLifecyclePolicy.permits($0, startedGeneration: 7, currentGeneration: 7)
        }), ScanFeedbackLifecycleEvent.allCases.allSatisfy({
            !ScanFeedbackLifecyclePolicy.permits($0, startedGeneration: 7, currentGeneration: 8)
        }) else {
            fputs("self-test failed: stale scan feedback lifecycle gate\n", stderr)
            exit(1)
        }
        guard QueuedScanLifecyclePolicy.shouldLaunch(
            queuedGeneration: 8, currentGeneration: 8, completedGeneration: 7
        ), !QueuedScanLifecyclePolicy.shouldLaunch(
            queuedGeneration: 8, currentGeneration: 9, completedGeneration: 7
        ), !QueuedScanLifecyclePolicy.shouldLaunch(
            queuedGeneration: 8, currentGeneration: 8, completedGeneration: 8
        ), QueuedScanLifecyclePolicy.shouldRetargetAfterPointerMovement(source: .explicitCommand),
           !QueuedScanLifecyclePolicy.shouldRetargetAfterPointerMovement(source: .automaticHover) else {
            fputs("self-test failed: queued scan generation lifecycle\n", stderr); exit(1)
        }
        guard ScanCuePolicy.showsInvoked(for: .explicitCommand),
              !ScanCuePolicy.showsInvoked(for: .automaticHover),
              ScanCuePolicy.terminal(for: .explicitCommand, hasResolvedResult: false, hasAnchor: false) == .noMatch,
              ScanCuePolicy.terminal(for: .automaticHover, hasResolvedResult: false, hasAnchor: false) == .none,
              ScanCuePolicy.terminal(for: .automaticHover, hasResolvedResult: true, hasAnchor: true) == .resolved,
              ScanCuePolicy.terminal(for: .explicitCommand, hasResolvedResult: true, hasAnchor: false) == .none else {
            fputs("self-test failed: explicit-versus-automatic scan cues\n", stderr); exit(1)
        }
        guard ScanFeedbackDisappearancePolicy.shouldExpire(scheduledGeneration: 12, currentGeneration: 12),
              !ScanFeedbackDisappearancePolicy.shouldExpire(scheduledGeneration: 11, currentGeneration: 12),
              ScanFeedbackTiming.recognizedLifetime <= 2.5,
              ScanFeedbackTiming.recognizedLifetime > ScanFeedbackTiming.resolvedLifetime else {
            fputs("self-test failed: scan feedback expiry generation\n", stderr); exit(1)
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
        ), !HoverInvocationPolicy.shouldTrigger(
            preferences: continuousActivation,
            stableDuration: 0, dwellAlreadyScanned: false, heldModifiers: [], elapsedSinceLastScan: 0.35
        ), HoverInvocationPolicy.shouldTrigger(
            preferences: continuousActivation,
            stableDuration: HoverInvocationPolicy.continuousMovementSettleDuration,
            dwellAlreadyScanned: false, heldModifiers: [], elapsedSinceLastScan: 0.35
        ) else {
            fputs("self-test failed: continuous responsiveness invocation policy\n", stderr)
            exit(1)
        }
        guard !ManualInspectionPolicy.shouldDismiss(distanceFromAnchor: 35, elapsed: 7.9),
              ManualInspectionPolicy.shouldDismiss(distanceFromAnchor: 37, elapsed: 1),
              ManualInspectionPolicy.shouldDismiss(distanceFromAnchor: 0, elapsed: 8) else {
            fputs("self-test failed: manual inspection lifetime policy\n", stderr); exit(1)
        }
        guard ResolutionLookupPolicy.initialCount(total: 16) == 4,
              ResolutionLookupPolicy.initialCount(total: 2) == 2,
              ResolutionLookupPolicy.shouldLaunchNext(launched: 4, total: 16, resolvedCount: 2, maximumResults: 12),
              !ResolutionLookupPolicy.shouldLaunchNext(launched: 4, total: 16, resolvedCount: 12, maximumResults: 12),
              !ResolutionLookupPolicy.shouldLaunchNext(launched: 16, total: 16, resolvedCount: 0, maximumResults: 12) else {
            fputs("self-test failed: bounded lookup scheduling policy\n", stderr); exit(1)
        }
        guard ScanTerminalFeedbackPolicy.event(hasResolvedResult: false, hasAnchor: false) == .noMatch,
              ScanTerminalFeedbackPolicy.event(hasResolvedResult: true, hasAnchor: true) == .resolved,
              ScanTerminalFeedbackPolicy.event(hasResolvedResult: true, hasAnchor: false) == .none else {
            fputs("self-test failed: terminal scan feedback policy\n", stderr); exit(1)
        }
        let directPlan = DirectEntryResolutionPlanner.plan(
            project: "GLINT", key: "GLINT-42", trackers: [.ppm, .pma]
        )
        guard directPlan.proposals.map(\.spec) == [
            .issue(tracker: .ppm, key: "GLINT-42"),
            .issue(tracker: .pma, key: "GLINT-42")
        ], directPlan.learningDecision(for: directPlan.proposals[0]) == nil,
           directPlan.learningDecision(for: directPlan.proposals[0], userConfirmed: true)?.basis == .userConfirmed else {
            fputs("self-test failed: direct-entry confirmation learning plan\n", stderr); exit(1)
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
        guard AppearanceResetPolicy.shouldKeepUndo(previous: presentation, current: .defaults),
              !AppearanceResetPolicy.shouldKeepUndo(previous: presentation, current: presentation),
              !AppearanceResetPolicy.shouldKeepUndo(previous: nil, current: .defaults) else {
            fputs("self-test failed: appearance reset undo lifecycle\n", stderr); exit(1)
        }
        let previewLines = (1...6).map {
            GlintLine(key: "GLINT-\($0)", state: "open", title: "Preview \($0)", source: "ppm", detail: "Detail")
        }
        let previewHeight = OverlayMetrics.preferredHeight(lines: previewLines, sticky: true, preferences: presentation)
        let previewScale = OverlayMetrics.previewScale(
            contentWidth: presentation.width.points,
            availableWidth: 556,
            contentHeight: previewHeight,
            maximumHeight: 300
        )
        var noAlternatives = presentation
        noAlternatives.alternativePreviews = 0
        guard presentation.width.points * previewScale <= 556.001,
              previewHeight * previewScale <= 300.001,
              previewScale > 0,
              noAlternatives.circularAlternativeIndices(count: 6, selectedIndex: 0).isEmpty,
              OverlayMetrics.preferredHeight(lines: previewLines, sticky: true, preferences: noAlternatives) < previewHeight else {
            fputs("self-test failed: bounded XL appearance preview\n", stderr)
            exit(1)
        }
        let constrainedOverlay = OverlayMetrics.size(
            lines: previewLines,
            sticky: true,
            preferences: presentation,
            visibleFrame: CGRect(x: 0, y: 0, width: 900, height: 330)
        )
        let pinnedBody = OverlayMetrics.pinnedBodyHeight(totalHeight: constrainedOverlay.height)
        guard pinnedBody > 0,
              pinnedBody + OverlayMetrics.pinnedReservedChromeHeight <= constrainedOverlay.height + 0.001 else {
            fputs("self-test failed: footer-safe max-stress pinned layout\n", stderr); exit(1)
        }
        let negativeDisplay = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let negativeScreen = CGRect(x: -1920, y: -120, width: 1920, height: 1080)
        let syntheticCapture = CapturePlan(
            rect: CGRect(x: -1820, y: 100, width: 200, height: 50),
            displayBounds: negativeDisplay,
            screenFrame: negativeScreen
        )
        guard syntheticCapture.appKitRect(forQuartz: syntheticCapture.rect) == CGRect(x: -1820, y: 810, width: 200, height: 50),
              syntheticCapture.quartzRect(forVisionNormalized: CGRect(x: 0.25, y: 0.2, width: 0.5, height: 0.4)) == CGRect(x: -1770, y: 120, width: 100, height: 20) else {
            fputs("self-test failed: CapturePlan coordinate conversion\n", stderr); exit(1)
        }
        let feedbackScreen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        guard ScanFeedbackGeometry.panelFrame(
            around: CGRect(x: 200, y: 300, width: 80, height: 20),
            lastPoint: .zero,
            screenFrames: [],
            mainScreenFrame: nil
        ) == nil,
        let clampedFeedbackFrame = ScanFeedbackGeometry.panelFrame(
            around: CGRect(x: 9_000, y: 9_000, width: 80, height: 20),
            lastPoint: .zero,
            screenFrames: [feedbackScreen],
            mainScreenFrame: feedbackScreen
        ), feedbackScreen.intersects(clampedFeedbackFrame), !clampedFeedbackFrame.isEmpty else {
            fputs("self-test failed: safe scan-feedback screen fallback\n", stderr)
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
        let denseInput = OCRContextInput(lines: [
            "Release 0.3.0 build 2026 08 29 GLINT-19 #184 PAI-843 999 1000"
        ])
        let denseTokens = TokenParser.parse(denseInput)
        let densePlan = EvidenceCandidatePlanner.plan(input: denseInput, context: context)
        let denseOrders = ScanAnchorPolicy.sourceOrders(tokens: denseTokens, plan: densePlan)
        let versionOrders = Set(denseTokens.compactMap { token -> Int? in
            if case .version = token.kind { return token.sourceOrder }
            return nil
        })
        guard denseOrders.count <= ScanAnchorPolicy.maximumAnchors,
              denseOrders.allSatisfy({ !versionOrders.contains($0) }),
              denseOrders.allSatisfy({ order in densePlan.proposals.contains(where: { $0.sourceOrder == order }) }) else {
            fputs("self-test failed: proposal-backed capped scan anchors\n", stderr); exit(1)
        }
        let historyProposal = CandidateProposal(
            spec: .issue(tracker: .ppm, key: "GLINT-24"), score: 100,
            reasons: [.init(code: "test", label: "test", weight: 100, strength: .strong)],
            sourceOrder: 0, inferredProject: "GLINT", learningEligibility: .userConfirmation
        )
        ResolutionHistoryStore.record(
            .init(proposal: historyProposal, basis: .userConfirmed),
            bundleIdentifier: "at.example.editor", defaults: defaults,
            now: Date(timeIntervalSince1970: 1_000)
        )
        var learnedContext = ResolutionContext.load(defaults: defaults)
        learnedContext.saw(project: "GLINT", on: .ppm, defaults: defaults)
        guard ResolutionHistoryStore.load(defaults: defaults).entries.count == 1,
              defaults.string(forKey: "lastPPMProject") == "GLINT" else {
            fputs("self-test failed: learned context round-trip\n", stderr); exit(1)
        }
        LearnedContextStore.clear(defaults: defaults)
        guard ResolutionHistoryStore.load(defaults: defaults).entries.isEmpty,
              defaults.object(forKey: "lastSeenTracker") == nil,
              defaults.object(forKey: "lastPPMProject") == nil,
              defaults.object(forKey: "lastPMAProject") == nil else {
            fputs("self-test failed: learned context clear\n", stderr); exit(1)
        }
        let resolverFailures = ResolverDeterministicChecks.run()
        guard resolverFailures.isEmpty else {
            fputs("self-test failed: evidence resolver: \(resolverFailures.joined(separator: ", "))\n", stderr)
            exit(1)
        }
        let cancellationFinished = DispatchSemaphore(value: 0)
        let cancellationResult = SelfTestAsyncResult()
        Task.detached {
            let startedAt = Date()
            let processTask = Task {
                await TicketResolver.runProcessForTesting(
                    URL(fileURLWithPath: "/bin/sleep"), ["5"]
                )
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
            processTask.cancel()
            let output = await processTask.value
            cancellationResult.set(output == nil && Date().timeIntervalSince(startedAt) < 2)
            cancellationFinished.signal()
        }
        guard cancellationFinished.wait(timeout: .now() + 3) == .success,
              cancellationResult.get() else {
            fputs("self-test failed: subprocess cancellation propagation\n", stderr); exit(1)
        }
        print("GLINT self-tests passed")
        exit(0)
    }
}

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
              CandidatePlanner.tracker(for: "NUNCID", context: context) == .ppm,
              CandidatePlanner.tracker(for: "START", context: context) == .pma else {
            fputs("self-test failed: tracker routing\n", stderr)
            exit(1)
        }
        guard HoverActivationMode.allCases.map(\.title) == ["Off", "Toggle Hover", "Press to Scan"],
              ActivationShortcutPolicy.action(for: .off) == .none,
              ActivationShortcutPolicy.action(for: .toggleHover) == .toggleHover,
              ActivationShortcutPolicy.action(for: .pressToScan) == .scanOnce,
              HoverMenuBarState.resolve(mode: .toggleHover, hoverEnabled: false, matchFound: true) == .inactive,
              HoverMenuBarState.resolve(mode: .toggleHover, hoverEnabled: true, matchFound: false) == .active,
              HoverMenuBarState.resolve(mode: .toggleHover, hoverEnabled: true, matchFound: true) == .matchFound,
              HoverMenuBarState.resolve(mode: .pressToScan, hoverEnabled: true, matchFound: true) == .inactive else {
            fputs("self-test failed: activation shortcut and menu bar state policy\n", stderr)
            exit(1)
        }
        guard let catalogueVersion = ReleaseHistory.notes.first?.version else {
            fputs("self-test failed: empty version history catalogue\n", stderr)
            exit(1)
        }
        let packagedVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? catalogueVersion
        guard ReleaseHistory.isValid(currentVersion: packagedVersion == "Development" ? catalogueVersion : packagedVersion),
              ReleaseHistory.notes.allSatisfy({ note in
                  note.items.allSatisfy { !$0.label.isEmpty && !$0.detail.isEmpty }
              }) else {
            fputs("self-test failed: positive version history catalogue\n", stderr)
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
        guard CandidatePlanner.repo(for: "NUNCID") == "markus-barta/nuncid",
              CandidatePlanner.repo(for: "GLINT") == "markus-barta/nuncid",
              CandidatePlanner.repo(for: "PAI") == "inspr-at/paimos",
              CandidatePlanner.repo(for: "UNKNOWN") == nil else {
            fputs("self-test failed: canonical repo routing\n", stderr)
            exit(1)
        }
        let first = TicketLine(key: "GLINT-7", state: "in-progress", title: "First", source: "ppm")
        let second = TicketLine(key: "#7", state: "open", title: "Second", source: "gh")
        guard HoverResultPolicy.visible(from: [nil, nil]).isEmpty,
              HoverResultPolicy.visible(from: [nil, first, nil, second, first]) == [first, second],
              HoverResultPolicy.visible(from: (1...20).map {
                  TicketLine(key: "PAI-\($0)", state: "open", title: "Result \($0)", source: "ppm")
              }).count == HoverResultPolicy.maximumResults else {
            fputs("self-test failed: visible result policy\n", stderr)
            exit(1)
        }
        let suite = "NuncidSelfTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fputs("self-test failed: isolated preferences\n", stderr)
            exit(1)
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("always", forKey: "triggerMode")
        let customInspect = HotKey(keyCode: 2, modifiers: [.command, .control], keyLabel: "D")
        let f19 = HotKey(keyCode: 80, modifiers: [], keyLabel: "F19")
        NuncidPreferences.save(customInspect, key: "inspectHotKey", defaults: defaults)
        NuncidPreferences.save(nil, key: "pinHotKey", defaults: defaults)
        guard NuncidPreferences.load(defaults: defaults) == NuncidPreferences(
            inspectHotKey: customInspect,
            pinHotKey: nil
        ) else {
            fputs("self-test failed: persisted preferences\n", stderr)
            exit(1)
        }
        NuncidPreferences.save(f19, key: "pinHotKey", defaults: defaults)
        guard NuncidPreferences.load(defaults: defaults).pinHotKey == f19 else {
            fputs("self-test failed: persisted F19 shortcut\n", stderr)
            exit(1)
        }
        let unsafePlainKey = HotKey(keyCode: 0, modifiers: [.shift], keyLabel: "A")
        let escape = HotKey(keyCode: 53, modifiers: [], keyLabel: "Esc")
        let backwardDelete = HotKey(keyCode: 51, modifiers: [], keyLabel: "Delete")
        let forwardDelete = HotKey(keyCode: 117, modifiers: [], keyLabel: "Forward Delete")
        guard HotKey.inspect.label == "⌥Space", HotKey.pin.label == "⌥⇧Space",
              HotKey.inspect.isSafeGlobalShortcut,
              HotKey(keyCode: 120, modifiers: [], keyLabel: "F2").isSafeGlobalShortcut,
              HotKey(keyCode: 122, modifiers: [], keyLabel: "F1").isSafeGlobalShortcut,
              HotKey(keyCode: 111, modifiers: [], keyLabel: "F12").isSafeGlobalShortcut,
              HotKey(keyCode: 105, modifiers: [], keyLabel: "F13").isSafeGlobalShortcut,
              f19.isSafeGlobalShortcut,
              HotKey(keyCode: 90, modifiers: [], keyLabel: "F20").isSafeGlobalShortcut,
              HotKey.functionKeyLabel(for: f19.keyCode) == "F19",
              !HotKey(keyCode: 123, modifiers: [], keyLabel: "←").isSafeGlobalShortcut,
              !unsafePlainKey.isSafeGlobalShortcut,
              ShortcutCapturePolicy.decision(for: f19, forbiddenHotKey: nil) == .accept(f19),
              ShortcutCapturePolicy.decision(for: unsafePlainKey, forbiddenHotKey: nil) == .rejectUnsafe,
              ShortcutCapturePolicy.decision(for: escape, forbiddenHotKey: nil) == .cancel,
              ShortcutCapturePolicy.decision(for: backwardDelete, forbiddenHotKey: nil) == .clear,
              ShortcutCapturePolicy.decision(for: forwardDelete, forbiddenHotKey: nil) == .clear,
              ShortcutCapturePolicy.decision(for: f19, forbiddenHotKey: f19) == .rejectDuplicate,
              NuncidPreferences.shortcutsConflict(inspect: .inspect, pin: .inspect),
              !NuncidPreferences.shortcutsConflict(inspect: .inspect, pin: .pin),
              !NuncidPreferences.shortcutsConflict(inspect: nil, pin: .pin) else {
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
        guard ProjectMatcher.bestMatch(for: "nunc")?.key == "NUNCID",
              ProjectMatcher.bestMatch(for: "phraos")?.key == "PHAROS",
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
        activation.mode = .toggleHover
        activation.scanFeedbackEnabled = false
        activation.persist(defaults: defaults)
        guard ActivationPreferences.load(defaults: defaults) == activation else {
            fputs("self-test failed: activation preference persistence\n", stderr)
            exit(1)
        }
        for (legacy, expected) in [("dwell", HoverActivationMode.toggleHover), ("continuous", .toggleHover), ("always", .toggleHover), ("option", .pressToScan), ("hold", .pressToScan), ("off", .off)] {
            let migrationSuite = "NuncidSelfTests.Migration.\(legacy).\(UUID().uuidString)"
            guard let migrationDefaults = UserDefaults(suiteName: migrationSuite) else { exit(1) }
            migrationDefaults.set(legacy, forKey: legacy == "always" || legacy == "option" ? "triggerMode" : "activation.mode")
            let migrated = ActivationPreferences.load(defaults: migrationDefaults)
            guard migrated.mode == expected,
                  migrationDefaults.string(forKey: "activation.mode") == expected.rawValue else {
                fputs("self-test failed: legacy activation migration \(legacy)\n", stderr); exit(1)
            }
            migrationDefaults.removePersistentDomain(forName: migrationSuite)
        }
        let corruptSuite = "NuncidSelfTests.CorruptActivation.\(UUID().uuidString)"
        guard let corruptDefaults = UserDefaults(suiteName: corruptSuite) else { exit(1) }
        corruptDefaults.set("not-a-mode", forKey: "activation.mode")
        guard ActivationPreferences.load(defaults: corruptDefaults).mode == ActivationPreferences.defaults.mode else {
            fputs("self-test failed: corrupt activation mode fallback\n", stderr); exit(1)
        }
        corruptDefaults.removePersistentDomain(forName: corruptSuite)
        guard !HoverInvocationPolicy.shouldTrigger(
            preferences: .init(mode: .off, scanFeedbackEnabled: true),
            hoverEnabled: true, stableDuration: 10, locationAlreadyScanned: false
        ), !HoverInvocationPolicy.shouldTrigger(
            preferences: activation,
            hoverEnabled: false, stableDuration: 10, locationAlreadyScanned: false
        ), !HoverInvocationPolicy.shouldTrigger(
            preferences: activation,
            hoverEnabled: true, stableDuration: ActivationPreferences.hoverSettleDuration - 0.001, locationAlreadyScanned: false
        ), HoverInvocationPolicy.shouldTrigger(
            preferences: activation,
            hoverEnabled: true, stableDuration: ActivationPreferences.hoverSettleDuration, locationAlreadyScanned: false
        ), !HoverInvocationPolicy.shouldTrigger(
            preferences: activation,
            hoverEnabled: true, stableDuration: 10, locationAlreadyScanned: true
        ) else {
            fputs("self-test failed: one-scan-per-location hover policy\n", stderr)
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
        let normalPinnedCompletion = PinnedScanOwnershipPolicy.permitsCompletion(
            startedScanGeneration: 40,
            currentScanGeneration: 40,
            startedDirectGeneration: 7,
            currentDirectGeneration: 7,
            startedEditGeneration: 3,
            currentEditGeneration: 3
        )
        let lateResolvedCompletion = PinnedScanOwnershipPolicy.permitsCompletion(
            startedScanGeneration: 40,
            currentScanGeneration: 41,
            startedDirectGeneration: 7,
            currentDirectGeneration: 9,
            startedEditGeneration: 3,
            currentEditGeneration: 4
        )
        let lateNoMatchCompletion = PinnedScanOwnershipPolicy.permitsCompletion(
            startedScanGeneration: 40,
            currentScanGeneration: 41,
            startedDirectGeneration: 7,
            currentDirectGeneration: 8,
            startedEditGeneration: 3,
            currentEditGeneration: 4
        )
        guard PinnedScanOwnershipPolicy.shouldInvalidateForInput(alreadyClaimed: false),
              !PinnedScanOwnershipPolicy.shouldInvalidateForInput(alreadyClaimed: true),
              normalPinnedCompletion,
              !lateResolvedCompletion,
              !lateNoMatchCompletion else {
            fputs("self-test failed: pinned input owns late scan results/no-match\n", stderr); exit(1)
        }
        guard ScanCuePolicy.showsInvoked(for: .explicitCommand),
              !ScanCuePolicy.showsInvoked(for: .automaticHover),
              ScanCuePolicy.terminal(for: .explicitCommand, hasResolvedResult: false) == .noMatch,
              ScanCuePolicy.terminal(for: .automaticHover, hasResolvedResult: false) == .none,
              ScanCuePolicy.terminal(for: .automaticHover, hasResolvedResult: true) == .none,
              ScanCuePolicy.terminal(for: .explicitCommand, hasResolvedResult: true) == .none else {
            fputs("self-test failed: explicit-versus-automatic scan cues\n", stderr); exit(1)
        }
        guard ScanFeedbackDisappearancePolicy.shouldExpire(scheduledGeneration: 12, currentGeneration: 12),
              !ScanFeedbackDisappearancePolicy.shouldExpire(scheduledGeneration: 11, currentGeneration: 12),
              ScanFeedbackTiming.recognizedLifetime <= 2.5,
              ScanFeedbackTiming.recognizedLifetime > ScanFeedbackTiming.resolvedLifetime else {
            fputs("self-test failed: scan feedback expiry generation\n", stderr); exit(1)
        }
        let stableAnchor = ScanFeedbackAnchor(
            literal: "GLINT-24",
            bounds: CGRect(x: 120.1, y: 340.1, width: 72.1, height: 18.1)
        )
        let reconstructedAnchor = ScanFeedbackAnchor(
            literal: "GLINT-24",
            bounds: CGRect(x: 120.2, y: 340.2, width: 72.2, height: 18.2)
        )
        let changedAnchor = ScanFeedbackAnchor(
            literal: "GLINT-25",
            bounds: CGRect(x: 120.1, y: 340.1, width: 72.1, height: 18.1)
        )
        let secondaryAnchor = ScanFeedbackAnchor(
            literal: "HAUSV-38",
            bounds: CGRect(x: 260, y: 280, width: 82, height: 18)
        )
        let recognizedPhase = ScanFeedbackPhase.recognized(
            anchors: [stableAnchor], selectedID: stableAnchor.id
        )
        let repeatedRecognized = ScanFeedbackPhase.recognized(
            anchors: [reconstructedAnchor], selectedID: reconstructedAnchor.id
        )
        let recognizedDecision = ScanFeedbackPresentationPolicy.decision(
            current: recognizedPhase, incoming: repeatedRecognized, generation: 20
        )
        let resolvedPhase = ScanFeedbackPhase.resolved(anchor: stableAnchor)
        let resolvedDecision = ScanFeedbackPresentationPolicy.decision(
            current: resolvedPhase,
            incoming: .resolved(anchor: reconstructedAnchor),
            generation: recognizedDecision.generation
        )
        let changedDecision = ScanFeedbackPresentationPolicy.decision(
            current: resolvedPhase,
            incoming: .resolved(anchor: changedAnchor),
            generation: resolvedDecision.generation
        )
        let activeOnly = LookupHighlightPolicy.visibleAnchors(
            [stableAnchor, secondaryAnchor], selected: secondaryAnchor, showAll: false
        )
        let allLookupAnchors = LookupHighlightPolicy.visibleAnchors(
            [stableAnchor, stableAnchor], selected: secondaryAnchor, showAll: true
        )
        let scannedSource = LookupSourceSnapshot(
            processIdentifier: 42,
            windowIdentifier: 7,
            windowBounds: CGRect(x: 10, y: 20, width: 900, height: 700),
            windowTitle: "NUNCID-52"
        )
        let movedSource = LookupSourceSnapshot(
            processIdentifier: 42,
            windowIdentifier: 7,
            windowBounds: CGRect(x: 11, y: 20, width: 900, height: 700),
            windowTitle: "NUNCID-52"
        )
        let midLockOn = FoundLockOnAnimationState.at(progress: 0.55)
        let settledLockOn = FoundLockOnAnimationState.at(progress: 1)
        let lookupDecision = ScanFeedbackPresentationPolicy.decision(
            current: .lookup(
                anchors: allLookupAnchors,
                selectedID: secondaryAnchor.id,
                celebratesFound: false
            ),
            incoming: .lookup(
                anchors: allLookupAnchors,
                selectedID: secondaryAnchor.id,
                celebratesFound: false
            ),
            generation: changedDecision.generation
        )
        let animatedLookupDecision = ScanFeedbackPresentationPolicy.decision(
            current: .lookup(
                anchors: allLookupAnchors,
                selectedID: secondaryAnchor.id,
                celebratesFound: true
            ),
            incoming: .lookup(
                anchors: allLookupAnchors,
                selectedID: secondaryAnchor.id,
                celebratesFound: false
            ),
            generation: lookupDecision.generation
        )
        guard stableAnchor.id == reconstructedAnchor.id,
              stableAnchor.id != changedAnchor.id,
              activeOnly == [secondaryAnchor],
              allLookupAnchors == [stableAnchor, secondaryAnchor],
              LookupHighlightVisibilityPolicy.shouldShow(
                popupVisible: true,
                mappedAnchorAvailable: true
              ),
              !LookupHighlightVisibilityPolicy.shouldShow(
                popupVisible: false,
                mappedAnchorAvailable: true
              ),
              LookupSourceLifecyclePolicy.remainsValid(
                scanned: scannedSource,
                current: scannedSource
              ),
              !LookupSourceLifecyclePolicy.remainsValid(
                scanned: scannedSource,
                current: movedSource
              ),
              midLockOn.sweepOpacity > 0,
              midLockOn.particleOpacity > 0,
              settledLockOn.sweep == 1,
              settledLockOn.sweepOpacity == 0,
              settledLockOn.confirmationOpacity == 0,
              settledLockOn.particleOpacity == 0,
              recognizedDecision == .init(action: .refreshExpiry, generation: 21),
              resolvedDecision == .init(action: .refreshExpiry, generation: 22),
              changedDecision == .init(action: .rebuild, generation: 23),
              lookupDecision == .init(action: .refreshExpiry, generation: 24),
              animatedLookupDecision == .init(action: .rebuild, generation: 25),
              ScanFeedbackStyleMetrics.foundAnimationDuration < 1,
              ScanFeedbackDisappearancePolicy.shouldExpire(
                scheduledGeneration: resolvedDecision.generation,
                currentGeneration: resolvedDecision.generation
              ),
              !ScanFeedbackDisappearancePolicy.shouldExpire(
                scheduledGeneration: recognizedDecision.generation,
                currentGeneration: resolvedDecision.generation
              ) else {
            fputs("self-test failed: idempotent scan feedback presentation\n", stderr); exit(1)
        }
        guard !ManualInspectionPolicy.shouldDismiss(distanceFromAnchor: 35, elapsed: 7.9),
              ManualInspectionPolicy.shouldDismiss(distanceFromAnchor: 37, elapsed: 1),
              ManualInspectionPolicy.shouldDismiss(distanceFromAnchor: 0, elapsed: 8) else {
            fputs("self-test failed: manual inspection lifetime policy\n", stderr); exit(1)
        }
        let hideNow = Date(timeIntervalSinceReferenceDate: 100)
        guard TemporaryOverlayLifetimePolicy.shouldScheduleHide(
            isVisible: true,
            isPinned: false,
            pointerInside: false,
            movedFromLastPosition: true,
            manualLifetimeExpired: false
        ), !TemporaryOverlayLifetimePolicy.shouldScheduleHide(
            isVisible: true,
            isPinned: false,
            pointerInside: true,
            movedFromLastPosition: true,
            manualLifetimeExpired: true
        ), !TemporaryOverlayLifetimePolicy.shouldScheduleHide(
            isVisible: true,
            isPinned: true,
            pointerInside: false,
            movedFromLastPosition: true,
            manualLifetimeExpired: true
        ), TemporaryOverlayLifetimePolicy.shouldHide(
            deadline: hideNow,
            now: hideNow.addingTimeInterval(TemporaryOverlayLifetimePolicy.exitGrace),
            pointerInside: false
        ), !TemporaryOverlayLifetimePolicy.shouldHide(
            deadline: hideNow,
            now: hideNow.addingTimeInterval(TemporaryOverlayLifetimePolicy.exitGrace),
            pointerInside: true
        ) else {
            fputs("self-test failed: pointer-safe temporary popup lifetime\n", stderr); exit(1)
        }
        guard ResolutionLookupPolicy.initialCount(total: 16) == 4,
              ResolutionLookupPolicy.initialCount(total: 2) == 2,
              ResolutionLookupPolicy.shouldLaunchNext(launched: 4, total: 16, resolvedCount: 2, maximumResults: 12),
              !ResolutionLookupPolicy.shouldLaunchNext(launched: 4, total: 16, resolvedCount: 12, maximumResults: 12),
              !ResolutionLookupPolicy.shouldLaunchNext(launched: 16, total: 16, resolvedCount: 0, maximumResults: 12) else {
            fputs("self-test failed: bounded lookup scheduling policy\n", stderr); exit(1)
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
        var customPresentation = presentation
        customPresentation.width = .custom
        customPresentation.customWidth = 777
        customPresentation.customHeight = 333
        customPresentation.persist(defaults: defaults)
        let neighborRail = NeighborRailPolicy.indices(count: 7, selectedIndex: 3, visibleCount: 6)
        let customOverlay = OverlayMetrics.size(
            lines: [],
            sticky: true,
            preferences: customPresentation,
            visibleFrame: CGRect(x: 0, y: 0, width: 720, height: 300)
        )
        let popupPreferences = PopupInteractionPreferences(
            scrollModifier: .command,
            restorePinned: true,
            showAllDetectedIDsWhenPinned: true
        )
        popupPreferences.persist(defaults: defaults)
        let forwardGeneration = 1
        let reverseGeneration = 2
        let staleCompletedGeneration = TicketTitleSettlePolicy.completedGeneration(
            current: 0,
            callbackGeneration: forwardGeneration
        )
        let reverseCompletedGeneration = TicketTitleSettlePolicy.completedGeneration(
            current: staleCompletedGeneration,
            callbackGeneration: reverseGeneration
        )
        let alreadySettledGeneration = 7
        let nextResultSetFlightGeneration = TicketTitleSettlePolicy.nextGeneration(
            after: alreadySettledGeneration
        )
        let upwardRail = SpatialRailTransitionPolicy.boundaries(navigationDirection: 1)
        let downwardRail = SpatialRailTransitionPolicy.boundaries(navigationDirection: -1)
        guard PresentationPreferences.load(defaults: defaults) == customPresentation,
              customOverlay == CGSize(width: 704, height: 284),
              neighborRail.previous == [0, 1, 2],
              neighborRail.next == [4, 5, 6],
              TicketKeyMotionPolicy.style(reduceMotion: false) == .matchedFlight,
              TicketKeyMotionPolicy.style(reduceMotion: true) == .opacityOnly,
              TicketKeyMotionPolicy.titleSettleDelay >= 0.34,
              forwardGeneration == 1,
              reverseGeneration == 2,
              !TicketTitleSettlePolicy.isSettled(
                  navigationGeneration: reverseGeneration,
                  settledGeneration: staleCompletedGeneration,
                  reduceMotion: false
              ),
              TicketTitleSettlePolicy.isSettled(
                  navigationGeneration: reverseGeneration,
                  settledGeneration: reverseCompletedGeneration,
                  reduceMotion: false
              ),
              TicketTitleSettlePolicy.isSettled(
                  navigationGeneration: reverseGeneration,
                  settledGeneration: 0,
                  reduceMotion: true
              ),
              nextResultSetFlightGeneration == 8,
              !TicketTitleSettlePolicy.isSettled(
                  navigationGeneration: nextResultSetFlightGeneration,
                  settledGeneration: alreadySettledGeneration,
                  reduceMotion: false
              ),
              upwardRail.insertion == .bottom,
              upwardRail.removal == .top,
              downwardRail.insertion == .top,
              downwardRail.removal == .bottom,
              SpatialRailTransitionPolicy.directionLeadTime > 0,
              SpatialRailTransitionPolicy.directionLeadTime <= 1.0 / 60.0,
              PinnedHeaderLayoutPolicy.contextWidth(totalWidth: 420) == 100,
              PinnedHeaderLayoutPolicy.contextWidth(totalWidth: 590) == 176,
              PopupInteractionPreferences.load(defaults: defaults) == popupPreferences,
              PopupScrollModifier.option.matches([.option, .capsLock]),
              !PopupScrollModifier.option.matches([.option, .shift]) else {
            fputs("self-test failed: custom popup geometry, rail, and interaction preferences\n", stderr); exit(1)
        }
        let ppmDestination = TicketLine(key: "NUNCID-35", state: "done", title: "Link", source: "ppm").destinationURL
        let githubDestination = TicketLine(key: "#184", state: "open", title: "Link", source: "gh", metadata: "markus-barta/nuncid · pull request").destinationURL
        guard ppmDestination?.absoluteString == "https://pm.barta.cm/issues/NUNCID-35",
              githubDestination?.absoluteString == "https://github.com/markus-barta/nuncid/pull/184" else {
            fputs("self-test failed: source destination links\n", stderr); exit(1)
        }
        let naturalSingle = OverlayMetrics.size(
            lines: [TicketLine(key: "NUNCID-1", state: "open", title: "Short result", source: "ppm")],
            sticky: false,
            preferences: .defaults,
            visibleFrame: CGRect(x: 0, y: 0, width: 1_200, height: 800)
        )
        guard naturalSingle.height < OverlaySizePolicy.minimum.height,
              OverlayMetrics.temporaryBodyHeight(totalHeight: naturalSingle.height) == naturalSingle.height - OverlayMetrics.outerPadding * 2 else {
            fputs("self-test failed: naturally measured popup height and temporary body budget\n", stderr); exit(1)
        }
        guard AppearanceResetPolicy.shouldKeepUndo(previous: presentation, current: .defaults),
              !AppearanceResetPolicy.shouldKeepUndo(previous: presentation, current: presentation),
              !AppearanceResetPolicy.shouldKeepUndo(previous: nil, current: .defaults) else {
            fputs("self-test failed: appearance reset undo lifecycle\n", stderr); exit(1)
        }
        let previewLines = (1...6).map {
            TicketLine(key: "GLINT-\($0)", state: "open", title: "Preview \($0)", source: "ppm", detail: "Detail")
        }
        let variedPrimaryLines = [
            TicketLine(key: "NUNCID-16", state: "done", title: "Short title", source: "ppm"),
            TicketLine(key: "HAUSV-38", state: "in-progress", title: "A much longer title that wraps and proves the primary card does not move while identities travel", source: "ppm", metadata: "ticket · high priority", detail: "Longer supporting detail occupies the stable slot without pushing either spatial rail.")
        ]
        let stablePrimary = OverlayMetrics.stablePrimaryHeight(
            lines: variedPrimaryLines,
            preferences: presentation,
            width: presentation.width.points
        )
        let individualPrimaryHeights = variedPrimaryLines.map({
            OverlayMetrics.primaryHeight(line: $0, preferences: presentation, width: presentation.width.points)
        })
        guard individualPrimaryHeights.allSatisfy({ stablePrimary >= $0 }),
              OverlayMetrics.stablePrimaryTitleHeight(
                  lines: variedPrimaryLines,
                  preferences: presentation,
                  width: presentation.width.points
              ) == variedPrimaryLines.map({
                  OverlayMetrics.primaryTitleHeight(
                      line: $0,
                      preferences: presentation,
                      width: presentation.width.points
                  )
              }).max() else {
            fputs("self-test failed: stable primary slot and ticket-key motion policy\n", stderr); exit(1)
        }
        var shortTemporaryPreferences = customPresentation
        shortTemporaryPreferences.alternativePreviews = 6
        shortTemporaryPreferences.customWidth = 420
        shortTemporaryPreferences.customHeight = 260
        let shortTemporarySize = OverlayMetrics.size(
            lines: previewLines,
            sticky: false,
            preferences: shortTemporaryPreferences,
            visibleFrame: CGRect(x: 0, y: 0, width: 1_200, height: 800)
        )
        let shortTemporaryNeighbors = OverlayMetrics.visibleAlternativeCount(
            lines: previewLines,
            preferences: shortTemporaryPreferences,
            width: shortTemporarySize.width,
            totalHeight: shortTemporarySize.height,
            sticky: false
        )
        guard shortTemporarySize == CGSize(width: 420, height: 260),
              shortTemporaryNeighbors < shortTemporaryPreferences.alternativePreviews else {
            fputs("self-test failed: short temporary card adaptive neighbor budget\n", stderr); exit(1)
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
        let shortStressLines = [
            TicketLine(
                key: "GLINT-24",
                state: "in-progress",
                title: "Make detailed ticket cards adapt precisely to long real-world titles without hiding alternatives",
                source: "ppm",
                metadata: "ticket · high priority · release 0.3",
                detail: "A deliberately long tracker detail verifies that the primary result remains legible while every alternative row is either fully visible or omitted from the rail."
            )
        ] + Array(previewLines.prefix(5))
        let shortVisibleFrame = CGRect(x: 0, y: 0, width: 900, height: 500)
        let shortOverlay = OverlayMetrics.size(
            lines: shortStressLines,
            sticky: true,
            preferences: presentation,
            visibleFrame: shortVisibleFrame
        )
        let shortAlternativeCount = OverlayMetrics.visibleAlternativeCount(
            lines: shortStressLines,
            preferences: presentation,
            width: shortOverlay.width,
            totalHeight: shortOverlay.height,
            sticky: true
        )
        let shortPrimaryHeight = OverlayMetrics.primaryHeight(
            line: shortStressLines[0],
            preferences: presentation,
            width: shortOverlay.width
        )
        let shortBodyBudget = OverlayMetrics.pinnedBodyHeight(totalHeight: shortOverlay.height)
        let shortUsedHeight = shortPrimaryHeight + OverlayMetrics.sectionSpacing +
            OverlayMetrics.alternativeBlockHeight(
                count: shortAlternativeCount,
                sticky: true,
                preferences: presentation
            )
        let shortNextHeight = shortPrimaryHeight + OverlayMetrics.sectionSpacing +
            OverlayMetrics.alternativeBlockHeight(
                count: shortAlternativeCount + 1,
                sticky: true,
                preferences: presentation
            )
        guard shortAlternativeCount > 0,
              shortAlternativeCount < presentation.alternativePreviews,
              shortPrimaryHeight <= shortBodyBudget,
              shortUsedHeight <= shortBodyBudget,
              shortNextHeight > shortBodyBudget else {
            fputs("self-test failed: short-display whole-row alternative budget\n", stderr); exit(1)
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
        let collapsedLineRelationship = OCRVisualLayout.relationship(
            firstRegion: .init(x: 0.1, y: 0.8, width: 0.2, height: 0.05),
            firstLine: 4,
            secondRegion: .init(x: 0.1, y: 0.4, width: 0.2, height: 0.05),
            secondLine: 4
        )
        guard !collapsedLineRelationship.isSameVisualLine,
              collapsedLineRelationship.lineGap == 1 else {
            fputs("self-test failed: collapsed OCR line relationship\n", stderr); exit(1)
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
              defaults.object(forKey: "lastPMAProject") == nil,
              defaults.object(forKey: "pinnedProject") == nil,
              defaults.object(forKey: "pinnedNumber") == nil else {
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
        print("Nuncid self-tests passed")
        exit(0)
    }
}

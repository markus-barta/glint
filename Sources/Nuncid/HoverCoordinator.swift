import AppKit
import CoreGraphics
import Foundation

enum QueuedScanLifecyclePolicy {
    static func shouldLaunch(
        queuedGeneration: Int,
        currentGeneration: Int,
        completedGeneration: Int
    ) -> Bool {
        queuedGeneration == currentGeneration && queuedGeneration != completedGeneration
    }

    static func shouldRetargetAfterPointerMovement(source: ScanInvocationSource) -> Bool {
        source == .explicitCommand
    }
}

enum ScanInvocationSource: Equatable {
    case explicitCommand
    case automaticHover
}

enum ScanCuePolicy {
    static func showsInvoked(for source: ScanInvocationSource) -> Bool {
        source == .explicitCommand
    }

    static func terminal(
        for source: ScanInvocationSource,
        hasResolvedResult: Bool,
        hasAnchor: Bool
    ) -> ScanTerminalFeedback {
        if hasResolvedResult { return hasAnchor ? .resolved : .none }
        return source == .explicitCommand ? .noMatch : .none
    }
}

enum DirectEntryResolutionPlanner {
    static func plan(project: String, key: String, trackers: [Tracker]) -> ResolutionPlan {
        ResolutionPlan(proposals: trackers.enumerated().map { index, tracker in
            CandidateProposal(
                spec: .issue(tracker: tracker, key: key),
                score: 1_000 - index,
                reasons: [ResolutionReason(
                    code: "pinned-direct-entry",
                    label: "entered in pinned card",
                    weight: 1_000 - index,
                    strength: .strong
                )],
                sourceOrder: index,
                inferredProject: project,
                learningEligibility: .userConfirmation
            )
        })
    }
}

enum PinnedScanOwnershipPolicy {
    static func shouldInvalidateForInput(alreadyClaimed: Bool) -> Bool {
        !alreadyClaimed
    }

    static func permitsCompletion(
        startedScanGeneration: Int,
        currentScanGeneration: Int,
        startedDirectGeneration: Int,
        currentDirectGeneration: Int,
        startedEditGeneration: Int,
        currentEditGeneration: Int
    ) -> Bool {
        startedScanGeneration == currentScanGeneration &&
            startedDirectGeneration == currentDirectGeneration &&
            startedEditGeneration == currentEditGeneration
    }
}

@MainActor final class HoverCoordinator {
    private enum Presentation { case temporary, pinned }

    private weak var appState: AppState?
    private let ocr = ScreenOCR()
    private let resolver = TicketResolver()
    private let evidencePlanner = TicketEvidencePlanner()
    private let scanFeedback = ScanFeedbackController()
    private let overlay: OverlayController
    private var timer: Timer?
    private var lastPosition = NSEvent.mouseLocation
    private var stableSince = Date()
    private var hoverScannedPosition: CGPoint?
    private var isScanning = false
    private var activeScanTask: Task<Void, Never>?
    private var lastPermissionPollAt = Date.distantPast
    private var scanGeneration = 0
    private var observedActivationPreferences: ActivationPreferences
    private var editState = PinnedEditState()
    private var editTask: Task<Void, Never>?
    private var directGeneration = 0
    private var pinnedEditGeneration = 0
    private var pinnedInputClaimedCurrentScan = false
    private struct PendingManualScan {
        let position: CGPoint
        let presentation: Presentation
        let generation: Int
        let source: ScanInvocationSource
        let invokedFeedbackShown: Bool
    }
    private var pendingManualScan: PendingManualScan?
    private struct ManualInspectionState {
        let anchor: CGPoint
        let startedAt: Date
    }
    private var manualInspection: ManualInspectionState?
    private var temporaryHideDeadline: Date?

    init(appState: AppState) {
        self.appState = appState
        observedActivationPreferences = appState.activationPreferences
#if DEBUG
        overlay = OverlayController(allowsCapture: CommandLine.arguments.contains("--capture-live"))
#else
        overlay = OverlayController()
#endif
        overlay.onCycleProject = { [weak self] direction in self?.cycleProject(direction) }
        overlay.onClose = { [weak self] in self?.closePinned() }
        overlay.onInput = { [weak self] event in self?.handleInput(event) }
        overlay.onSelectionChange = { [weak self] _ in self?.syncSelectionContext() }
        overlay.onTogglePin = { [weak self] in self?.togglePinFromOverlay() }
        overlay.onPinStateChange = { [weak self] pinned in
            guard let self, var preferences = self.appState?.popupInteractionPreferences,
                  preferences.restorePinned != pinned else { return }
            preferences.restorePinned = pinned
            self.appState?.popupInteractionPreferences = preferences
        }
        overlay.onPresentationPreferencesChange = { [weak self] preferences in
            guard let self, self.appState?.presentationPreferences != preferences else { return }
            self.appState?.presentationPreferences = preferences
        }
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.overlay.restorePinnedIfNeeded(shortcutLabel: self.pinShortcutLabel)
        }
    }

    func clearCache() { Task { await resolver.clearCache() } }

    func setHoverScanningEnabled(_ enabled: Bool) {
        resetHoverActivation()
        appState?.activity = enabled ? "Hover on" : "Hover off"
    }

    func resetHoverActivation() {
        scanGeneration += 1
        activeScanTask?.cancel()
        pendingManualScan = nil
        clearManualInspection()
        hoverScannedPosition = nil
        lastPosition = NSEvent.mouseLocation
        stableSince = Date()
        temporaryHideDeadline = nil
        overlay.hide()
        scanFeedback.cancel()
        appState?.setHoverMatchFound(false)
        appState?.activity = "Ready"
    }

    func performInspectCommand() {
        guard appState?.screenRecordingGranted == true else {
            appState?.requestScreenRecording(); return
        }
        directGeneration += 1
        let presentation: Presentation = overlay.isSticky ? .pinned : .temporary
        if presentation == .pinned { beginPinnedScanOwnership() }
        if isScanning {
            scanGeneration += 1
            activeScanTask?.cancel()
            let position = NSEvent.mouseLocation
            let showsFeedback = appState?.activationPreferences.scanFeedbackEnabled == true
            if showsFeedback { scanFeedback.invoked(at: position) }
            pendingManualScan = PendingManualScan(
                position: position,
                presentation: presentation,
                generation: scanGeneration,
                source: .explicitCommand,
                invokedFeedbackShown: showsFeedback
            )
            if presentation == .pinned { overlay.showPinnedStatus("Reading near pointer…") }
            return
        }
        scanGeneration += 1
        _ = trigger(
            at: NSEvent.mouseLocation,
            presentation: presentation,
            source: .explicitCommand,
            requiresStablePointer: false
        )
    }

    func performPinCommand() {
        let state: PanelInteractionState = overlay.isSticky
            ? (overlay.isActive ? .pinnedActive : .pinnedInactive)
            : (overlay.isVisible ? .temporary : .hidden)
        let action = PinCommandPolicy.action(for: state)
        if PinCommandPolicy.clearsManualInspection(for: action) { clearManualInspection() }
        switch action {
        case .closePinned:
            closePinned(); return
        case .focusPinned:
            overlay.focusPinned()
            appState?.activity = overlay.selectedLine.map { "Pinned · \($0.title)" } ?? "Pinned navigator"
            return
        case .pinTemporary:
            resetEditing()
            beginPinnedScanOwnership()
            overlay.pin(shortcutLabel: pinShortcutLabel)
            syncSelectionContext()
            appState?.activity = "Pinned"
            return
        case .openPinned:
            resetEditing()
            beginPinnedScanOwnership()
        }
        overlay.openPinned(shortcutLabel: pinShortcutLabel)
        appState?.activity = "Pinned · reading near pointer…"
        guard appState?.screenRecordingGranted == true else {
            overlay.showPinnedStatus("Screen Recording permission is required")
            appState?.requestScreenRecording()
            return
        }
        if isScanning {
            scanGeneration += 1
            activeScanTask?.cancel()
            let position = NSEvent.mouseLocation
            let showsFeedback = appState?.activationPreferences.scanFeedbackEnabled == true
            if showsFeedback { scanFeedback.invoked(at: position) }
            pendingManualScan = PendingManualScan(
                position: position,
                presentation: .pinned,
                generation: scanGeneration,
                source: .explicitCommand,
                invokedFeedbackShown: showsFeedback
            )
        } else {
            scanGeneration += 1
            _ = trigger(
                at: NSEvent.mouseLocation,
                presentation: .pinned,
                source: .explicitCommand,
                requiresStablePointer: false
            )
        }
    }

    private func tick() {
        if Date().timeIntervalSince(lastPermissionPollAt) >= 1 {
            let granted = CGPreflightScreenCaptureAccess()
            if appState?.screenRecordingGranted != granted {
                appState?.screenRecordingGranted = granted
                if !granted {
                    scanGeneration += 1
                    activeScanTask?.cancel()
                    pendingManualScan = nil
                    clearManualInspection()
                    scanFeedback.cancel()
                    if !overlay.isSticky { overlay.hide() }
                    appState?.activity = overlay.isSticky ? "Pinned navigator" : "Ready"
                }
            }
            lastPermissionPollAt = Date()
        }
        if overlay.isSticky {
            // Sticky presentation owns its own local Escape handling and must
            // never inherit the temporary card's movement/lifetime state.
            clearManualInspection()
            return
        }
        let now = Date()
        let position = NSEvent.mouseLocation
        let moved = hypot(position.x - lastPosition.x, position.y - lastPosition.y) > 4
        let manualLifetimeExpired = manualInspection.map { now.timeIntervalSince($0.startedAt) >= ManualInspectionPolicy.lifetime } ?? false
        if overlay.isVisible {
            if overlay.containsPointer {
                temporaryHideDeadline = nil
                lastPosition = position
                stableSince = now
                return
            }
            if TemporaryOverlayLifetimePolicy.shouldHide(
                deadline: temporaryHideDeadline,
                now: now,
                pointerInside: false
            ) {
                temporaryHideDeadline = nil
                dismissManualInspection()
                return
            }
            if temporaryHideDeadline != nil { return }
            if TemporaryOverlayLifetimePolicy.shouldScheduleHide(
                isVisible: true,
                isPinned: false,
                pointerInside: false,
                movedFromLastPosition: moved,
                manualLifetimeExpired: manualLifetimeExpired
            ) {
                temporaryHideDeadline = now.addingTimeInterval(TemporaryOverlayLifetimePolicy.exitGrace)
                lastPosition = position
                stableSince = now
                return
            }
        }
        if let manualInspection {
            let distance = hypot(position.x - manualInspection.anchor.x, position.y - manualInspection.anchor.y)
            if pendingManualScan != nil,
               hypot(position.x - lastPosition.x, position.y - lastPosition.y) > 4 {
                invalidateForPointerMovement(at: position)
                return
            }
            if ManualInspectionPolicy.shouldDismiss(
                distanceFromAnchor: distance,
                elapsed: now.timeIntervalSince(manualInspection.startedAt)
            ) {
                dismissManualInspection()
            }
            return
        }
        let preferences = appState?.activationPreferences ?? .defaults
        if preferences != observedActivationPreferences {
            observedActivationPreferences = preferences
            scanGeneration += 1
            activeScanTask?.cancel()
            pendingManualScan = nil
            hoverScannedPosition = nil
            stableSince = now
            overlay.hide()
            scanFeedback.cancel()
            appState?.activity = "Ready"
        }
        if moved {
            invalidateForPointerMovement(at: position)
        }
#if DEBUG
        if CommandLine.arguments.contains("--menu-hover-active-probe") ||
            CommandLine.arguments.contains("--menu-match-probe") { return }
#endif
        guard appState?.screenRecordingGranted == true else { return }
        guard HoverInvocationPolicy.shouldTrigger(
            preferences: preferences,
            hoverEnabled: appState?.hoverScanningEnabled == true,
            stableDuration: now.timeIntervalSince(stableSince),
            locationAlreadyScanned: hoverScannedPosition != nil
        ) else { return }
        switch preferences.mode {
        case .off, .pressToScan:
            return
        case .toggleHover:
            if trigger(at: position, presentation: .temporary, source: .automaticHover, requiresStablePointer: true) {
                hoverScannedPosition = position
            }
        }
    }

    @discardableResult
    private func trigger(
        at position: CGPoint,
        presentation: Presentation,
        source: ScanInvocationSource,
        showInvokedCue: Bool = true,
        requiresStablePointer: Bool
    ) -> Bool {
        guard !isScanning, let plan = CapturePlan.around(position) else { return false }
        guard CGPreflightScreenCaptureAccess() else { appState?.screenRecordingGranted = false; return false }
        let generation = scanGeneration
        let startedDirectGeneration = directGeneration
        let startedEditGeneration = pinnedEditGeneration
        if presentation == .pinned { pinnedInputClaimedCurrentScan = false }
        // Capture once per accepted scan (never on the 20 Hz pointer timer). Keeping this
        // uncached preserves the foreground window title that belongs to this invocation.
        let foreground = ForegroundApplicationContext.capture()
        if presentation == .temporary, !requiresStablePointer {
            manualInspection = ManualInspectionState(anchor: position, startedAt: Date())
            lastPosition = position
        }
        isScanning = true; appState?.activity = "Reading near cursor…"
        if appState?.activationPreferences.scanFeedbackEnabled == true,
           showInvokedCue,
           ScanCuePolicy.showsInvoked(for: source) {
            scanFeedback.invoked(at: position)
        }
        if presentation == .pinned, overlay.isSticky { overlay.showPinnedStatus("Reading near pointer…") }
        activeScanTask = Task {
            defer { finishScan(completedGeneration: generation) }
            let fragments = await ocr.recognizeFragments(plan: plan)
            guard !Task.isCancelled else { return }
            let input = Self.contextInput(from: fragments)
            let tokens = TokenParser.parse(input)
            let context = ResolutionContext.load()
            let history = ResolutionHistoryStore.load()
            let resolutionPlan = await evidencePlanner.plan(
                input: input,
                context: context,
                pinned: PinnedTicketContext.load(fallback: context),
                foreground: foreground,
                history: history
            )
            guard !Task.isCancelled else { return }
            let anchorSourceOrders = Set(ScanAnchorPolicy.sourceOrders(tokens: tokens, plan: resolutionPlan))
            let anchorPairs = tokens.filter { anchorSourceOrders.contains($0.sourceOrder) }.compactMap { token in
                ScanFeedbackAnchor(token: token, fragments: fragments).map { (token.sourceOrder, $0) }
            }
            let anchorsBySourceOrder = anchorPairs.reduce(into: [Int: ScanFeedbackAnchor]()) { result, pair in
                result[pair.0] = pair.1
            }
            let selectedAnchor = resolutionPlan.proposals.first.flatMap { anchorsBySourceOrder[$0.sourceOrder] }
            guard ScanFeedbackLifecyclePolicy.permits(
                .recognized,
                startedGeneration: generation,
                currentGeneration: scanGeneration
            ) else { return }
            if appState?.activationPreferences.scanFeedbackEnabled == true {
                scanFeedback.recognized(anchors: anchorPairs.map(\.1), selected: selectedAnchor)
            }
            let resolved = await resolver.resolve(resolutionPlan)
            guard !Task.isCancelled else { return }
            let terminalEvent: ScanFeedbackLifecycleEvent = resolved.isEmpty ? .noMatch : .resolved
            guard ScanFeedbackLifecyclePolicy.permits(
                terminalEvent,
                startedGeneration: generation,
                currentGeneration: scanGeneration
            ) else { return }
            let lines = Self.presentationLines(from: resolved)
            if let first = resolved.first {
                recordLearningIfEligible(first, in: resolutionPlan, foreground: foreground)
            }
            if appState?.activationPreferences.scanFeedbackEnabled == true {
                guard ScanFeedbackLifecyclePolicy.permits(
                    terminalEvent,
                    startedGeneration: generation,
                    currentGeneration: scanGeneration
                ) else { return }
                let resultAnchor = resolved.first.flatMap { anchorsBySourceOrder[$0.proposal.sourceOrder] ?? selectedAnchor }
                switch ScanCuePolicy.terminal(
                    for: source,
                    hasResolvedResult: !resolved.isEmpty,
                    hasAnchor: resultAnchor != nil
                ) {
                case .resolved:
                    guard let anchor = resultAnchor else { break }
                    scanFeedback.resolved(anchor: anchor)
                case .noMatch:
                    scanFeedback.noMatch()
                case .none:
                    scanFeedback.cancel()
                }
            }
            if presentation == .pinned {
                guard overlay.isSticky,
                      PinnedScanOwnershipPolicy.permitsCompletion(
                        startedScanGeneration: generation,
                        currentScanGeneration: scanGeneration,
                        startedDirectGeneration: startedDirectGeneration,
                        currentDirectGeneration: directGeneration,
                        startedEditGeneration: startedEditGeneration,
                        currentEditGeneration: pinnedEditGeneration
                      ) else { return }
                if lines.isEmpty {
                    overlay.showPinnedStatus(tokens.isEmpty ? "No nearby ticket token" : "No real ticket match")
                    appState?.activity = tokens.isEmpty ? "No nearby ticket token" : "No match"
                } else {
                    overlay.replacePinnedResults(lines); syncSelectionContext()
                    appState?.activity = lines.first?.title ?? "Pinned"
                }
                return
            }
            guard !overlay.isSticky,
                  (!requiresStablePointer || hypot(NSEvent.mouseLocation.x - position.x, NSEvent.mouseLocation.y - position.y) <= 4) else { return }
            if lines.isEmpty {
                if source == .automaticHover { appState?.setHoverMatchFound(false) }
                overlay.hide(); clearManualInspection(); appState?.activity = tokens.isEmpty ? "No nearby ticket token" : "No match"
            } else {
                if source == .automaticHover { appState?.setHoverMatchFound(true) }
                overlay.show(lines, near: position, shortcutLabel: pinShortcutLabel)
                temporaryHideDeadline = nil
                appState?.activity = lines.first?.title ?? "Ready"
            }
        }
        return true
    }

    private func finishScan(completedGeneration: Int) {
        isScanning = false
        activeScanTask = nil
        guard let pending = pendingManualScan else { return }
        pendingManualScan = nil
        guard QueuedScanLifecyclePolicy.shouldLaunch(
            queuedGeneration: pending.generation,
            currentGeneration: scanGeneration,
            completedGeneration: completedGeneration
        ) else {
            appState?.activity = overlay.isSticky ? "Pinned navigator" : "Ready"
            return
        }
        if !trigger(
            at: pending.position,
            presentation: pending.presentation,
            source: pending.source,
            showInvokedCue: !pending.invokedFeedbackShown,
            requiresStablePointer: false
        ) {
            appState?.activity = overlay.isSticky ? "Pinned navigator" : "Ready"
        }
    }

    private func recordLearningIfEligible(
        _ resolved: ResolvedCandidate,
        in plan: ResolutionPlan,
        foreground: ForegroundApplicationContext?
    ) {
        guard let decision = plan.learningDecision(for: resolved.proposal) else { return }
        ResolutionHistoryStore.record(decision, bundleIdentifier: foreground?.bundleIdentifier)
        guard let project = resolved.proposal.inferredProject,
              case let .issue(tracker, _) = resolved.proposal.spec else { return }
        var context = ResolutionContext.load()
        context.saw(project: project, on: tracker)
    }

    private var pinShortcutLabel: String { appState?.pinHotKey?.label ?? "Pin shortcut" }

    private func togglePinFromOverlay() {
        if overlay.isSticky {
            resetEditing()
            overlay.unpin()
            clearManualInspection()
            temporaryHideDeadline = nil
            lastPosition = NSEvent.mouseLocation
            stableSince = Date()
            appState?.activity = overlay.selectedLine?.title ?? "Ready"
            return
        }
        resetEditing()
        beginPinnedScanOwnership()
        temporaryHideDeadline = nil
        overlay.pin(shortcutLabel: pinShortcutLabel)
        syncSelectionContext()
        appState?.activity = "Pinned"
    }

    private func cycleProject(_ direction: Int) {
        syncSelectionContext()
        guard let number = currentNumber else {
            overlay.setInput("Type a ticket number first"); return
        }
        let projects = ProjectDescriptor.known
        let currentIndex = projects.firstIndex(where: { $0.key == currentProject }) ?? 0
        let next = projects[(currentIndex + direction + projects.count) % projects.count]
        currentProject = next.key
        resolveDirect(project: next, number: number)
    }

    private var currentProject: String {
        get {
            if let (project, _) = overlay.selectedLine.flatMap({ Self.projectAndNumber(from: $0.key) }) { return project }
            return PinnedTicketContext.load().project
        }
        set {
            var context = PinnedTicketContext.load(); context.project = newValue; context.persist()
        }
    }
    private var currentNumber: Int? {
        if let (_, number) = overlay.selectedLine.flatMap({ Self.projectAndNumber(from: $0.key) }) { return number }
        return PinnedTicketContext.load().number
    }

    private func syncSelectionContext() {
        guard let (project, number) = overlay.selectedLine.flatMap({ Self.projectAndNumber(from: $0.key) }) else { return }
        PinnedTicketContext(project: project, number: number).persist()
    }

    private func handleInput(_ event: PinnedInputEvent) {
        if eventClaimsPinnedResults(event) {
            pinnedEditGeneration += 1
            directGeneration += 1
            claimPinnedInputOwnershipIfNeeded()
        }
        switch event {
        case let .digits(value):
            editState.appendDigits(value)
            overlay.setInput("\(currentProject)-\(editState.numberBuffer ?? "")")
            scheduleResolve(after: 0.25)
        case let .letters(value):
            editState.appendLetters(value, currentProject: currentProject)
            previewProjectAndSchedule()
        case .backspace:
            switch editState.backspace() {
            case .project:
                previewProjectAndSchedule()
            case .number:
                let value = editState.numberBuffer ?? ""
                overlay.setInput(value.isEmpty ? nil : "\(currentProject)-\(value)")
                if !value.isEmpty { scheduleResolve(after: 0.25) }
            case .none:
                break
            }
        case .submit:
            editTask?.cancel(); commitEditing()
        case .escape:
            if editState.hasInput {
                if let projectBeforeQuery = editState.projectBeforeQuery { currentProject = projectBeforeQuery }
                resetEditing(); overlay.setInput(nil)
            } else { closePinned() }
        case let .paste(value):
            applyPaste(value)
        }
    }

    private func previewProjectAndSchedule() {
        editTask?.cancel()
        guard !editState.projectQuery.isEmpty else { overlay.setInput(nil); return }
        let match = ProjectMatcher.bestMatch(for: editState.projectQuery, current: currentProject)
        overlay.setInput(editState.projectQuery, projectPreview: match?.key)
        scheduleResolve(after: 0.32)
    }

    private func scheduleResolve(after delay: TimeInterval) {
        editTask?.cancel()
        editTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.commitEditing() }
        }
    }

    private func commitEditing() {
        if !editState.projectQuery.isEmpty {
            guard let match = ProjectMatcher.bestMatch(for: editState.projectQuery, current: currentProject) else { return }
            currentProject = match.key
            let number = currentNumber
            editState.clear()
            if let number { resolveDirect(project: match, number: number) }
            else { overlay.setInput(match.key) }
            return
        }
        guard let numberBuffer = editState.numberBuffer, let number = Int(numberBuffer), number > 0 else { return }
        editState.numberBuffer = nil
        PinnedTicketContext(project: currentProject, number: number).persist()
        let project = ProjectDescriptor.known.first(where: { $0.key == currentProject })
            ?? ProjectDescriptor(key: currentProject, name: currentProject, aliases: [], tracker: ResolutionContext.load().lastSeenTracker)
        resolveDirect(project: project, number: number)
    }

    private func applyPaste(_ raw: String) {
        guard let token = TokenParser.parse([raw.uppercased()]).first else {
            overlay.setInput("Paste did not contain a ticket"); NSSound.beep(); return
        }
        switch token.kind {
        case let .issueKey(project, number):
            PinnedTicketContext(project: project, number: number).persist()
            let descriptor = ProjectDescriptor.known.first(where: { $0.key == project })
                ?? ProjectDescriptor(key: project, name: project, aliases: [], tracker: CandidatePlanner.tracker(for: project, context: .load()))
            resetEditing(); resolveDirect(project: descriptor, number: number)
        case let .hashNumber(number), let .bareNumber(number):
            PinnedTicketContext(project: currentProject, number: number).persist()
            let descriptor = ProjectDescriptor.known.first(where: { $0.key == currentProject })
                ?? ProjectDescriptor(key: currentProject, name: currentProject, aliases: [], tracker: ResolutionContext.load().lastSeenTracker)
            resetEditing(); resolveDirect(project: descriptor, number: number)
        case .version:
            overlay.setInput("Paste did not contain a ticket"); NSSound.beep()
        }
    }

    private func resolveDirect(project: ProjectDescriptor, number: Int) {
        claimPinnedInputOwnershipIfNeeded()
        editTask?.cancel(); directGeneration += 1
        let generation = directGeneration
        let key = "\(project.key)-\(number)"
        PinnedTicketContext(project: project.key, number: number).persist()
        overlay.setInput(key); appState?.activity = "Resolving \(key)…"
        var trackers = [project.tracker]
        if !CandidatePlanner.ppmProjects.contains(project.key), !CandidatePlanner.pmaProjects.contains(project.key) {
            trackers.append(project.tracker.other)
        }
        let plan = DirectEntryResolutionPlanner.plan(project: project.key, key: key, trackers: trackers)
        let foreground = ForegroundApplicationContext.capture()
        Task {
            let resolved = await resolver.resolve(plan).first
            guard generation == directGeneration, overlay.isSticky else { return }
            if let resolved,
               case let .issue(tracker, _) = resolved.proposal.spec {
                let line = resolved.line
                overlay.replacePinnedResults([line], selecting: line.key)
                if let decision = plan.learningDecision(for: resolved.proposal, userConfirmed: true) {
                    ResolutionHistoryStore.record(decision, bundleIdentifier: foreground?.bundleIdentifier)
                }
                var context = ResolutionContext.load(); context.saw(project: project.key, on: tracker)
                PinnedTicketContext(project: project.key, number: number).persist()
                appState?.activity = line.title
            } else {
                overlay.showPinnedStatus("No real match for \(key)")
                overlay.setInput(key)
                appState?.activity = "No match for \(key)"
            }
        }
    }

    private func resetEditing() {
        editTask?.cancel(); editTask = nil; editState.clear()
    }

    private func beginPinnedScanOwnership() {
        pinnedInputClaimedCurrentScan = false
    }

    private func claimPinnedInputOwnershipIfNeeded() {
        guard PinnedScanOwnershipPolicy.shouldInvalidateForInput(
            alreadyClaimed: pinnedInputClaimedCurrentScan
        ) else { return }
        pinnedInputClaimedCurrentScan = true
        scanGeneration += 1
        activeScanTask?.cancel()
        pendingManualScan = nil
        scanFeedback.cancel()
        appState?.activity = "Pinned · editing"
    }

    private func eventClaimsPinnedResults(_ event: PinnedInputEvent) -> Bool {
        if case .escape = event { return false }
        return true
    }

    private func closePinned() {
        clearManualInspection()
        pendingManualScan = nil
        scanGeneration += 1; activeScanTask?.cancel(); directGeneration += 1; resetEditing(); overlay.closePinned(); scanFeedback.cancel()
        lastPosition = NSEvent.mouseLocation; stableSince = Date(); hoverScannedPosition = nil; appState?.setHoverMatchFound(false); appState?.activity = "Ready"
    }

    private func clearManualInspection() {
        manualInspection = nil
    }

    private func dismissManualInspection() {
        clearManualInspection()
        scanGeneration += 1
        activeScanTask?.cancel()
        pendingManualScan = nil
        overlay.hide()
        temporaryHideDeadline = nil
        scanFeedback.cancel()
        appState?.activity = "Ready"
        lastPosition = NSEvent.mouseLocation
        stableSince = Date()
        hoverScannedPosition = nil
        appState?.setHoverMatchFound(false)
    }

    private func invalidateForPointerMovement(at position: CGPoint) {
        scanGeneration += 1
        activeScanTask?.cancel()
        scanFeedback.cancel()
        if let pending = pendingManualScan,
           QueuedScanLifecyclePolicy.shouldRetargetAfterPointerMovement(source: pending.source) {
            let showsFeedback = appState?.activationPreferences.scanFeedbackEnabled == true
            if showsFeedback { scanFeedback.invoked(at: position) }
            pendingManualScan = PendingManualScan(
                position: position,
                presentation: pending.presentation,
                generation: scanGeneration,
                source: pending.source,
                invokedFeedbackShown: showsFeedback
            )
        } else {
            pendingManualScan = nil
        }
        clearManualInspection()
        lastPosition = position
        stableSince = Date()
        hoverScannedPosition = nil
        appState?.setHoverMatchFound(false)
        overlay.hide()
        temporaryHideDeadline = nil
        appState?.activity = "Ready"
    }

    private static func projectAndNumber(from key: String) -> (String, Int)? {
        guard let token = TokenParser.parse([key]).first,
              case let .issueKey(project, number) = token.kind else { return nil }
        return (project, number)
    }

    private static func contextInput(from fragments: [RecognizedTextFragment]) -> OCRContextInput {
        OCRContextInput(fragments: fragments.enumerated().map { index, fragment in
            OCRContextFragment(
                text: fragment.text,
                lineIndex: index,
                order: index,
                confidence: Double(fragment.confidence),
                region: OCRNormalizedRegion(
                    x: fragment.normalizedBounds.minX,
                    y: fragment.normalizedBounds.minY,
                    width: fragment.normalizedBounds.width,
                    height: fragment.normalizedBounds.height
                )
            )
        })
    }

    private static func presentationLines(from resolved: [ResolvedCandidate]) -> [TicketLine] {
        HoverResultPolicy.visible(from: resolved.map { result in
            let provenance = result.proposal.provenanceSummary
            let metadata = [result.line.metadata, provenance.isEmpty ? nil : "Matched: \(provenance)"]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            return TicketLine(
                key: result.line.key,
                state: result.line.state,
                title: result.line.title,
                source: result.line.source,
                metadata: metadata,
                detail: result.line.detail,
                destination: result.line.destination
            )
        })
    }

}

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
    private var lastScanAt = Date.distantPast
    private var dwellScannedPosition: CGPoint?
    private var isScanning = false
    private var lastPermissionPollAt = Date.distantPast
    private var scanGeneration = 0
    private var observedActivationPreferences: ActivationPreferences
    private var editState = PinnedEditState()
    private var editTask: Task<Void, Never>?
    private var directGeneration = 0
    private struct PendingManualScan {
        let position: CGPoint
        let presentation: Presentation
        let generation: Int
    }
    private var pendingManualScan: PendingManualScan?
    private struct ManualInspectionState {
        let anchor: CGPoint
        let startedAt: Date
    }
    private var manualInspection: ManualInspectionState?

    init(appState: AppState) {
        self.appState = appState
        observedActivationPreferences = appState.activationPreferences
#if DEBUG
        overlay = OverlayController(allowsCapture: CommandLine.arguments.contains("--capture-live"))
#else
        overlay = OverlayController()
#endif
        overlay.onCycleProject = { [weak self] direction in self?.cycleProject(direction) }
        overlay.onInput = { [weak self] event in self?.handleInput(event) }
        overlay.onSelectionChange = { [weak self] _ in self?.syncSelectionContext() }
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func clearCache() { Task { await resolver.clearCache() } }

    func performInspectCommand() {
        guard appState?.screenRecordingGranted == true else {
            appState?.requestScreenRecording(); return
        }
        directGeneration += 1
        let presentation: Presentation = overlay.isSticky ? .pinned : .temporary
        if isScanning {
            scanGeneration += 1
            pendingManualScan = PendingManualScan(
                position: NSEvent.mouseLocation,
                presentation: presentation,
                generation: scanGeneration
            )
            if presentation == .pinned { overlay.showPinnedStatus("Reading near pointer…") }
            return
        }
        scanGeneration += 1
        _ = trigger(at: NSEvent.mouseLocation, presentation: presentation, requiresStablePointer: false)
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
            overlay.pin(shortcutLabel: pinShortcutLabel)
            syncSelectionContext()
            appState?.activity = "Pinned"
            return
        case .openPinned:
            resetEditing()
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
            pendingManualScan = PendingManualScan(
                position: NSEvent.mouseLocation,
                presentation: .pinned,
                generation: scanGeneration
            )
        } else {
            scanGeneration += 1; _ = trigger(at: NSEvent.mouseLocation, presentation: .pinned, requiresStablePointer: false)
        }
    }

    private func tick() {
        if Date().timeIntervalSince(lastPermissionPollAt) >= 1 {
            let granted = CGPreflightScreenCaptureAccess()
            if appState?.screenRecordingGranted != granted {
                appState?.screenRecordingGranted = granted
                if !granted {
                    scanGeneration += 1
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
        if let manualInspection {
            let distance = hypot(position.x - manualInspection.anchor.x, position.y - manualInspection.anchor.y)
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
            pendingManualScan = nil
            dwellScannedPosition = nil
            stableSince = now
            overlay.hide()
            scanFeedback.cancel()
            appState?.activity = "Ready"
        }
        if hypot(position.x - lastPosition.x, position.y - lastPosition.y) > 4 {
            pendingManualScan = nil
            lastPosition = position; stableSince = now; dwellScannedPosition = nil; scanGeneration += 1; overlay.hide(); scanFeedback.cancel()
            appState?.activity = "Ready"
        }
        guard appState?.screenRecordingGranted == true else { return }
        let heldModifiers = Self.hotKeyModifiers(from: NSEvent.modifierFlags)
        guard HoverInvocationPolicy.shouldTrigger(
            preferences: preferences,
            stableDuration: now.timeIntervalSince(stableSince),
            dwellAlreadyScanned: dwellScannedPosition != nil,
            heldModifiers: heldModifiers,
            elapsedSinceLastScan: now.timeIntervalSince(lastScanAt)
        ) else { return }
        switch preferences.mode {
        case .off:
            return
        case .dwell:
            if trigger(at: position, presentation: .temporary, requiresStablePointer: true) { dwellScannedPosition = position }
        case .hold:
            _ = trigger(at: position, presentation: .temporary, requiresStablePointer: true)
        case .continuous:
            _ = trigger(at: position, presentation: .temporary, requiresStablePointer: true)
        }
    }

    @discardableResult
    private func trigger(at position: CGPoint, presentation: Presentation, requiresStablePointer: Bool) -> Bool {
        guard !isScanning, let plan = CapturePlan.around(position) else { return false }
        guard CGPreflightScreenCaptureAccess() else { appState?.screenRecordingGranted = false; return false }
        let generation = scanGeneration
        // Capture once per accepted scan (never on the 20 Hz pointer timer). Keeping this
        // uncached preserves the foreground window title that belongs to this invocation.
        let foreground = ForegroundApplicationContext.capture()
        if presentation == .temporary, !requiresStablePointer {
            manualInspection = ManualInspectionState(anchor: position, startedAt: Date())
        }
        isScanning = true; lastScanAt = Date(); appState?.activity = "Reading near cursor…"
        if appState?.activationPreferences.scanFeedbackEnabled == true { scanFeedback.invoked(at: position) }
        if presentation == .pinned, overlay.isSticky { overlay.showPinnedStatus("Reading near pointer…") }
        Task {
            defer { finishScan(completedGeneration: generation) }
            let fragments = await ocr.recognizeFragments(plan: plan)
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
                switch ScanTerminalFeedbackPolicy.event(hasResolvedResult: !resolved.isEmpty, hasAnchor: resultAnchor != nil) {
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
                guard overlay.isSticky else { return }
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
                overlay.hide(); clearManualInspection(); appState?.activity = tokens.isEmpty ? "No nearby ticket token" : "No match"
            } else {
                overlay.show(lines, near: position, shortcutLabel: pinShortcutLabel)
                appState?.activity = lines.first?.title ?? "Ready"
            }
        }
        return true
    }

    private func finishScan(completedGeneration: Int) {
        isScanning = false
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
        if !trigger(at: pending.position, presentation: pending.presentation, requiresStablePointer: false) {
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
        editTask?.cancel(); directGeneration += 1
        let generation = directGeneration
        let key = "\(project.key)-\(number)"
        PinnedTicketContext(project: project.key, number: number).persist()
        overlay.setInput(key); appState?.activity = "Resolving \(key)…"
        Task {
            var trackers = [project.tracker]
            if !CandidatePlanner.ppmProjects.contains(project.key), !CandidatePlanner.pmaProjects.contains(project.key) {
                trackers.append(project.tracker.other)
            }
            var resolved: (GlintLine, Tracker)?
            for tracker in trackers {
                if let line = await resolver.resolve(.issue(tracker: tracker, key: key)) {
                    resolved = (line, tracker); break
                }
            }
            guard generation == directGeneration, overlay.isSticky else { return }
            if let (line, tracker) = resolved {
                overlay.replacePinnedResults([line], selecting: line.key)
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
    private func closePinned() {
        clearManualInspection()
        pendingManualScan = nil
        scanGeneration += 1; directGeneration += 1; resetEditing(); overlay.closePinned(); scanFeedback.cancel()
        lastPosition = NSEvent.mouseLocation; stableSince = Date(); dwellScannedPosition = nil; appState?.activity = "Ready"
    }

    private func clearManualInspection() {
        manualInspection = nil
    }

    private func dismissManualInspection() {
        clearManualInspection()
        scanGeneration += 1
        pendingManualScan = nil
        overlay.hide()
        scanFeedback.cancel()
        appState?.activity = "Ready"
        lastPosition = NSEvent.mouseLocation
        stableSince = Date()
        dwellScannedPosition = nil
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

    private static func presentationLines(from resolved: [ResolvedCandidate]) -> [GlintLine] {
        HoverResultPolicy.visible(from: resolved.map { result in
            let provenance = result.proposal.provenanceSummary
            let metadata = [result.line.metadata, provenance.isEmpty ? nil : "Matched: \(provenance)"]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            return GlintLine(
                key: result.line.key,
                state: result.line.state,
                title: result.line.title,
                source: result.line.source,
                metadata: metadata,
                detail: result.line.detail
            )
        })
    }

    private static func hotKeyModifiers(from flags: NSEvent.ModifierFlags) -> HotKeyModifiers {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var result: HotKeyModifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.shift) { result.insert(.shift) }
        return result
    }
}

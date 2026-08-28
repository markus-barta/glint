import AppKit
import CoreGraphics
import Foundation

@MainActor final class HoverCoordinator {
    private enum Presentation { case temporary, pinned }

    private weak var appState: AppState?
    private let ocr = ScreenOCR()
    private let resolver = TicketResolver()
    private let overlay: OverlayController
    private var timer: Timer?
    private var lastPosition = NSEvent.mouseLocation
    private var stableSince = Date()
    private var lastScanAt = Date.distantPast
    private var dwellScannedPosition: CGPoint?
    private var isScanning = false
    private var lastPermissionPollAt = Date.distantPast
    private var scanGeneration = 0
    private var optionWasHeld = false
    private var observedMode: TriggerMode
    private var numberBuffer: String?
    private var projectQuery = ""
    private var projectBeforeQuery: String?
    private var editTask: Task<Void, Never>?
    private var directGeneration = 0
    private var pendingManualScan: (CGPoint, Presentation)?

    init(appState: AppState) {
        self.appState = appState
        observedMode = appState.triggerMode
#if DEBUG
        overlay = OverlayController(allowsCapture: CommandLine.arguments.contains("--capture-live"))
#else
        overlay = OverlayController()
#endif
        overlay.onCycleProject = { [weak self] direction in self?.cycleProject(direction) }
        overlay.onInput = { [weak self] event in self?.handleInput(event) }
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
            pendingManualScan = (NSEvent.mouseLocation, presentation)
            if presentation == .pinned { overlay.showPinnedStatus("Reading near pointer…") }
            return
        }
        scanGeneration += 1
        _ = trigger(at: NSEvent.mouseLocation, presentation: presentation, requiresStablePointer: false)
    }

    func performPinCommand() {
        if overlay.isSticky {
            if overlay.isActive {
                closePinned()
            } else {
                overlay.focusPinned()
                appState?.activity = overlay.selectedLine.map { "Pinned · \($0.title)" } ?? "Pinned navigator"
            }
            return
        }
        resetEditing()
        if overlay.isVisible {
            overlay.pin(shortcutLabel: pinShortcutLabel)
            syncSelectionContext()
            appState?.activity = "Pinned"
            return
        }
        overlay.openPinned(shortcutLabel: pinShortcutLabel)
        appState?.activity = "Pinned · reading near pointer…"
        guard appState?.screenRecordingGranted == true else {
            overlay.showPinnedStatus("Screen Recording permission is required")
            appState?.requestScreenRecording()
            return
        }
        if isScanning {
            scanGeneration += 1; pendingManualScan = (NSEvent.mouseLocation, .pinned)
        } else {
            scanGeneration += 1; _ = trigger(at: NSEvent.mouseLocation, presentation: .pinned, requiresStablePointer: false)
        }
    }

    private func tick() {
        if Date().timeIntervalSince(lastPermissionPollAt) >= 1 {
            let granted = CGPreflightScreenCaptureAccess()
            if appState?.screenRecordingGranted != granted {
                appState?.screenRecordingGranted = granted
                if !granted { scanGeneration += 1; if !overlay.isSticky { overlay.hide() } }
            }
            lastPermissionPollAt = Date()
        }
        if overlay.isSticky { return }
        let mode = appState?.triggerMode ?? .dwell
        if mode != observedMode {
            observedMode = mode; scanGeneration += 1; dwellScannedPosition = nil; stableSince = Date(); optionWasHeld = false; overlay.hide()
        }
        let position = NSEvent.mouseLocation
        if hypot(position.x - lastPosition.x, position.y - lastPosition.y) > 4 {
            lastPosition = position; stableSince = Date(); dwellScannedPosition = nil; scanGeneration += 1; overlay.hide()
        }
        guard appState?.screenRecordingGranted == true else { return }
        switch mode {
        case .dwell:
            guard Date().timeIntervalSince(stableSince) >= 0.30, dwellScannedPosition == nil else { return }
            if trigger(at: position, presentation: .temporary, requiresStablePointer: true) { dwellScannedPosition = position }
        case .option:
            guard NSEvent.modifierFlags.contains(.option) else { optionWasHeld = false; return }
            optionWasHeld = true
            guard Date().timeIntervalSince(lastScanAt) >= 0.65 else { return }
            _ = trigger(at: position, presentation: .temporary, requiresStablePointer: true)
        case .always:
            guard Date().timeIntervalSince(lastScanAt) >= 0.65 else { return }
            _ = trigger(at: position, presentation: .temporary, requiresStablePointer: true)
        }
    }

    @discardableResult
    private func trigger(at position: CGPoint, presentation: Presentation, requiresStablePointer: Bool) -> Bool {
        guard !isScanning, let plan = CapturePlan.around(position) else { return false }
        guard CGPreflightScreenCaptureAccess() else { appState?.screenRecordingGranted = false; return false }
        let generation = scanGeneration
        isScanning = true; lastScanAt = Date(); appState?.activity = "Reading near cursor…"
        if presentation == .pinned, overlay.isSticky { overlay.showPinnedStatus("Reading near pointer…") }
        Task {
            defer { finishScan() }
            let recognized = await ocr.recognize(plan: plan)
            let tokens = TokenParser.parse(recognized)
            let lines = await resolve(tokens: tokens)
            guard generation == scanGeneration else { return }
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
                overlay.hide(); appState?.activity = tokens.isEmpty ? "No nearby ticket token" : "No match"
            } else {
                overlay.show(lines, near: position, shortcutLabel: pinShortcutLabel)
                appState?.activity = lines.first?.title ?? "Ready"
            }
        }
        return true
    }

    private func finishScan() {
        isScanning = false
        guard let pending = pendingManualScan else { return }
        pendingManualScan = nil
        _ = trigger(at: pending.0, presentation: pending.1, requiresStablePointer: false)
    }

    private func resolve(tokens: [NearbyToken]) async -> [GlintLine] {
        guard !tokens.isEmpty else { return [] }
        var context = ResolutionContext.load()
        var attempts: [GlintLine?] = []
        var realMatchCount = 0
        var candidateBudget = 16
        for token in tokens.sorted(by: { tokenPriority($0) < tokenPriority($1) }).prefix(12) {
            let specs = CandidatePlanner.candidates(for: token, context: context)
            if specs.isEmpty { continue }
            var matches: [GlintLine] = []
            for spec in specs where candidateBudget > 0 {
                candidateBudget -= 1
                let line = await resolver.resolve(spec); attempts.append(line)
                if let line { matches.append(line); realMatchCount += 1 }
                if realMatchCount >= HoverResultPolicy.maximumResults { break }
            }
            if let first = matches.first,
               let (project, _) = Self.projectAndNumber(from: first.key),
               let actualTracker = Tracker(rawValue: first.source) {
                context.saw(project: project, on: actualTracker)
            }
            if realMatchCount >= HoverResultPolicy.maximumResults || candidateBudget == 0 { break }
        }
        return HoverResultPolicy.visible(from: attempts)
    }

    private func tokenPriority(_ token: NearbyToken) -> Int {
        switch token.kind { case .issueKey: return 0; case .hashNumber, .bareNumber: return 1; case .version: return 2 }
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
            return UserDefaults.standard.string(forKey: "pinnedProject") ?? ResolutionContext.load().project(for: ResolutionContext.load().lastSeenTracker)
        }
        set { UserDefaults.standard.set(newValue, forKey: "pinnedProject") }
    }
    private var currentNumber: Int? {
        if let (_, number) = overlay.selectedLine.flatMap({ Self.projectAndNumber(from: $0.key) }) { return number }
        return UserDefaults.standard.object(forKey: "pinnedNumber") as? Int
    }

    private func syncSelectionContext() {
        guard let (project, number) = overlay.selectedLine.flatMap({ Self.projectAndNumber(from: $0.key) }) else { return }
        currentProject = project; UserDefaults.standard.set(number, forKey: "pinnedNumber")
    }

    private func handleInput(_ event: PinnedInputEvent) {
        switch event {
        case let .digits(value):
            projectQuery = ""; projectBeforeQuery = nil
            numberBuffer = (numberBuffer ?? "") + value
            overlay.setInput("\(currentProject)-\(numberBuffer ?? "")")
            scheduleResolve(after: 0.25)
        case let .letters(value):
            numberBuffer = nil
            if projectQuery.isEmpty { projectBeforeQuery = currentProject }
            projectQuery += value
            previewProjectAndSchedule()
        case .backspace:
            if !projectQuery.isEmpty {
                projectQuery.removeLast(); previewProjectAndSchedule()
            } else if var value = numberBuffer, !value.isEmpty {
                value.removeLast(); numberBuffer = value
                overlay.setInput(value.isEmpty ? nil : "\(currentProject)-\(value)")
                if !value.isEmpty { scheduleResolve(after: 0.25) }
            }
        case .submit:
            editTask?.cancel(); commitEditing()
        case .escape:
            if numberBuffer != nil || !projectQuery.isEmpty {
                if let projectBeforeQuery { currentProject = projectBeforeQuery }
                resetEditing(); overlay.setInput(nil)
            } else { closePinned() }
        case let .paste(value):
            applyPaste(value)
        }
    }

    private func previewProjectAndSchedule() {
        editTask?.cancel()
        guard !projectQuery.isEmpty else { overlay.setInput(nil); return }
        let match = ProjectMatcher.bestMatch(for: projectQuery, current: currentProject)
        overlay.setInput(projectQuery, projectPreview: match?.key)
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
        if !projectQuery.isEmpty {
            guard let match = ProjectMatcher.bestMatch(for: projectQuery, current: currentProject) else { return }
            currentProject = match.key
            let number = currentNumber
            projectQuery = ""; projectBeforeQuery = nil
            if let number { resolveDirect(project: match, number: number) }
            else { overlay.setInput(match.key) }
            return
        }
        guard let numberBuffer, let number = Int(numberBuffer), number > 0 else { return }
        self.numberBuffer = nil
        UserDefaults.standard.set(number, forKey: "pinnedNumber")
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
            currentProject = project; UserDefaults.standard.set(number, forKey: "pinnedNumber")
            let descriptor = ProjectDescriptor.known.first(where: { $0.key == project })
                ?? ProjectDescriptor(key: project, name: project, aliases: [], tracker: CandidatePlanner.tracker(for: project, context: .load()))
            resetEditing(); resolveDirect(project: descriptor, number: number)
        case let .hashNumber(number), let .bareNumber(number):
            UserDefaults.standard.set(number, forKey: "pinnedNumber")
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
                currentProject = project.key; UserDefaults.standard.set(number, forKey: "pinnedNumber")
                appState?.activity = line.title
            } else {
                overlay.showPinnedStatus("No real match for \(key)")
                overlay.setInput(key)
                appState?.activity = "No match for \(key)"
            }
        }
    }

    private func resetEditing() {
        editTask?.cancel(); editTask = nil; numberBuffer = nil; projectQuery = ""; projectBeforeQuery = nil
    }
    private func closePinned() {
        scanGeneration += 1; directGeneration += 1; resetEditing(); overlay.closePinned()
        lastPosition = NSEvent.mouseLocation; stableSince = Date(); dwellScannedPosition = nil; appState?.activity = "Ready"
    }

    private static func projectAndNumber(from key: String) -> (String, Int)? {
        guard let token = TokenParser.parse([key]).first,
              case let .issueKey(project, number) = token.kind else { return nil }
        return (project, number)
    }
}

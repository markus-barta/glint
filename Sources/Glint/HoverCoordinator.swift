import AppKit
import CoreGraphics
import Foundation

@MainActor final class HoverCoordinator {
    private weak var appState: AppState?
    private let ocr = ScreenOCR(); private let resolver = TicketResolver(); private let overlay = OverlayController()
    private var timer: Timer?; private var lastPosition = NSEvent.mouseLocation; private var stableSince = Date()
    private var lastScanAt = Date.distantPast; private var dwellScannedPosition: CGPoint?; private var isScanning = false
    private var lastPermissionPollAt = Date.distantPast
    private var scanGeneration = 0
    private var optionWasHeld = false
    private var observedMode: TriggerMode

    init(appState: AppState) {
        self.appState = appState
        observedMode = appState.triggerMode
    }
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }
    func clearCache() { Task { await resolver.clearCache() } }

    private func tick() {
        if Date().timeIntervalSince(lastPermissionPollAt) >= 1 {
            let granted = CGPreflightScreenCaptureAccess()
            if appState?.screenRecordingGranted != granted {
                appState?.screenRecordingGranted = granted
                if !granted { scanGeneration += 1; overlay.hide() }
            }
            lastPermissionPollAt = Date()
        }
        let mode = appState?.triggerMode ?? .dwell
        if mode != observedMode {
            observedMode = mode
            scanGeneration += 1
            dwellScannedPosition = nil
            stableSince = Date()
            optionWasHeld = false
            overlay.hide()
        }
        let position = NSEvent.mouseLocation
        if hypot(position.x - lastPosition.x, position.y - lastPosition.y) > 4 {
            lastPosition = position; stableSince = Date(); dwellScannedPosition = nil
            scanGeneration += 1
            overlay.hide()
        }
        guard appState?.screenRecordingGranted == true else { return }
        switch mode {
        case .dwell:
            guard Date().timeIntervalSince(stableSince) >= 0.30, dwellScannedPosition == nil else { return }
            if trigger(at: position, mode: mode) { dwellScannedPosition = position }
        case .option:
            guard NSEvent.modifierFlags.contains(.option) else {
                if optionWasHeld { scanGeneration += 1; overlay.hide() }
                optionWasHeld = false
                return
            }
            optionWasHeld = true
            guard Date().timeIntervalSince(lastScanAt) >= 0.65 else { return }
            _ = trigger(at: position, mode: mode)
        case .always:
            guard Date().timeIntervalSince(lastScanAt) >= 0.65 else { return }
            _ = trigger(at: position, mode: mode)
        }
    }

    @discardableResult
    private func trigger(at position: CGPoint, mode: TriggerMode? = nil) -> Bool {
        guard !isScanning, let plan = CapturePlan.around(position) else { return false }
        guard CGPreflightScreenCaptureAccess() else { appState?.screenRecordingGranted = false; return false }
        let triggerMode = mode ?? appState?.triggerMode ?? .dwell
        let generation = scanGeneration
        isScanning = true; lastScanAt = Date(); appState?.activity = "Reading near cursor…"
        Task {
            defer { isScanning = false }
            let recognized = await ocr.recognize(plan: plan)
            let tokens = TokenParser.parse(recognized)
            let lines = await resolve(tokens: tokens)
            guard generation == scanGeneration,
                  appState?.triggerMode == triggerMode,
                  hypot(NSEvent.mouseLocation.x - position.x, NSEvent.mouseLocation.y - position.y) <= 4,
                  triggerMode != .option || NSEvent.modifierFlags.contains(.option) else {
                appState?.activity = "Ready"
                return
            }
            if lines.isEmpty { overlay.hide(); appState?.activity = tokens.isEmpty ? "No nearby ticket token" : "No match" }
            else { overlay.show(lines, near: position); appState?.activity = lines.first?.title ?? "Ready" }
        }
        return true
    }

    private func resolve(tokens: [NearbyToken]) async -> [GlintLine] {
        guard !tokens.isEmpty else { return [] }
        var context = ResolutionContext.load()
        var matchesOutput: [GlintLine] = []
        var misses: [GlintLine] = []
        var candidateBudget = 6
        let prioritized = tokens.sorted { tokenPriority($0) < tokenPriority($1) }
        for token in prioritized.prefix(8) {
            let specs = CandidatePlanner.candidates(for: token, context: context)
            if specs.isEmpty {
                misses.append(.miss(token.raw))
                continue
            }
            var matches: [GlintLine] = []
            for spec in specs where candidateBudget > 0 {
                candidateBudget -= 1
                if let line = await resolver.resolve(spec) { matches.append(line) }
                if matches.count + matchesOutput.count >= 3 { break }
            }
            if matches.isEmpty { misses.append(.miss(token.raw)) }
            else { matchesOutput.append(contentsOf: matches) }
            if let first = matches.first,
               case let .issueKey(project, _) = token.kind,
               let actualTracker = Tracker(rawValue: first.source) {
                context.saw(project: project, on: actualTracker)
            }
            if matchesOutput.count >= 3 || candidateBudget == 0 { break }
        }
        var seen = Set<String>()
        return (matchesOutput + misses).filter { seen.insert($0.id).inserted }.prefix(3).map { $0 }
    }

    private func tokenPriority(_ token: NearbyToken) -> Int {
        switch token.kind {
        case .issueKey: return 0
        case .hashNumber, .bareNumber: return 1
        case .version: return 2
        }
    }
}

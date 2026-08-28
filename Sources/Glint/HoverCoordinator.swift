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
    private var observedStickyModifier: StickyModifier
    private var stickyModifierWasDown = false
    private var stickyPressDetector = RapidPressDetector()
    private var pendingStickyPin = false
    private var suppressOptionTriggerUntilRelease = false

    init(appState: AppState) {
        self.appState = appState
        observedMode = appState.triggerMode
        observedStickyModifier = appState.stickyModifier
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
        observeStickyShortcut()
        if overlay.isSticky { return }
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
            if suppressOptionTriggerUntilRelease {
                if !NSEvent.modifierFlags.contains(.option) {
                    suppressOptionTriggerUntilRelease = false
                    optionWasHeld = false
                }
                return
            }
            guard NSEvent.modifierFlags.contains(.option) else {
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
                  hypot(NSEvent.mouseLocation.x - position.x, NSEvent.mouseLocation.y - position.y) <= 4 else {
                appState?.activity = "Ready"
                pendingStickyPin = false
                return
            }
            if lines.isEmpty {
                overlay.hide()
                pendingStickyPin = false
                appState?.activity = tokens.isEmpty ? "No nearby ticket token" : "No match"
            } else {
                overlay.show(lines, near: position, shortcutLabel: stickyShortcutLabel)
                if pendingStickyPin {
                    overlay.pin(shortcutLabel: stickyShortcutLabel)
                    pendingStickyPin = false
                    appState?.activity = "Pinned · \(lines.first?.title ?? "result")"
                } else {
                    appState?.activity = lines.first?.title ?? "Ready"
                }
            }
        }
        return true
    }

    private func resolve(tokens: [NearbyToken]) async -> [GlintLine] {
        guard !tokens.isEmpty else { return [] }
        var context = ResolutionContext.load()
        var attempts: [GlintLine?] = []
        var realMatchCount = 0
        var candidateBudget = 16
        let prioritized = tokens.sorted { tokenPriority($0) < tokenPriority($1) }
        for token in prioritized.prefix(12) {
            let specs = CandidatePlanner.candidates(for: token, context: context)
            if specs.isEmpty { continue }
            var matches: [GlintLine] = []
            for spec in specs where candidateBudget > 0 {
                candidateBudget -= 1
                let line = await resolver.resolve(spec)
                attempts.append(line)
                if let line {
                    matches.append(line)
                    realMatchCount += 1
                }
                if realMatchCount >= HoverResultPolicy.maximumResults { break }
            }
            if let first = matches.first,
               case let .issueKey(project, _) = token.kind,
               let actualTracker = Tracker(rawValue: first.source) {
                context.saw(project: project, on: actualTracker)
            }
            if realMatchCount >= HoverResultPolicy.maximumResults || candidateBudget == 0 { break }
        }
        return HoverResultPolicy.visible(from: attempts)
    }

    private func tokenPriority(_ token: NearbyToken) -> Int {
        switch token.kind {
        case .issueKey: return 0
        case .hashNumber, .bareNumber: return 1
        case .version: return 2
        }
    }

    private var stickyShortcutLabel: String {
        "\(appState?.stickyModifier.symbol ?? StickyModifier.option.symbol) twice"
    }

    private func observeStickyShortcut() {
        let modifier = appState?.stickyModifier ?? .option
        let flags = NSEvent.modifierFlags
        let isDown = flags.contains(eventFlag(for: modifier))
        if modifier != observedStickyModifier {
            observedStickyModifier = modifier
            stickyModifierWasDown = isDown
            stickyPressDetector.reset()
            pendingStickyPin = false
            return
        }
        defer { stickyModifierWasDown = isDown }
        guard isDown, !stickyModifierWasDown else { return }
        let now = Date()
        let interval = appState?.stickyDoublePressInterval ?? GlintPreferences.defaultStickyDoublePressInterval
        guard stickyPressDetector.registerPress(at: now, maximumInterval: interval) else { return }
        if modifier == .option { suppressOptionTriggerUntilRelease = true }
        if overlay.isSticky {
            overlay.closePinned()
            pendingStickyPin = false
            scanGeneration += 1
            lastPosition = NSEvent.mouseLocation
            stableSince = now
            dwellScannedPosition = nil
            appState?.activity = "Ready"
        } else if overlay.isVisible {
            overlay.pin(shortcutLabel: stickyShortcutLabel)
            appState?.activity = "Pinned"
        } else if isScanning {
            pendingStickyPin = true
            appState?.activity = "Pinning result…"
        }
    }

    private func eventFlag(for modifier: StickyModifier) -> NSEvent.ModifierFlags {
        switch modifier {
        case .option: return .option
        case .control: return .control
        case .command: return .command
        case .shift: return .shift
        }
    }
}

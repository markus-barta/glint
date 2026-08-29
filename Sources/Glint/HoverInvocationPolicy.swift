import Foundation

/// Pure decision seam for automatic hover activation. Manual Inspect remains
/// unconditional and is intentionally handled by `HoverCoordinator`.
enum HoverInvocationPolicy {
    static let holdRepeatInterval: TimeInterval = 0.65

    static func shouldTrigger(
        preferences: ActivationPreferences,
        stableDuration: TimeInterval,
        dwellAlreadyScanned: Bool,
        heldModifiers: HotKeyModifiers,
        elapsedSinceLastScan: TimeInterval
    ) -> Bool {
        switch preferences.mode {
        case .off:
            return false
        case .dwell:
            return stableDuration >= preferences.dwellSeconds && !dwellAlreadyScanned
        case .hold:
            let required = preferences.holdModifiers
            return heldModifiers.intersection(required) == required &&
                elapsedSinceLastScan >= holdRepeatInterval
        case .continuous:
            return elapsedSinceLastScan >= preferences.scanInterval
        }
    }
}

enum ScanFeedbackLifecycleEvent: CaseIterable {
    case invoked
    case recognized
    case resolved
    case noMatch
}

/// Keeps asynchronous OCR/lookup completions from repainting feedback owned by
/// a newer pointer position or command. Stale work must return silently: the
/// generation change itself owns cancellation, and may already have presented
/// the next scan's invocation.
enum ScanFeedbackLifecyclePolicy {
    static func permits(
        _ event: ScanFeedbackLifecycleEvent,
        startedGeneration: Int,
        currentGeneration: Int
    ) -> Bool {
        _ = event
        return startedGeneration == currentGeneration
    }
}

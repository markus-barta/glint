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

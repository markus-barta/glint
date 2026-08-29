import Foundation

/// Pure decision seam for automatic hover activation. Manual Inspect remains
/// unconditional and is intentionally handled by `HoverCoordinator`.
enum HoverInvocationPolicy {
    static let holdRepeatInterval: TimeInterval = 0.65
    static let continuousMovementSettleDuration: TimeInterval = 0.12

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
            return stableDuration >= continuousMovementSettleDuration &&
                elapsedSinceLastScan >= preferences.scanInterval
        }
    }
}

enum ManualInspectionPolicy {
    static let movementGraceRadius: CGFloat = 36
    static let lifetime: TimeInterval = 8

    static func shouldDismiss(distanceFromAnchor: CGFloat, elapsed: TimeInterval) -> Bool {
        distanceFromAnchor > movementGraceRadius || elapsed >= lifetime
    }
}

enum ScanAnchorPolicy {
    static let maximumAnchors = 3

    static func sourceOrders(tokens: [NearbyToken], plan: ResolutionPlan) -> [Int] {
        let eligible = Set(tokens.compactMap { token -> Int? in
            if case .version = token.kind { return nil }
            return token.sourceOrder
        })
        var seen = Set<Int>()
        return plan.proposals.compactMap { proposal in
            eligible.contains(proposal.sourceOrder) && seen.insert(proposal.sourceOrder).inserted
                ? proposal.sourceOrder : nil
        }.prefix(maximumAnchors).map { $0 }
    }
}

enum ScanTerminalFeedback: Equatable { case resolved, noMatch, none }

enum ResolutionLookupPolicy {
    static let maximumConcurrentLookups = 4

    static func initialCount(total: Int) -> Int {
        min(max(0, total), maximumConcurrentLookups)
    }

    static func shouldLaunchNext(
        launched: Int,
        total: Int,
        resolvedCount: Int,
        maximumResults: Int,
        isCancelled: Bool = false
    ) -> Bool {
        !isCancelled && launched < total && resolvedCount < maximumResults
    }

    static func shouldResolveFallback(primaryResolvedCount: Int, isCancelled: Bool = false) -> Bool {
        !isCancelled && primaryResolvedCount == 0
    }
}

enum ProcessExecutionPolicy {
    static let timeout: TimeInterval = 3
    static let pollNanoseconds: UInt64 = 25_000_000
    static let terminationGraceNanoseconds: UInt64 = 125_000_000
    static let killGraceNanoseconds: UInt64 = 125_000_000

    static func shouldStop(isCancelled: Bool, elapsed: TimeInterval) -> Bool {
        isCancelled || elapsed >= timeout
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

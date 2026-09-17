import Foundation

/// Durable identity candidates are intentionally conservative. A UUID is
/// preferred; a runtime ID is only a same-session fallback and is never
/// sufficient to authorize destructive mutation.
nonisolated struct NativeSpaceIdentity: Codable, Equatable, Sendable, Hashable {
    let uuid: String?
    let displayIdentifier: String
    let runtimeID: UInt64?

    init(_ space: NativeSpaceDescriptor) {
        uuid = space.uuid
        displayIdentifier = space.displayIdentifier
        runtimeID = space.runtimeID
    }

    func matches(_ space: NativeSpaceDescriptor) -> Bool {
        guard displayIdentifier == space.displayIdentifier else { return false }
        if let uuid, let observed = space.uuid { return uuid == observed }
        return uuid == nil && runtimeID == space.runtimeID
    }
}

nonisolated struct NativeSpaceMapping: Codable, Equatable, Sendable {
    let virtualSpaceID: String
    let displayIdentifier: String
    let nativeIdentity: NativeSpaceIdentity
    let managedByBlazaresSpaces: Bool
}

nonisolated enum NativeTopologyReconciliationAction: Equatable, Sendable {
    case retain(NativeSpaceIdentity)
    case create(displayIdentifier: String)
    case review(displayIdentifier: String, reason: String)
}

nonisolated struct NativeTopologyReconciliationPlan: Equatable, Sendable {
    let actions: [NativeTopologyReconciliationAction]
    var requiresReview: Bool { actions.contains { if case .review = $0 { return true }; return false } }
}

/// Result of a reconciliation run. A partial result is deliberately useful:
/// successful display bindings are retained and a later run only addresses
/// the missing displays.
nonisolated enum NativeSpaceBindingStatus: Equatable, Sendable {
    case complete
    case partial(missingDisplays: [String])
    case missing
    case stale(reason: String)
    case degraded(reason: String)
}

nonisolated struct NativeSpaceReconciliationResult: Equatable, Sendable {
    let status: NativeSpaceBindingStatus
    let mappings: [NativeSpaceMapping]
    let topology: NativeSpaceTopology?
    let failures: [String]

    var isUsable: Bool {
        switch status {
        case .complete, .partial: return !mappings.isEmpty
        case .missing, .stale, .degraded: return false
        }
    }
}

/// The private Mission Control/AX implementation is intentionally kept out of
/// the reconciler. It only needs to create one ordinary Space and return a
/// descriptor; the executor performs all freshness and post-mutation checks.
nonisolated protocol NativeSpaceCreationProviding: NativeSpacesProviding {
    nonisolated func createNativeSpace(displayIdentifier: String) -> Result<NativeSpaceDescriptor, NativeSpaceOperationError>
}

/// Executes a previously computed plan without making planner decisions.
/// Every mutation is guarded by a fresh topology comparison and followed by a
/// topology read. This prevents a stale Mission Control snapshot from causing
/// duplicate Spaces or binding a Space on the wrong display.
nonisolated struct NativeSpaceReconciliationExecutor: Sendable {
    nonisolated init() {}

    nonisolated func execute(
        plan: NativeTopologyReconciliationPlan,
        virtualSpaceIDs: [String],
        displays: [String],
        expectedTopology: NativeSpaceTopology,
        provider: any NativeSpaceCreationProviding
    ) -> NativeSpaceReconciliationResult {
        var current = expectedTopology
        var mappings: [NativeSpaceMapping] = []
        var failures: [String] = []

        // Retains are resolved against the snapshot, never adopted as owned.
        // The planner has no virtual ID in its action payload, so resolve the
        // deterministic action order (virtual space, then display).
        var actionIndex = 0
        for virtualID in virtualSpaceIDs {
            for display in displays {
                guard actionIndex < plan.actions.count else { break }
                let action = plan.actions[actionIndex]
                actionIndex += 1
                switch action {
                case let .retain(identity):
                    guard let space = current.spaces.first(where: { identity.matches($0) }) else {
                        failures.append("\(virtualID)/\(display): retained native Space became stale")
                        continue
                    }
                    mappings.append(NativeSpaceMapping(virtualSpaceID: virtualID, displayIdentifier: display,
                                                       nativeIdentity: NativeSpaceIdentity(space), managedByBlazaresSpaces: false))
                case let .review(_, reason):
                    failures.append("\(virtualID)/\(display): \(reason)")
                case let .create(targetDisplay):
                    guard targetDisplay == display else {
                        failures.append("\(virtualID)/\(display): planner/display mismatch")
                        continue
                    }
                    guard provider.readTopology().value?.normalized == current.normalized else {
                        return NativeSpaceReconciliationResult(status: .stale(reason: "Native topology changed before creation"), mappings: mappings, topology: current, failures: failures)
                    }
                    let beforeIDs = Set(current.spaces.map(\.runtimeID))
                    switch provider.createNativeSpace(displayIdentifier: display) {
                    case let .failure(error):
                        failures.append("\(virtualID)/\(display): \(error)")
                        // A private AX operation can fail after the click was
                        // posted. Always refresh so a late-created Space is
                        // observed on the next reconciliation instead of
                        // being duplicated.
                        if let refreshed = provider.readTopology().value {
                            current = refreshed
                        }
                    case let .success(created):
                        guard let refreshed = provider.readTopology().value else {
                            failures.append("\(virtualID)/\(display): topology refresh failed after creation")
                            continue
                        }
                        current = refreshed
                        guard created.displayIdentifier == display,
                              created.kind == .userDesktop,
                              !beforeIDs.contains(created.runtimeID),
                              let observed = current.spaces.first(where: { $0.runtimeID == created.runtimeID }) else {
                            failures.append("\(virtualID)/\(display): created Space could not be verified")
                            continue
                        }
                        // App ownership is only persisted for a Space returned
                        // by our creation operation and then observed again.
                        mappings.append(NativeSpaceMapping(virtualSpaceID: virtualID, displayIdentifier: display,
                                                           nativeIdentity: NativeSpaceIdentity(observed), managedByBlazaresSpaces: true))
                    }
                }
            }
        }

        let missing = displays.filter { display in
            !mappings.contains { $0.displayIdentifier == display }
        }
        let status: NativeSpaceBindingStatus
        if !failures.isEmpty && !mappings.isEmpty {
            status = .partial(missingDisplays: missing)
        } else if !failures.isEmpty {
            status = .degraded(reason: failures.joined(separator: "; "))
        } else {
            status = missing.isEmpty ? .complete : .partial(missingDisplays: missing)
        }
        return NativeSpaceReconciliationResult(status: status, mappings: mappings, topology: current, failures: failures)
    }
}

private extension Result where Failure == NativeSpacesReadError {
    nonisolated var value: Success? {
        guard case let .success(value) = self else { return nil }
        return value
    }
}

/// Pure planner. It never destroys a Space and never treats an arbitrary
/// existing Space as owned merely because it occupies a matching position.
nonisolated struct NativeTopologyReconciler: Sendable {
    nonisolated init() {}

    nonisolated func plan(
        virtualSpaceIDs: [String],
        displays: [String],
        topology: NativeSpaceTopology,
        mappings: [NativeSpaceMapping]
    ) -> NativeTopologyReconciliationPlan {
        let bindings = NativeSpaceTopologyMapper().bindings(for: topology)
        var actions: [NativeTopologyReconciliationAction] = []
        for (position, virtualID) in virtualSpaceIDs.enumerated() {
            let binding = bindings.first { $0.virtualSpacePosition == position + 1 }
            for display in displays {
                if let mapped = mappings.first(where: { $0.virtualSpaceID == virtualID && $0.displayIdentifier == display }),
                   let observed = topology.spaces.first(where: { mapped.nativeIdentity.matches($0) }) {
                    actions.append(.retain(NativeSpaceIdentity(observed)))
                } else if binding?.spacesByDisplay[display] != nil {
                    // Existing user Spaces can be used for a mapping, but are
                    // never silently marked as app-owned.
                    actions.append(.review(displayIdentifier: display, reason: "Existing Space requires explicit mapping confirmation"))
                } else {
                    actions.append(.create(displayIdentifier: display))
                }
            }
        }
        return NativeTopologyReconciliationPlan(actions: actions)
    }
}

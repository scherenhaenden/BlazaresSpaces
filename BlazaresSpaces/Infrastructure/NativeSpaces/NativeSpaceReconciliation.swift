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

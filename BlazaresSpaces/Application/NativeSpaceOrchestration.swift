import Foundation

/// Application adapter which keeps the creation executor independent from the
/// controller and from private SkyLight symbols.
private struct NativeSpaceControllerCreationAdapter: NativeSpaceCreationProviding, Sendable {
    let provider: any NativeSpacesProviding
    let controller: any NativeSpacesControlling

    nonisolated func readTopology() -> Result<NativeSpaceTopology, NativeSpacesReadError> {
        provider.readTopology()
    }

    nonisolated func createNativeSpace(displayIdentifier: String) -> Result<NativeSpaceDescriptor, NativeSpaceOperationError> {
        controller.createSpace(on: displayIdentifier)
    }
}

extension WorkspaceApplicationService {
    /// Reconciles the configured global Virtual Spaces against freshly read
    /// native topology. Each create is planned and verified independently; a
    /// partial result is retained and surfaced rather than reported complete.
    func ensureRequiredNativeSpaces() {
        guard !isNativeReconciliationInProgress else {
            actionStatus = "Native Space reconciliation is already in progress."
            return
        }
        guard let topology = nativeSpaceTopology ?? readNativeTopology() else {
            actionStatus = "Native topology is unavailable; reconciliation was not started."
            return
        }
        let displays = topology.displays.map(\.displayIdentifier)
        let virtualIDs = workspaceManager.workspaceOrder.map(\.rawValue)
        guard !virtualIDs.isEmpty, !displays.isEmpty else {
            actionStatus = "No Virtual Spaces or connected Screens are available for reconciliation."
            return
        }
        let plan = NativeTopologyReconciler().plan(
            virtualSpaceIDs: virtualIDs,
            displays: displays,
            topology: topology,
            mappings: nativeSpaceMappings
        )
        if plan.requiresReview {
            // Review actions are retained as explicit failures by the
            // executor, but must not prevent independent missing Spaces from
            // being created. A topology with one unowned existing Space and a
            // missing later Space is a normal migration case: create what we
            // can and leave the ambiguous binding for user confirmation.
            nativeSpaceReadStatus = "Native topology contains mappings requiring review; safe missing Spaces will still be reconciled."
        }
        isNativeReconciliationInProgress = true
        actionStatus = "Reconciling required Native Spaces…"
        let executor = NativeSpaceReconciliationExecutor()
        let adapter = NativeSpaceControllerCreationAdapter(provider: nativeSpacesProvider, controller: nativeSpacesController)
        let prior = nativeSpaceMappings
        Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                executor.execute(plan: plan, virtualSpaceIDs: virtualIDs, displays: displays,
                                 expectedTopology: topology, provider: adapter, existingMappings: prior)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.isNativeReconciliationInProgress = false
            if let refreshed = result.topology { self.nativeSpaceTopology = refreshed }
            let updated = Self.mergeNativeMappings(prior, with: result.mappings)
            self.nativeSpaceMappings = updated
            switch await self.nativeSpaceMappingStore.save(updated) {
            case .loaded:
                break
            case let .invalid(message), let .ioFailure(message):
                self.appendNativeSpaceLog("RECONCILE persistence failed · \(message)")
            case .missing:
                break
            }
            self.appendNativeSpaceLog("RECONCILE \(String(describing: result.status)) · failures=\(result.failures.count)")
            self.nativeSpaceReadStatus = "Native reconciliation: \(String(describing: result.status))"
            self.actionStatus = result.failures.isEmpty
                ? "Required Native Spaces reconciled."
                : "Native Space reconciliation is partial/degraded; review diagnostics."
        }
    }

    private func readNativeTopology() -> NativeSpaceTopology? {
        guard case let .success(topology) = nativeSpacesProvider.readTopology() else { return nil }
        return topology.normalized
    }

    private static func mergeNativeMappings(_ old: [NativeSpaceMapping], with new: [NativeSpaceMapping]) -> [NativeSpaceMapping] {
        var merged = old.filter { prior in
            !new.contains { $0.virtualSpaceID == prior.virtualSpaceID && $0.displayIdentifier == prior.displayIdentifier }
        }
        merged.append(contentsOf: new)
        return merged
    }
}

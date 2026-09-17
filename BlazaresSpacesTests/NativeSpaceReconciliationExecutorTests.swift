import Foundation
import Testing

@Suite
struct NativeSpaceReconciliationExecutorTests {
    @Test
    func createRefreshesAndReplansRemainingBindings() {
        let initial = topology(spaces: [space(id: 1, position: 0)])
        let created = space(id: 2, position: 1)
        let mapping = NativeSpaceMapping(
            virtualSpaceID: "v1",
            displayIdentifier: "A",
            nativeIdentity: NativeSpaceIdentity(initial.spaces[0]),
            managedByBlazaresSpaces: false
        )
        let plan = NativeTopologyReconciler().plan(
            virtualSpaceIDs: ["v1", "v2"],
            displays: ["A"],
            topology: initial,
            mappings: [mapping]
        )
        let provider = ReconciliationProvider(initial: initial, created: created)

        let result = NativeSpaceReconciliationExecutor().execute(
            plan: plan,
            virtualSpaceIDs: ["v1", "v2"],
            displays: ["A"],
            expectedTopology: initial,
            provider: provider,
            existingMappings: [mapping]
        )

        #expect(provider.createCount == 1)
        #expect(result.failures.isEmpty)
        #expect(result.status == .complete)
        #expect(result.mappings.contains { $0.virtualSpaceID == "v2" && $0.managedByBlazaresSpaces })
        #expect(result.topology?.spaces.contains { $0.runtimeID == 2 } == true)
    }

    private func space(id: UInt64, position: Int) -> NativeSpaceDescriptor {
        NativeSpaceDescriptor(runtimeID: id, uuid: "uuid-\(id)", displayIdentifier: "A", position: position, kind: .userDesktop, isCurrent: position == 0)
    }

    private func topology(spaces: [NativeSpaceDescriptor]) -> NativeSpaceTopology {
        NativeSpaceTopology(displays: [.init(displayIdentifier: "A", currentSpaceRuntimeID: 1)], spaces: spaces, separateSpaces: true)
    }
}

private final class ReconciliationProvider: NativeSpaceCreationProviding, @unchecked Sendable {
    private let initial: NativeSpaceTopology
    private let created: NativeSpaceDescriptor
    private var current: NativeSpaceTopology
    private(set) var createCount = 0

    init(initial: NativeSpaceTopology, created: NativeSpaceDescriptor) {
        self.initial = initial
        self.created = created
        self.current = initial
    }

    nonisolated func readTopology() -> Result<NativeSpaceTopology, NativeSpacesReadError> {
        currentResult()
    }

    nonisolated func createNativeSpace(displayIdentifier: String) -> Result<NativeSpaceDescriptor, NativeSpaceOperationError> {
        createResult(displayIdentifier: displayIdentifier)
    }

    private func currentResult() -> Result<NativeSpaceTopology, NativeSpacesReadError> {
        .success(current)
    }

    private func createResult(displayIdentifier: String) -> Result<NativeSpaceDescriptor, NativeSpaceOperationError> {
        guard displayIdentifier == created.displayIdentifier else { return .failure(.failed("wrong display")) }
        createCount += 1
        current = NativeSpaceTopology(displays: initial.displays, spaces: initial.spaces + [created], separateSpaces: initial.separateSpaces)
        return .success(created)
    }
}

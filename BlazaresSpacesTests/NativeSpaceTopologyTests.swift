import Foundation
import Testing
@testable import BlazaresSpaces

@Suite struct NativeSpaceTopologyTests {
    @Test func validatorRejectsDuplicateRuntimeIDs() {
        let topology = NativeSpaceTopology(
            displays: [.init(displayIdentifier: "A", currentSpaceRuntimeID: 1)],
            spaces: [
                .init(runtimeID: 1, uuid: nil, displayIdentifier: "A", position: 0, kind: .userDesktop, isCurrent: true),
                .init(runtimeID: 1, uuid: nil, displayIdentifier: "A", position: 1, kind: .userDesktop, isCurrent: false)
            ], separateSpaces: true
        )
        #expect(throws: NativeSpacesReadError.self) { try NativeSpaceTopologyValidator().validate(topology).get() }
    }

    @Test func mapperBuildsGlobalBindingsAcrossDisplays() {
        let topology = NativeSpaceTopology(
            displays: [.init(displayIdentifier: "A", currentSpaceRuntimeID: 1), .init(displayIdentifier: "B", currentSpaceRuntimeID: 3)],
            spaces: [
                .init(runtimeID: 1, uuid: "a1", displayIdentifier: "A", position: 0, kind: .userDesktop, isCurrent: true),
                .init(runtimeID: 2, uuid: "a2", displayIdentifier: "A", position: 1, kind: .userDesktop, isCurrent: false),
                .init(runtimeID: 3, uuid: "b1", displayIdentifier: "B", position: 0, kind: .userDesktop, isCurrent: true),
                .init(runtimeID: 4, uuid: "b2", displayIdentifier: "B", position: 1, kind: .userDesktop, isCurrent: false)
            ], separateSpaces: true
        )
        let bindings = NativeSpaceTopologyMapper().bindings(for: topology)
        #expect(bindings.count == 2)
        #expect(bindings[0].spacesByDisplay.count == 2)
        #expect(bindings[1].spacesByDisplay.count == 2)
    }

    @Test func separateSpacesKeepsPartialBindingForDisplayWithExtraDesktop() {
        let topology = NativeSpaceTopology(
            displays: [.init(displayIdentifier: "A", currentSpaceRuntimeID: 1), .init(displayIdentifier: "B", currentSpaceRuntimeID: 2)],
            spaces: [
                .init(runtimeID: 1, uuid: nil, displayIdentifier: "A", position: 0, kind: .userDesktop, isCurrent: true),
                .init(runtimeID: 11, uuid: nil, displayIdentifier: "A", position: 1, kind: .userDesktop, isCurrent: false),
                .init(runtimeID: 12, uuid: nil, displayIdentifier: "A", position: 2, kind: .userDesktop, isCurrent: false),
                .init(runtimeID: 2, uuid: nil, displayIdentifier: "B", position: 0, kind: .userDesktop, isCurrent: true)
            ], separateSpaces: true
        )
        let bindings = NativeSpaceTopologyMapper().bindings(for: topology)
        #expect(bindings.count == 3)
        #expect(bindings[2].spacesByDisplay == ["A": topology.spaces[2]])
    }

    @Test func reconcilerNeverSchedulesDestructionAndReviewsUnownedExistingSpace() {
        let topology = NativeSpaceTopology(
            displays: [.init(displayIdentifier: "A", currentSpaceRuntimeID: 1)],
            spaces: [.init(runtimeID: 1, uuid: "existing", displayIdentifier: "A", position: 0, kind: .userDesktop, isCurrent: true)],
            separateSpaces: true
        )
        let plan = NativeTopologyReconciler().plan(virtualSpaceIDs: ["work"], displays: ["A"], topology: topology, mappings: [])
        #expect(plan.requiresReview)
        #expect(plan.actions.count == 1)
        guard case .review = plan.actions[0] else { Issue.record("Expected explicit review for an unowned existing Space"); return }
    }

    @Test func reconcilerSchedulesMissingSpaceCreation() {
        let topology = NativeSpaceTopology(displays: [.init(displayIdentifier: "A", currentSpaceRuntimeID: 1)], spaces: [.init(runtimeID: 1, uuid: "a1", displayIdentifier: "A", position: 0, kind: .userDesktop, isCurrent: true)], separateSpaces: true)
        let plan = NativeTopologyReconciler().plan(virtualSpaceIDs: ["work", "dev"], displays: ["A"], topology: topology, mappings: [])
        #expect(plan.actions.count == 2)
        guard case .review = plan.actions[0] else { Issue.record("Expected review for existing Space"); return }
        guard case let .create(display) = plan.actions[1] else { Issue.record("Expected creation for missing Space"); return }
        #expect(display == "A")
    }
}

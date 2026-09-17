import Foundation
import Testing
@testable import BlazaresSpaces

@Suite struct NativeSpaceTopologyTests {
    @Test func specialSpaceRolesAreExplicitAndNeverOrdinary() {
        #expect(NativeSpaceKind.fromMetadata(type: 4, metadata: ["isFullscreen": true]) == .fullScreen)
        #expect(NativeSpaceKind.fromMetadata(type: 4, metadata: ["isTiled": true]) == .tiled)
        #expect(NativeSpaceKind.fromMetadata(type: 9, metadata: ["transient": true]) == .transient(rawValue: 9))
        #expect(NativeSpaceKind.fromMetadata(type: 4, metadata: [:]) == .unknown(rawValue: 4))
        #expect(NativeSpaceKind.fullScreen != .userDesktop)
        #expect(NativeSpaceKind.tiled != .userDesktop)
        #expect(NativeSpaceKind.transient(rawValue: 9) != .userDesktop)
    }

    @Test func mapperExcludesFullscreenTiledTransientAndUnknownSpaces() {
        let topology = NativeSpaceTopology(
            displays: [.init(displayIdentifier: "A", currentSpaceRuntimeID: 1)],
            spaces: [
                .init(runtimeID: 1, uuid: "ordinary", displayIdentifier: "A", position: 0, kind: .userDesktop, isCurrent: true),
                .init(runtimeID: 2, uuid: "fullscreen", displayIdentifier: "A", position: 1, kind: .fullScreen, isCurrent: false),
                .init(runtimeID: 3, uuid: "tiled", displayIdentifier: "A", position: 2, kind: .tiled, isCurrent: false),
                .init(runtimeID: 4, uuid: "transient", displayIdentifier: "A", position: 3, kind: .transient(rawValue: 9), isCurrent: false),
                .init(runtimeID: 5, uuid: "unknown", displayIdentifier: "A", position: 4, kind: .unknown(rawValue: 77), isCurrent: false)
            ], separateSpaces: true
        )
        let bindings = NativeSpaceTopologyMapper().bindings(for: topology)
        #expect(bindings.count == 1)
        #expect(bindings[0].spacesByDisplay["A"]?.runtimeID == 1)
    }

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

    @Test func mapperIgnoresFullscreenTiledAndUnknownSpaces() {
        let topology = NativeSpaceTopology(
            displays: [.init(displayIdentifier: "A", currentSpaceRuntimeID: 10)],
            spaces: [
                .init(runtimeID: 10, uuid: "desktop", displayIdentifier: "A", position: 0, kind: .userDesktop, isCurrent: true),
                .init(runtimeID: 11, uuid: "fullscreen", displayIdentifier: "A", position: 1, kind: .fullScreen, isCurrent: false),
                .init(runtimeID: 12, uuid: "tiled", displayIdentifier: "A", position: 2, kind: .tiled, isCurrent: false),
                .init(runtimeID: 13, uuid: "unknown", displayIdentifier: "A", position: 3, kind: .unknown(rawValue: 99), isCurrent: false),
                .init(runtimeID: 14, uuid: "desktop-2", displayIdentifier: "A", position: 4, kind: .userDesktop, isCurrent: false)
            ], separateSpaces: true
        )
        let bindings = NativeSpaceTopologyMapper().bindings(for: topology)
        #expect(bindings.count == 2)
        #expect(bindings.allSatisfy { $0.spacesByDisplay.values.allSatisfy(\.isOrdinaryUserDesktop) })
        #expect(bindings[0].spacesByDisplay["A"]?.runtimeID == 10)
        #expect(bindings[1].spacesByDisplay["A"]?.runtimeID == 14)
    }

    @Test func destructionSafetyRejectsSpecialSpacesBeforeMutation() {
        let ordinary = NativeSpaceDescriptor(runtimeID: 10, uuid: "ordinary", displayIdentifier: "A", position: 0, kind: .userDesktop, isCurrent: true)
        let secondOrdinary = NativeSpaceDescriptor(runtimeID: 11, uuid: "ordinary-2", displayIdentifier: "A", position: 1, kind: .userDesktop, isCurrent: false)
        let specialKinds: [NativeSpaceKind] = [.fullScreen, .tiled, .unknown(rawValue: 99)]

        for (index, kind) in specialKinds.enumerated() {
            let special = NativeSpaceDescriptor(runtimeID: UInt64(20 + index), uuid: "special-\(index)", displayIdentifier: "A", position: 2, kind: kind, isCurrent: false)
            let topology = NativeSpaceTopology(
                displays: [.init(displayIdentifier: "A", currentSpaceRuntimeID: ordinary.runtimeID)],
                spaces: [ordinary, secondOrdinary, special],
                separateSpaces: true
            )
            let result = NativeSpaceDestructionSafety().validate(space: special, in: topology, confirmedOwned: true)
            guard case .failure(.unsafe) = result else {
                Issue.record("Special Native Space kind was accepted as a destruction target: \(kind)")
                continue
            }
        }
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

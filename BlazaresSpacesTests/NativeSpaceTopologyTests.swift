import Testing
@testable import BlazaresSpaces

struct NativeSpaceTopologyTests {
    @Test func mapsEqualOrdinaryDesktopPositionsAcrossDisplays() {
        let topology = NativeSpaceTopology(
            displays: [
                .init(displayIdentifier: "A", currentSpaceRuntimeID: 11),
                .init(displayIdentifier: "B", currentSpaceRuntimeID: 21)
            ],
            spaces: [
                .init(runtimeID: 11, uuid: "a1", displayIdentifier: "A", position: 0, kind: .userDesktop, isCurrent: true),
                .init(runtimeID: 12, uuid: "a2", displayIdentifier: "A", position: 1, kind: .userDesktop, isCurrent: false),
                .init(runtimeID: 21, uuid: "b1", displayIdentifier: "B", position: 0, kind: .userDesktop, isCurrent: true),
                .init(runtimeID: 22, uuid: "b2", displayIdentifier: "B", position: 1, kind: .userDesktop, isCurrent: false)
            ],
            separateSpaces: true
        )

        let bindings = NativeSpaceTopologyMapper().bindings(for: topology)
        #expect(bindings.map(\.virtualSpacePosition) == [1, 2])
        #expect(bindings[1].spacesByDisplay["A"]?.runtimeID == 12)
        #expect(bindings[1].spacesByDisplay["B"]?.runtimeID == 22)
    }

    @Test func excludesFullscreenTiledAndUnknownEntries() {
        let topology = NativeSpaceTopology(
            displays: [.init(displayIdentifier: "A", currentSpaceRuntimeID: 1)],
            spaces: [
                .init(runtimeID: 1, uuid: nil, displayIdentifier: "A", position: 0, kind: .userDesktop, isCurrent: true),
                .init(runtimeID: 2, uuid: nil, displayIdentifier: "A", position: 1, kind: .fullScreen, isCurrent: false),
                .init(runtimeID: 3, uuid: nil, displayIdentifier: "A", position: 2, kind: .tiled, isCurrent: false),
                .init(runtimeID: 4, uuid: nil, displayIdentifier: "A", position: 3, kind: .unknown(rawValue: 99), isCurrent: false),
                .init(runtimeID: 5, uuid: nil, displayIdentifier: "A", position: 4, kind: .userDesktop, isCurrent: false)
            ],
            separateSpaces: true
        )

        let bindings = NativeSpaceTopologyMapper().bindings(for: topology)
        #expect(bindings.count == 2)
        #expect(bindings.map { $0.spacesByDisplay["A"]?.runtimeID } == [1, 5])
    }

    @Test func unequalDisplayCountsDoNotCreatePartialBindings() {
        let topology = NativeSpaceTopology(
            displays: [
                .init(displayIdentifier: "A", currentSpaceRuntimeID: 1),
                .init(displayIdentifier: "B", currentSpaceRuntimeID: 2)
            ],
            spaces: [
                .init(runtimeID: 1, uuid: nil, displayIdentifier: "A", position: 0, kind: .userDesktop, isCurrent: true),
                .init(runtimeID: 11, uuid: nil, displayIdentifier: "A", position: 1, kind: .userDesktop, isCurrent: false),
                .init(runtimeID: 2, uuid: nil, displayIdentifier: "B", position: 0, kind: .userDesktop, isCurrent: true)
            ],
            separateSpaces: false
        )

        let bindings = NativeSpaceTopologyMapper().bindings(for: topology)
        #expect(bindings.count == 1)
        #expect(bindings[0].spacesByDisplay.count == 2)
    }
}

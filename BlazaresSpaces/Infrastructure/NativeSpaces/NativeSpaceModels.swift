import Foundation

/// Runtime-only description of a native Mission Control space. Native IDs are
/// intentionally not persisted and are never used as Virtual Space identity.
nonisolated enum NativeSpaceKind: Equatable, Sendable {
    case userDesktop
    case fullScreen
    case tiled
    case unknown(rawValue: Int)
}

nonisolated struct NativeSpaceDescriptor: Equatable, Sendable {
    let runtimeID: UInt64
    let uuid: String?
    let displayIdentifier: String
    let position: Int
    let kind: NativeSpaceKind
    let isCurrent: Bool
}

nonisolated struct NativeDisplayDescriptor: Equatable, Sendable {
    let displayIdentifier: String
    let currentSpaceRuntimeID: UInt64?
}

nonisolated struct NativeSpaceTopology: Equatable, Sendable {
    let displays: [NativeDisplayDescriptor]
    let spaces: [NativeSpaceDescriptor]
    let separateSpaces: Bool
}

nonisolated struct NativeVirtualSpaceBinding: Equatable, Sendable {
    let virtualSpacePosition: Int
    let spacesByDisplay: [String: NativeSpaceDescriptor]
}

/// Positional binding deliberately ignores full-screen/tiled/unknown entries.
/// Unknown native types are not guessed into ordinary desktop positions.
nonisolated struct NativeSpaceTopologyMapper: Sendable {
    nonisolated init() {}

    nonisolated func bindings(for topology: NativeSpaceTopology) -> [NativeVirtualSpaceBinding] {
        let displayIDs = topology.displays.map(\.displayIdentifier)
        let ordinaryByDisplay = Dictionary(grouping: topology.spaces.filter { $0.kind == .userDesktop }, by: \.displayIdentifier)
            .mapValues { spaces in spaces.sorted { $0.position < $1.position } }
        let count = ordinaryByDisplay.values.map(\.count).min() ?? 0

        return (0..<count).map { index in
            NativeVirtualSpaceBinding(
                virtualSpacePosition: index + 1,
                spacesByDisplay: Dictionary(uniqueKeysWithValues: displayIDs.compactMap { displayID in
                    guard let space = ordinaryByDisplay[displayID]?[safe: index] else { return nil }
                    return (displayID, space)
                })
            )
        }.filter { $0.spacesByDisplay.count == displayIDs.count }
    }
}

protocol NativeSpacesProviding: Sendable {
    nonisolated func readTopology() -> Result<NativeSpaceTopology, NativeSpacesReadError>
}

nonisolated enum NativeSpacesReadError: Error, Equatable, Sendable {
    case unavailable(String)
    case malformedData(String)
}

/// Production-safe placeholder until the private SkyLight bridge has verified
/// symbols and signatures for the running macOS release. It performs no calls
/// and cannot mutate native Spaces.
nonisolated struct UnavailableNativeSpacesProvider: NativeSpacesProviding {
    let reason: String

    nonisolated init(reason: String = "Native SkyLight read bridge is experimental and unavailable") {
        self.reason = reason
    }

    nonisolated func readTopology() -> Result<NativeSpaceTopology, NativeSpacesReadError> {
        .failure(.unavailable(reason))
    }
}

private extension Array {
    nonisolated subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

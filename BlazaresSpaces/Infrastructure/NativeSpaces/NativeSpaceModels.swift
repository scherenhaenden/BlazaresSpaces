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

    /// Returns a deterministic snapshot suitable for comparison and planning.
    /// Runtime IDs are retained, but never become durable Virtual Space IDs.
    var normalized: NativeSpaceTopology {
        let orderedDisplays = displays.sorted { $0.displayIdentifier < $1.displayIdentifier }
        let displayOrder = Dictionary(uniqueKeysWithValues: orderedDisplays.enumerated().map { ($1.displayIdentifier, $0) })
        let orderedSpaces = spaces.sorted {
            let lhsDisplay = displayOrder[$0.displayIdentifier] ?? .max
            let rhsDisplay = displayOrder[$1.displayIdentifier] ?? .max
            if lhsDisplay != rhsDisplay { return lhsDisplay < rhsDisplay }
            if $0.position != $1.position { return $0.position < $1.position }
            return $0.runtimeID < $1.runtimeID
        }
        return NativeSpaceTopology(displays: orderedDisplays, spaces: orderedSpaces, separateSpaces: separateSpaces)
    }
}

nonisolated struct NativeSpaceTopologyValidator: Sendable {
    nonisolated init() {}

    nonisolated func validate(_ topology: NativeSpaceTopology) -> Result<Void, NativeSpacesReadError> {
        let displayIDs = topology.displays.map(\.displayIdentifier)
        guard displayIDs.allSatisfy({ !$0.isEmpty }), Set(displayIDs).count == displayIDs.count else {
            return .failure(.malformedData("Duplicate or empty native display identifier"))
        }
        let knownDisplays = Set(displayIDs)
        let runtimeIDs = topology.spaces.map(\.runtimeID)
        guard Set(runtimeIDs).count == runtimeIDs.count else {
            return .failure(.malformedData("Duplicate native Space runtime ID"))
        }
        guard topology.spaces.allSatisfy({ knownDisplays.contains($0.displayIdentifier) }) else {
            return .failure(.malformedData("Native Space references an unknown display"))
        }
        let uuids = topology.spaces.compactMap { space -> String? in
            guard let uuid = space.uuid, !uuid.isEmpty else { return nil }
            return space.displayIdentifier + "\u{1f}" + uuid
        }
        guard Set(uuids).count == uuids.count else {
            return .failure(.malformedData("Duplicate native Space UUID on a display"))
        }
        return .success(())
    }
}

nonisolated struct NativeSpaceCapabilities: Equatable, Sendable {
    let discovery: Bool
    let create: Bool
    let destroy: Bool
    let focus: Bool
    let moveWindow: Bool
    let reasons: [String]

    static let unavailable = NativeSpaceCapabilities(
        discovery: false, create: false, destroy: false, focus: false,
        moveWindow: false, reasons: ["SkyLight bridge unavailable"]
    )
}

nonisolated enum NativeSpaceOperationError: Error, Equatable, Sendable {
    case unavailable(String)
    case staleIdentity(String)
    case unsafe(String)
    case failed(String)
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
        // With separate Spaces enabled, displays may legitimately have
        // different counts. Keep partial positional bindings so the active
        // display can still be switched; callers decide whether completeness
        // is required for a coordinated multi-display operation.
        let counts = ordinaryByDisplay.values.map(\.count)
        let maximumCount = topology.separateSpaces ? (counts.max() ?? 0) : (counts.min() ?? 0)
        return (0..<maximumCount).map { index in
            NativeVirtualSpaceBinding(
                virtualSpacePosition: index + 1,
                spacesByDisplay: Dictionary(uniqueKeysWithValues: displayIDs.compactMap { displayID in
                    guard let space = ordinaryByDisplay[displayID]?[safe: index] else { return nil }
                    return (displayID, space)
                })
            )
        }
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

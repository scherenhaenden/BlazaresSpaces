import AppKit
import CoreGraphics
import Foundation

/// Minimal, read-only runtime bridge. All private ABI details are confined to
/// this file; absence or mismatch is reported instead of guessed.
struct SkyLightNativeSpacesProvider: NativeSpacesProviding {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopyManagedSpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

    nonisolated init() {}

    nonisolated func readTopology() -> Result<NativeSpaceTopology, NativeSpacesReadError> {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else {
            return .failure(.unavailable("SkyLight framework is unavailable"))
        }
        defer { dlclose(handle) }
        guard let connectionSymbol = dlsym(handle, "SLSMainConnectionID"),
              let spacesSymbol = dlsym(handle, "SLSCopyManagedDisplaySpaces") else {
            return .failure(.unavailable("Required SkyLight symbols are unavailable"))
        }

        let connection = unsafeBitCast(connectionSymbol, to: MainConnection.self)()
        let copySpaces = unsafeBitCast(spacesSymbol, to: CopyManagedSpaces.self)
        guard let managed = copySpaces(connection)?.takeRetainedValue() else {
            return .failure(.malformedData("SLSCopyManagedDisplaySpaces returned no data"))
        }
        let parsed = parse(managed)
        guard case let .success(topology) = parsed else { return parsed }
        return NativeSpaceTopologyValidator().validate(topology).map { topology.normalized }
    }

    private func parse(_ managed: CFArray) -> Result<NativeSpaceTopology, NativeSpacesReadError> {
        let displays = managed as NSArray
        var descriptors: [NativeSpaceDescriptor] = []
        var displayDescriptors: [NativeDisplayDescriptor] = []

        for displayObject in displays {
            guard let display = displayObject as? NSDictionary,
                  let identifier = display["Display Identifier"] as? String,
                  let spaces = display["Spaces"] as? NSArray else {
                return .failure(.malformedData("Unexpected managed display shape"))
            }
            let currentID = (display["Current Space"] as? NSDictionary).flatMap { number($0["id64"]) }
            displayDescriptors.append(.init(displayIdentifier: identifier, currentSpaceRuntimeID: currentID))
            for (index, object) in spaces.enumerated() {
                guard let space = object as? NSDictionary, let runtimeID = number(space["id64"]) else {
                    return .failure(.malformedData("Unexpected native Space shape"))
                }
                let type = number(space["type"]).map(Int.init) ?? -1
                let kind: NativeSpaceKind = type == 0 ? .userDesktop : (type == 4 ? .fullScreen : .unknown(rawValue: type))
                descriptors.append(.init(
                    runtimeID: runtimeID,
                    uuid: space["uuid"] as? String,
                    displayIdentifier: identifier,
                    position: index,
                    kind: kind,
                    isCurrent: runtimeID == currentID
                ))
            }
        }
        return .success(.init(displays: displayDescriptors, spaces: descriptors, separateSpaces: NSScreen.screensHaveSeparateSpaces))
    }

    private func number(_ value: Any?) -> UInt64? {
        (value as? NSNumber).map { $0.uint64Value }
    }
}

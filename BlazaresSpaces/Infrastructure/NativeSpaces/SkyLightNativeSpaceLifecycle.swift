import AppKit
import CoreGraphics
import Foundation

private nonisolated(unsafe) let nativeSpaceSkyLightPath = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"

/// Dynamic SkyLight lifecycle bridge.  The symbols are deliberately resolved
/// at runtime: they are private, and linking them weakly would make an ABI
/// mismatch a process-load failure.  A mutation is only reported as successful
/// after a fresh managed-display snapshot observes the expected delta.
struct SkyLightNativeSpaceLifecycle: NativeSpaceCreationProviding, NativeSpaceDestructionProviding {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CreateSpace = @convention(c) (Int32, UnsafeMutableRawPointer?, CFDictionary?) -> UInt64
    private typealias DestroySpace = @convention(c) (Int32, UInt64) -> Void

    let timeout: TimeInterval
    let pollInterval: TimeInterval

    nonisolated init(timeout: TimeInterval = 2.0, pollInterval: TimeInterval = 0.05) {
        self.timeout = timeout
        self.pollInterval = pollInterval
    }

    nonisolated func readTopology() -> Result<NativeSpaceTopology, NativeSpacesReadError> {
        SkyLightNativeSpacesProvider().readTopology()
    }

    nonisolated func createNativeSpace(displayIdentifier: String) -> Result<NativeSpaceDescriptor, NativeSpaceOperationError> {
        guard !displayIdentifier.isEmpty else { return .failure(.failed("Display identifier is empty")) }
        guard let before = readValidTopology() else {
            return .failure(.unavailable("Could not read a valid topology before native Space creation"))
        }
        guard let display = before.displays.first(where: { $0.displayIdentifier == displayIdentifier }) else {
            return .failure(.failed("Refused to create on an undiscovered display"))
        }
        guard let handle = dlopen(nativeSpaceSkyLightPath, RTLD_LAZY) else {
            return .failure(.unavailable("SkyLight framework is unavailable"))
        }
        defer { dlclose(handle) }
        guard let mainSymbol = dlsym(handle, "SLSMainConnectionID"),
              let createSymbol = dlsym(handle, "CGSSpaceCreate") else {
            return .failure(.unavailable("CGSSpaceCreate is unavailable on this macOS release"))
        }
        let connection = unsafeBitCast(mainSymbol, to: MainConnection.self)()
        let create = unsafeBitCast(createSymbol, to: CreateSpace.self)

        // CGSSpaceCreate's documented internal option is `type`; the Dock is
        // responsible for display placement.  Include the observed display as
        // advisory metadata where supported, then verify the actual delta.
        let options: NSDictionary = [
            "type": NSNumber(value: 0),
            "display": displayIdentifier
        ]
        let createdID = create(connection, nil, options as CFDictionary)
        guard createdID != 0 else { return .failure(.failed("CGSSpaceCreate returned id 0")) }

        guard let after = waitForTopologyChange(from: before) else {
            return .failure(.failed("Native Space creation did not produce a readable topology delta"))
        }
        let beforeIDs = Set(before.spaces.map(\.runtimeID))
        let candidates = after.spaces.filter {
            $0.displayIdentifier == display.displayIdentifier &&
            $0.kind == .userDesktop &&
            !beforeIDs.contains($0.runtimeID)
        }
        guard candidates.count == 1, let observed = candidates.first else {
            return .failure(.failed("Creation result was ambiguous or appeared on the wrong display"))
        }
        guard observed.runtimeID == createdID else {
            return .failure(.failed("Created Space identity could not be correlated safely"))
        }
        return .success(observed)
    }

    nonisolated func destroyNativeSpace(_ space: NativeSpaceDescriptor, confirmedOwnedByBlazaresSpaces: Bool) -> Result<Void, NativeSpaceOperationError> {
        guard confirmedOwnedByBlazaresSpaces else { return .failure(.unsafe("Refused to destroy an unowned native Space")) }
        guard let before = readValidTopology(),
              let observed = before.spaces.first(where: { NativeSpaceIdentity(space).matches($0) }) else {
            return .failure(.staleIdentity("Owned Space is absent or its identity is stale"))
        }
        guard observed.kind == .userDesktop else { return .failure(.unsafe("Only ordinary user Spaces may be destroyed")) }
        guard !observed.isCurrent else { return .failure(.unsafe("Refused to destroy the currently focused Space")) }
        let ordinary = before.spaces.filter { $0.displayIdentifier == observed.displayIdentifier && $0.kind == .userDesktop }
        guard ordinary.count > 1 else { return .failure(.unsafe("Refused to destroy the last ordinary Space on a display")) }
        guard let handle = dlopen(nativeSpaceSkyLightPath, RTLD_LAZY) else { return .failure(.unavailable("SkyLight framework is unavailable")) }
        defer { dlclose(handle) }
        guard let mainSymbol = dlsym(handle, "SLSMainConnectionID"),
              let destroySymbol = dlsym(handle, "CGSSpaceDestroy") else {
            return .failure(.unavailable("CGSSpaceDestroy is unavailable on this macOS release"))
        }
        let connection = unsafeBitCast(mainSymbol, to: MainConnection.self)()
        let destroy = unsafeBitCast(destroySymbol, to: DestroySpace.self)
        destroy(connection, observed.runtimeID)
        guard let after = waitForRemoval(identity: NativeSpaceIdentity(observed), from: before) else {
            return .failure(.failed("Native Space destruction was not verified by a fresh topology read"))
        }
        _ = after
        return .success(())
    }

    nonisolated var symbolsAvailable: Bool {
        guard let handle = dlopen(nativeSpaceSkyLightPath, RTLD_LAZY) else { return false }
        defer { dlclose(handle) }
        return dlsym(handle, "SLSMainConnectionID") != nil &&
            dlsym(handle, "CGSSpaceCreate") != nil &&
            dlsym(handle, "CGSSpaceDestroy") != nil
    }

    private nonisolated func readValidTopology() -> NativeSpaceTopology? {
        guard case let .success(topology) = SkyLightNativeSpacesProvider().readTopology(),
              case .success = NativeSpaceTopologyValidator().validate(topology) else { return nil }
        return topology.normalized
    }

    private nonisolated func waitForTopologyChange(from before: NativeSpaceTopology) -> NativeSpaceTopology? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let current = readValidTopology(), current.normalized != before.normalized { return current }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        return nil
    }

    private nonisolated func waitForRemoval(identity: NativeSpaceIdentity, from before: NativeSpaceTopology) -> NativeSpaceTopology? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let current = readValidTopology(), current.spaces.first(where: { identity.matches($0) }) == nil { return current }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        return nil
    }
}

import AppKit
import CoreGraphics
import Foundation
import ObjectiveC

// Swift 5.9 intentionally hides variadic objc_msgSend. The private selector
// used here has a fixed ABI, so expose only that typed entry point.
@_silgen_name("objc_msgSend")
private func blazaresObjcMsgSend(_ receiver: AnyObject, _ selector: Selector, _ windows: AnyObject, _ spaceID: UInt64) -> AnyObject?

/// A deliberately small authorization value. Discovery and a runtime identity
/// do not grant permission to mutate a window; callers must explicitly mark the
/// identity as managed for the current session.
nonisolated struct NativeWindowMoveAuthorization: Equatable, Sendable {
    let isManaged: Bool
    let isNeverManage: Bool
    let isCitrixExcluded: Bool

    static let managed = NativeWindowMoveAuthorization(isManaged: true, isNeverManage: false, isCitrixExcluded: false)
}

protocol WindowCGWindowIDResolving: Sendable {
    nonisolated func resolve(_ identity: WindowRuntimeIdentity) -> Result<CGWindowID, NativeSpaceOperationError>
}

/// Resolves only an unambiguous CGWindowList result. AX enumeration indexes
/// are not treated as CGWindowIDs and are never used to guess between windows.
struct CGWindowListIdentityResolver: WindowCGWindowIDResolving {
    nonisolated init() {}

    nonisolated func resolve(_ identity: WindowRuntimeIdentity) -> Result<CGWindowID, NativeSpaceOperationError> {
        guard identity.processIdentifier > 0 else { return .failure(.staleIdentity("Window PID is invalid")) }
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return .failure(.unavailable("CGWindowListCopyWindowInfo returned no window list"))
        }
        let candidates = info.compactMap { item -> (CGWindowID, Int)? in
            guard let pid = item[kCGWindowOwnerPID as String] as? NSNumber,
                  pid.int32Value == identity.processIdentifier,
                  let number = item[kCGWindowNumber as String] as? NSNumber else { return nil }
            let layer = (item[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer == 0 else { return nil }
            return (CGWindowID(number.uint32Value), (item[kCGWindowName as String] as? String)?.isEmpty == false ? 1 : 0)
        }
        guard candidates.count == 1, let id = candidates.first?.0 else {
            return .failure(.staleIdentity(candidates.isEmpty ? "No unambiguous CGWindowID for runtime identity" : "CGWindowID resolution is ambiguous"))
        }
        return .success(id)
    }
}

protocol NativeWindowSpaceMutationBackend: Sendable {
    nonisolated var isAvailable: Bool { get }
    nonisolated func move(windowID: CGWindowID, to spaceID: UInt64) -> Result<Void, NativeSpaceOperationError>
    nonisolated func spaces(for windowID: CGWindowID) -> Result<Set<UInt64>, NativeSpaceOperationError>
}

/// SkyLight bridge for the modern bridged operation, with the older
/// SLSMoveWindowsToManagedSpace fallback when it is exported. Both operations
/// are private and therefore resolved at runtime; no private symbols leak out
/// of Infrastructure.
struct SkyLightWindowSpaceMutationBackend: NativeWindowSpaceMutationBackend {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias MoveWindows = @convention(c) (Int32, CFArray, UInt64) -> Int32
    private typealias PerformAsync = @convention(c) (AnyObject) -> Void
    private typealias CopySpaces = @convention(c) (Int32, UInt64, CFArray) -> Unmanaged<CFArray>?

    nonisolated init() {}

    nonisolated var isAvailable: Bool {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else { return false }
        defer { dlclose(handle) }
        let hasMove = dlsym(handle, "SLSMoveWindowsToManagedSpace") != nil
        let hasCopy = dlsym(handle, "SLSCopySpacesForWindows") != nil
        let hasAsync = dlsym(handle, "SLSPerformAsynchronousBridgedWindowManagementOperation") != nil
            && objc_getClass("SLSBridgedMoveWindowsToManagedSpaceOperation") != nil
        return hasCopy && (hasAsync || hasMove)
    }

    nonisolated func move(windowID: CGWindowID, to spaceID: UInt64) -> Result<Void, NativeSpaceOperationError> {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else { return .failure(.unavailable("SkyLight framework unavailable")) }
        defer { dlclose(handle) }
        guard let connectionSymbol = dlsym(handle, "SLSMainConnectionID"),
              let connection = Optional(unsafeBitCast(connectionSymbol, to: MainConnection.self)()) else {
            return .failure(.unavailable("SLSMainConnectionID unavailable"))
        }
        let wid = UInt32(windowID)
        let windows = [NSNumber(value: wid)] as NSArray
        if let asyncSymbol = dlsym(handle, "SLSPerformAsynchronousBridgedWindowManagementOperation"),
           let cls = objc_getClass("SLSBridgedMoveWindowsToManagedSpaceOperation") {
            let perform = unsafeBitCast(asyncSymbol, to: PerformAsync.self)
            let selector = sel_registerName("initWithWindows:spaceID:")
            guard let operation = class_createInstance(cls, 0) else { return .failure(.failed("Could not allocate bridged window operation")) }
            guard let initialized = blazaresObjcMsgSend(operation, selector, windows, spaceID) else { return .failure(.failed("Could not initialize bridged window operation")) }
            perform(initialized)
            return .success(())
        }
        guard let moveSymbol = dlsym(handle, "SLSMoveWindowsToManagedSpace") else { return .failure(.unavailable("No native window move symbol available")) }
        let move = unsafeBitCast(moveSymbol, to: MoveWindows.self)
        let status = move(connection, windows, spaceID)
        return status == 0 ? .success(()) : .failure(.failed("SLSMoveWindowsToManagedSpace returned (status)"))
    }

    nonisolated func spaces(for windowID: CGWindowID) -> Result<Set<UInt64>, NativeSpaceOperationError> {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else { return .failure(.unavailable("SkyLight framework unavailable")) }
        defer { dlclose(handle) }
        guard let connectionSymbol = dlsym(handle, "SLSMainConnectionID"), let copySymbol = dlsym(handle, "SLSCopySpacesForWindows") else { return .failure(.unavailable("SLSCopySpacesForWindows unavailable")) }
        let connection = unsafeBitCast(connectionSymbol, to: MainConnection.self)()
        let wid = UInt32(windowID)
        let windows = [NSNumber(value: wid)] as NSArray
        let result = unsafeBitCast(copySymbol, to: CopySpaces.self)(connection, 0x7, windows)?.takeRetainedValue()
        guard let result else { return .failure(.failed("SLSCopySpacesForWindows returned NULL")) }
        let values = (result as NSArray).compactMap { ($0 as? NSNumber)?.uint64Value }
        return .success(Set(values))
    }
}

struct NativeWindowSpaceMover: Sendable {
    let resolver: any WindowCGWindowIDResolving
    let backend: any NativeWindowSpaceMutationBackend
    let timeout: TimeInterval
    let pollInterval: TimeInterval

    nonisolated init(resolver: any WindowCGWindowIDResolving = CGWindowListIdentityResolver(), backend: any NativeWindowSpaceMutationBackend = SkyLightWindowSpaceMutationBackend(), timeout: TimeInterval = 1.5, pollInterval: TimeInterval = 0.05) {
        self.resolver = resolver; self.backend = backend; self.timeout = timeout; self.pollInterval = pollInterval
    }

    nonisolated func move(_ identity: WindowRuntimeIdentity, to space: NativeSpaceDescriptor, topology: NativeSpaceTopology, authorization: NativeWindowMoveAuthorization = .managed) -> Result<Void, NativeSpaceOperationError> {
        guard authorization.isManaged else { return .failure(.unsafe("Unmanaged windows cannot be moved")) }
        guard !authorization.isNeverManage else { return .failure(.unsafe("NEVER MANAGE windows cannot be moved")) }
        guard !authorization.isCitrixExcluded else { return .failure(.unsafe("Citrix windows are excluded by policy")) }
        guard space.kind == .userDesktop else { return .failure(.unsafe("Only ordinary user Native Spaces may receive windows")) }
        guard topology.spaces.contains(where: { NativeSpaceIdentity(space).matches($0) && $0.displayIdentifier == space.displayIdentifier }) else { return .failure(.staleIdentity("Target Native Space is not in the supplied topology")) }
        guard backend.isAvailable else { return .failure(.unavailable("SkyLight window-space mutation bridge unavailable")) }
        let resolved = resolver.resolve(identity)
        guard case let .success(windowID) = resolved else {
            if case let .failure(error) = resolved { return .failure(error) }
            return .failure(.staleIdentity("Window identity could not be resolved"))
        }
        let dispatched = backend.move(windowID: windowID, to: space.runtimeID)
        guard case .success = dispatched else {
            if case let .failure(error) = dispatched { return .failure(error) }
            return .failure(.failed("Native window move failed"))
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if case let .success(spaces) = backend.spaces(for: windowID), spaces.contains(space.runtimeID) { return .success(()) }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        return .failure(.failed("Window move was dispatched but verification timed out"))
    }
}

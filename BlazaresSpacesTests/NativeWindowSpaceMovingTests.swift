import CoreGraphics
import Foundation
import Testing
@testable import BlazaresSpaces

private struct FixedResolver: WindowCGWindowIDResolving {
    let result: Result<CGWindowID, NativeSpaceOperationError>
    nonisolated func resolve(_ identity: WindowRuntimeIdentity) -> Result<CGWindowID, NativeSpaceOperationError> { result }
}

private final class RecordingBackend: NativeWindowSpaceMutationBackend, @unchecked Sendable {
    let available: Bool
    var moved: (CGWindowID, UInt64)?
    var memberships: Set<UInt64>
    init(available: Bool = true, memberships: Set<UInt64> = []) { self.available = available; self.memberships = memberships }
    nonisolated var isAvailable: Bool { available }
    nonisolated func move(windowID: CGWindowID, to spaceID: UInt64) -> Result<Void, NativeSpaceOperationError> {
        moved = (windowID, spaceID); memberships = [spaceID]; return .success(())
    }
    nonisolated func spaces(for windowID: CGWindowID) -> Result<Set<UInt64>, NativeSpaceOperationError> { .success(memberships) }
}

@Suite struct NativeWindowSpaceMovingTests {
    private let identity = WindowRuntimeIdentity(processIdentifier: 100, accessibilityIdentifier: "ax", enumerationIndex: 0)
    private let topology = NativeSpaceTopology(
        displays: [.init(displayIdentifier: "A", currentSpaceRuntimeID: 10)],
        spaces: [.init(runtimeID: 11, uuid: "a11", displayIdentifier: "A", position: 1, kind: .userDesktop, isCurrent: false)],
        separateSpaces: true
    )

    @Test func moveRequiresExplicitManagement() {
        let backend = RecordingBackend()
        let mover = NativeWindowSpaceMover(resolver: FixedResolver(result: .success(42)), backend: backend)
        let result = mover.move(identity, to: topology.spaces[0], topology: topology, authorization: .init(isManaged: false, isNeverManage: false, isCitrixExcluded: false))
        guard case .failure(.unsafe) = result else { Issue.record("Unmanaged window was not rejected"); return }
        #expect(backend.moved == nil)
    }

    @Test func moveDispatchesAndVerifiesMembership() {
        let backend = RecordingBackend()
        let mover = NativeWindowSpaceMover(resolver: FixedResolver(result: .success(42)), backend: backend)
        let result = mover.move(identity, to: topology.spaces[0], topology: topology)
        #expect(result == .success(()))
        #expect(backend.moved?.0 == 42)
        #expect(backend.moved?.1 == 11)
    }

    @Test func moveRejectsNeverManageAndCitrix() {
        let mover = NativeWindowSpaceMover(resolver: FixedResolver(result: .success(42)), backend: RecordingBackend())
        let never = mover.move(identity, to: topology.spaces[0], topology: topology, authorization: .init(isManaged: true, isNeverManage: true, isCitrixExcluded: false))
        let citrix = mover.move(identity, to: topology.spaces[0], topology: topology, authorization: .init(isManaged: true, isNeverManage: false, isCitrixExcluded: true))
        guard case .failure(.unsafe) = never, case .failure(.unsafe) = citrix else { Issue.record("Excluded windows were not rejected") ; return }
    }

    @Test func moveRejectsSpecialNativeSpaceKinds() {
        let backend = RecordingBackend()
        let mover = NativeWindowSpaceMover(resolver: FixedResolver(result: .success(42)), backend: backend)
        for kind in [NativeSpaceKind.fullScreen, .tiled, .unknown(rawValue: 99)] {
            let special = NativeSpaceDescriptor(runtimeID: 20, uuid: "special", displayIdentifier: "A", position: 1, kind: kind, isCurrent: false)
            let topology = NativeSpaceTopology(
                displays: [.init(displayIdentifier: "A", currentSpaceRuntimeID: 10)],
                spaces: [special],
                separateSpaces: true
            )
            let result = mover.move(identity, to: special, topology: topology)
            guard case .failure(.unsafe) = result else {
                Issue.record("Special Native Space kind was accepted as a window-move target: \(kind)")
                continue
            }
        }
        #expect(backend.moved == nil)
    }

    @Test func moveRejectsUnresolvedIdentity() {
        let mover = NativeWindowSpaceMover(resolver: FixedResolver(result: .failure(.staleIdentity("ambiguous"))), backend: RecordingBackend())
        let result = mover.move(identity, to: topology.spaces[0], topology: topology)
        guard case .failure(.staleIdentity("ambiguous")) = result else { Issue.record("Ambiguous identity was not rejected") ; return }
    }
}

import CoreGraphics
import Foundation
import Testing
@testable import BlazaresSpaces

struct FocusedWindowProviderTests {
    @Test("Focused snapshots preserve exact runtime identity")
    func snapshotKeepsPIDAndEnumerationIdentity() {
        let identity = WindowRuntimeIdentity(
            processIdentifier: 42,
            accessibilityIdentifier: nil,
            enumerationIndex: 3
        )
        let observation = FocusedWindowObservation(runtimeIdentity: identity, snapshot: nil)

        #expect(observation.runtimeIdentity.processIdentifier == 42)
        #expect(observation.runtimeIdentity.accessibilityIdentifier == nil)
        #expect(observation.runtimeIdentity.enumerationIndex == 3)
    }

    @Test("Focused-window port is read-only and supports pure fakes")
    func focusedWindowProviderCanBeFakedWithoutAX() {
        let expected = FocusedWindowObservation(
            runtimeIdentity: WindowRuntimeIdentity(
                processIdentifier: 42,
                accessibilityIdentifier: "focused",
                enumerationIndex: 1
            ),
            snapshot: nil
        )
        let provider = FakeFocusedWindowProvider(observation: expected)

        #expect(provider.focusedWindow(displays: []) == expected)
    }
}

private struct FakeFocusedWindowProvider: FocusedWindowProviding {
    let observation: FocusedWindowObservation?

    func focusedWindow(displays: [DisplaySnapshot]) -> FocusedWindowObservation? {
        observation
    }
}

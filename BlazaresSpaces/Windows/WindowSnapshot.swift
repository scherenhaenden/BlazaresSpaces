import CoreGraphics
import Foundation

/// Identity usable only while inspecting the current AX enumeration. macOS does not
/// expose a universal public window identifier that survives application restarts.
nonisolated struct WindowRuntimeIdentity: Hashable, Sendable {
    let processIdentifier: pid_t
    let accessibilityIdentifier: String?
    let enumerationIndex: Int

    init(processIdentifier: pid_t, accessibilityIdentifier: String?, enumerationIndex: Int) {
        self.processIdentifier = processIdentifier
        self.accessibilityIdentifier = accessibilityIdentifier
        self.enumerationIndex = enumerationIndex
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(processIdentifier)
        hasher.combine(accessibilityIdentifier)
        hasher.combine(enumerationIndex)
    }

    nonisolated static func == (lhs: WindowRuntimeIdentity, rhs: WindowRuntimeIdentity) -> Bool {
        lhs.processIdentifier == rhs.processIdentifier
            && lhs.accessibilityIdentifier == rhs.accessibilityIdentifier
            && lhs.enumerationIndex == rhs.enumerationIndex
    }
}

struct WindowSnapshot: Identifiable, Equatable, Sendable {
    var id: WindowRuntimeIdentity { runtimeIdentity }

    let runtimeIdentity: WindowRuntimeIdentity
    let applicationName: String
    let bundleIdentifier: String?
    let title: String?
    let role: String
    let subrole: String?
    let frame: CGRect
    let isMinimized: Bool?
    let isFullscreen: Bool?
    let displayID: CGDirectDisplayID?
}

struct WindowDiscoveryIssue: Identifiable, Equatable, Sendable {
    let id = UUID()
    let applicationName: String
    let processIdentifier: pid_t
    let message: String

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.applicationName == rhs.applicationName
            && lhs.processIdentifier == rhs.processIdentifier
            && lhs.message == rhs.message
    }
}

struct WindowDiscoveryResult: Equatable, Sendable {
    let windows: [WindowSnapshot]
    let issues: [WindowDiscoveryIssue]
}

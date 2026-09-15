import Foundation

struct PersistedStateEnvelope: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let state: PersistedStateV1

    init(schemaVersion: Int = Self.currentSchemaVersion, state: PersistedStateV1) {
        self.schemaVersion = schemaVersion
        self.state = state
    }
}

/// Version-one storage DTO. It is deliberately separate from runtime models so
/// process IDs, AX identifiers, and temporary parking state cannot leak to disk.
struct PersistedStateV1: Codable, Equatable, Sendable {
    struct Workspace: Codable, Equatable, Sendable {
        let id: String
        let name: String
    }

    struct ShortcutConfiguration: Codable, Equatable, Sendable {
        var enabled: Bool
        var modifierRawValue: UInt
        var desktopKeyCodes: [Int]
        var nextKeyCode: Int
        var previousKeyCode: Int

        init(
            enabled: Bool = true,
            modifierRawValue: UInt,
            desktopKeyCodes: [Int],
            nextKeyCode: Int,
            previousKeyCode: Int
        ) {
            self.enabled = enabled
            self.modifierRawValue = modifierRawValue
            self.desktopKeyCodes = desktopKeyCodes
            self.nextKeyCode = nextKeyCode
            self.previousKeyCode = previousKeyCode
        }
    }

    struct Preferences: Codable, Equatable, Sendable {
        /// Persisted intent never authorizes an external mutation by itself.
        var requiresExplicitRestoreConfirmation: Bool

        init(requiresExplicitRestoreConfirmation: Bool = true) {
            self.requiresExplicitRestoreConfirmation = requiresExplicitRestoreConfirmation
        }
    }

    struct ManagedWindow: Codable, Equatable, Sendable {
        let id: ManagedWindowID
        let descriptor: PersistedWindowDescriptor
        let workspaceIDs: Set<String>
        let sticky: Bool
        let logicalGeometry: LogicalWindowGeometry

        init(
            id: ManagedWindowID,
            descriptor: PersistedWindowDescriptor,
            workspaceIDs: Set<String>,
            sticky: Bool,
            logicalGeometry: LogicalWindowGeometry
        ) {
            self.id = id
            self.descriptor = descriptor
            self.workspaceIDs = workspaceIDs
            self.sticky = sticky
            self.logicalGeometry = logicalGeometry
        }
    }

    let workspaces: [Workspace]
    let workspaceOrder: [String]
    let activeWorkspaceID: String
    let shortcuts: ShortcutConfiguration
    let preferences: Preferences
    let managedWindows: [ManagedWindow]
}


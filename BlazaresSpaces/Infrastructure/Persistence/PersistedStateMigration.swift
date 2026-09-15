import Foundation

enum PersistedStateDecodeResult: Equatable, Sendable {
    case loaded(PersistedStateV1)
    case unsupported(schemaVersion: Int)
    case corrupted(description: String)
}

struct PersistedStateMigrator: Sendable {
    private struct Header: Decodable {
        let schemaVersion: Int
    }

    private let decoder: JSONDecoder

    init(decoder: JSONDecoder = JSONDecoder()) {
        self.decoder = decoder
    }

    func decode(_ data: Data) -> PersistedStateDecodeResult {
        let version: Int
        do {
            version = try decoder.decode(Header.self, from: data).schemaVersion
        } catch {
            return .corrupted(description: "The persistence envelope is not valid JSON or has no schema version: \(error.localizedDescription)")
        }

        guard version == PersistedStateEnvelope.currentSchemaVersion else {
            return .unsupported(schemaVersion: version)
        }

        do {
            let envelope = try decoder.decode(PersistedStateEnvelope.self, from: data)
            let issues = PersistedStateValidator().validate(envelope.state)
            guard issues.isEmpty else {
                return .corrupted(description: issues.map(\.message).joined(separator: " "))
            }
            return .loaded(envelope.state)
        } catch {
            return .corrupted(description: "Schema V\(version) could not be decoded: \(error.localizedDescription)")
        }
    }
}

struct PersistedStateValidationIssue: Equatable, Sendable {
    let message: String
}

struct PersistedStateValidator: Sendable {
    init() {}

    func validate(_ state: PersistedStateV1) -> [PersistedStateValidationIssue] {
        var issues: [PersistedStateValidationIssue] = []
        let workspaceIDs = state.workspaces.map(\.id)
        let workspaceSet = Set(workspaceIDs)

        if workspaceIDs.isEmpty {
            issues.append(.init(message: "At least one workspace is required."))
        }
        if workspaceSet.count != workspaceIDs.count {
            issues.append(.init(message: "Workspace identifiers must be unique."))
        }
        if state.workspaces.contains(where: { $0.id.isEmpty || $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            issues.append(.init(message: "Workspace identifiers and names must not be empty."))
        }
        if state.workspaceOrder.count != workspaceIDs.count || Set(state.workspaceOrder) != workspaceSet {
            issues.append(.init(message: "Workspace order must contain every workspace exactly once."))
        }
        if !workspaceSet.contains(state.activeWorkspaceID) {
            issues.append(.init(message: "The active workspace must exist."))
        }

        let managedIDs = state.managedWindows.map(\.id)
        if Set(managedIDs).count != managedIDs.count {
            issues.append(.init(message: "Managed-window identifiers must be unique."))
        }
        for window in state.managedWindows {
            if !window.workspaceIDs.isSubset(of: workspaceSet) {
                issues.append(.init(message: "Managed-window memberships must reference existing workspaces."))
            }
            if !window.sticky && window.workspaceIDs.isEmpty {
                issues.append(.init(message: "A non-sticky managed window must belong to at least one workspace."))
            }
            if window.descriptor.applicationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || window.descriptor.role.isEmpty {
                issues.append(.init(message: "Managed-window descriptors require an application name and role."))
            }
            if !isValid(window.logicalGeometry.absolute, normalized: false) {
                issues.append(.init(message: "Logical absolute geometry must be finite and have positive dimensions."))
            }
            if let normalized = window.logicalGeometry.normalized, !isValid(normalized, normalized: true) {
                issues.append(.init(message: "Normalized geometry must be finite and have positive dimensions."))
            }
        }
        return issues
    }

    private func isValid(_ rect: WindowGeometryRect, normalized: Bool) -> Bool {
        let values = [rect.x, rect.y, rect.width, rect.height]
        guard values.allSatisfy(\.isFinite), rect.width > 0, rect.height > 0 else { return false }
        // Partially off-screen and oversized windows are valid inputs. Mapping
        // clamps them conservatively when a topology changes.
        return !normalized || rect.width <= 4 && rect.height <= 4
    }
}


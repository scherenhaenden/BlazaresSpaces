import CoreGraphics
import Foundation

/// Stable in-memory identity for a logical workspace. The collection is dynamic;
/// the two values below are only convenient defaults for the first experiment.
struct WorkspaceID: RawRepresentable, Hashable, Identifiable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }

    var id: String { rawValue }
    var description: String { rawValue }

    static let workspace1 = WorkspaceID("workspace-1")
    static let workspace2 = WorkspaceID("workspace-2")
}

struct WorkspaceMember: Identifiable, Equatable, Sendable {
    let id: WindowRuntimeIdentity
    let authorizedWindow: AuthorizedExternalWindow
    var logicalSnapshot: WindowSnapshot
    /// Explicit memberships. `visibleOnAllWorkspaces` is intentionally separate
    /// so a sticky window also appears in workspaces created later.
    var workspaceIDs: Set<WorkspaceID>
    var visibleOnAllWorkspaces: Bool
    var isParked = false
    var parkedFrame: CGRect?

    init(
        authorizedWindow: AuthorizedExternalWindow,
        logicalSnapshot: WindowSnapshot,
        workspaceIDs: Set<WorkspaceID> = [],
        visibleOnAllWorkspaces: Bool = false
    ) {
        id = authorizedWindow.runtimeIdentity
        self.authorizedWindow = authorizedWindow
        self.logicalSnapshot = logicalSnapshot
        self.workspaceIDs = workspaceIDs
        self.visibleOnAllWorkspaces = visibleOnAllWorkspaces
    }
}

struct LogicalWorkspace: Identifiable, Equatable, Sendable {
    let id: WorkspaceID
    var name: String
    /// This is the resolved view for the workspace and may include shared/sticky
    /// members. The manager keeps membership truth in `WorkspaceMember` values.
    var members: [WorkspaceMember]

    init(id: WorkspaceID, name: String, members: [WorkspaceMember] = []) {
        self.id = id
        self.name = name
        self.members = members
    }
}

struct WorkspaceManager: Equatable, Sendable {
    private(set) var activeWorkspaceID: WorkspaceID = .workspace1
    private(set) var workspaces: [WorkspaceID: LogicalWorkspace] = [
        .workspace1: LogicalWorkspace(id: .workspace1, name: "Desktop 1"),
        .workspace2: LogicalWorkspace(id: .workspace2, name: "Desktop 2")
    ]
    private(set) var workspaceOrder: [WorkspaceID] = [.workspace1, .workspace2]

    var activeWorkspace: LogicalWorkspace { workspace(for: activeWorkspaceID) }
    var workspaceIDs: [WorkspaceID] { workspaceOrder.filter { workspaces[$0] != nil } }

    func workspace(for id: WorkspaceID) -> LogicalWorkspace {
        guard var workspace = workspaces[id] else {
            return LogicalWorkspace(id: id, name: id.rawValue)
        }
        workspace.members = members(in: id)
        return workspace
    }

    func members(in workspaceID: WorkspaceID) -> [WorkspaceMember] {
        var resolved: [WindowRuntimeIdentity: WorkspaceMember] = [:]
        for workspace in workspaces.values {
            for member in workspace.members where member.visibleOnAllWorkspaces || member.workspaceIDs.contains(workspaceID) {
                resolved[member.id] = member
            }
        }
        return resolved.values.sorted {
            ($0.authorizedWindow.applicationName, $0.id.processIdentifier, $0.id.enumerationIndex)
                < ($1.authorizedWindow.applicationName, $1.id.processIdentifier, $1.id.enumerationIndex)
        }
    }

    func member(for identity: WindowRuntimeIdentity) -> WorkspaceMember? {
        allMembers.first(where: { $0.id == identity })
    }

    func workspaceContaining(_ identity: WindowRuntimeIdentity) -> Set<WorkspaceID> {
        guard let member = member(for: identity) else { return [] }
        return member.visibleOnAllWorkspaces ? Set(workspaceIDs) : member.workspaceIDs
    }

    mutating func addWorkspace(name: String? = nil) -> WorkspaceID {
        let ordinal = workspaceOrder.count + 1
        let id = WorkspaceID("workspace-" + String(ordinal) + "-" + UUID().uuidString.prefix(8).lowercased())
        let defaultName = "Desktop " + String(ordinal)
        workspaces[id] = LogicalWorkspace(id: id, name: name?.isEmpty == false ? name! : defaultName)
        workspaceOrder.append(id)
        return id
    }

    mutating func renameWorkspace(_ id: WorkspaceID, name: String) -> Bool {
        guard var workspace = workspaces[id], !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        workspace.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        workspaces[id] = workspace
        return true
    }

    /// Deletes only the logical container. When members would otherwise lose all
    /// membership, a destination must be supplied explicitly; windows are never
    /// closed or destroyed by this operation.
    mutating func deleteWorkspace(_ id: WorkspaceID, moveExclusiveMembersTo destination: WorkspaceID? = nil) -> Bool {
        guard workspaces[id] != nil, workspaceOrder.count > 1 else { return false }
        let affected = allMembers.filter { !$0.visibleOnAllWorkspaces && $0.workspaceIDs == [id] }
        if !affected.isEmpty {
            guard let destination, destination != id, workspaces[destination] != nil else { return false }
        }
        if let destination {
            for member in affected { addMembership(member.id, to: destination) }
        }
        removeMembershipFromAllMembers(id)
        workspaces.removeValue(forKey: id)
        workspaceOrder.removeAll { $0 == id }
        if activeWorkspaceID == id { activeWorkspaceID = workspaceOrder[0] }
        return true
    }

    mutating func activate(_ id: WorkspaceID) -> Bool {
        guard workspaces[id] != nil else { return false }
        activeWorkspaceID = id
        return true
    }

    /// MOVE TO WORKSPACE: replace all explicit memberships.
    mutating func moveToWorkspace(_ member: WorkspaceMember, workspaceID: WorkspaceID) {
        guard workspaces[workspaceID] != nil else { return }
        var updated = self.member(for: member.id) ?? member
        updated.workspaceIDs = [workspaceID]
        updated.visibleOnAllWorkspaces = false
        replaceMemberEverywhere(updated)
        ensureMemberPresent(updated, in: workspaceID)
    }

    /// ADD TO / SHOW ON WORKSPACE: retain existing memberships.
    mutating func addToWorkspace(_ member: WorkspaceMember, workspaceID: WorkspaceID) {
        guard workspaces[workspaceID] != nil else { return }
        var updated = self.member(for: member.id) ?? member
        updated.workspaceIDs.insert(workspaceID)
        replaceMemberEverywhere(updated)
        ensureMemberPresent(updated, in: workspaceID)
    }

    mutating func setVisibleOnAllWorkspaces(_ member: WorkspaceMember, visible: Bool) {
        var updated = self.member(for: member.id) ?? member
        updated.visibleOnAllWorkspaces = visible
        replaceMemberEverywhere(updated)
        if visible {
            for id in workspaceOrder { ensureMemberPresent(updated, in: id) }
        }
    }

    mutating func replaceMember(_ member: WorkspaceMember, in workspaceID: WorkspaceID) {
        replaceMemberEverywhere(member)
        ensureMemberPresent(member, in: workspaceID)
    }

    mutating func replaceWorkspace(_ workspace: LogicalWorkspace) {
        guard workspaces[workspace.id] != nil else { return }
        var stored = workspace
        stored.members = workspace.members.filter { !$0.visibleOnAllWorkspaces || $0.workspaceIDs.contains(workspace.id) }
        workspaces[workspace.id] = stored
    }

    mutating func remove(_ identity: WindowRuntimeIdentity) {
        for id in workspaceOrder { workspaces[id]?.members.removeAll { $0.id == identity } }
    }

    var allMembers: [WorkspaceMember] {
        var unique: [WindowRuntimeIdentity: WorkspaceMember] = [:]
        for workspace in workspaces.values {
            for member in workspace.members { unique[member.id] = member }
        }
        return Array(unique.values)
    }

    private mutating func addMembership(_ identity: WindowRuntimeIdentity, to workspaceID: WorkspaceID) {
        guard let member = member(for: identity) else { return }
        addToWorkspace(member, workspaceID: workspaceID)
    }

    private mutating func removeMembershipFromAllMembers(_ workspaceID: WorkspaceID) {
        for member in allMembers {
            var updated = member
            updated.workspaceIDs.remove(workspaceID)
            replaceMemberEverywhere(updated)
        }
    }

    private mutating func replaceMemberEverywhere(_ member: WorkspaceMember) {
        for id in workspaceOrder {
            guard var workspace = workspaces[id] else { continue }
            for index in workspace.members.indices where workspace.members[index].id == member.id {
                workspace.members[index] = member
            }
            workspaces[id] = workspace
        }
    }

    private mutating func ensureMemberPresent(_ member: WorkspaceMember, in workspaceID: WorkspaceID) {
        guard var workspace = workspaces[workspaceID] else { return }
        if let index = workspace.members.firstIndex(where: { $0.id == member.id }) {
            workspace.members[index] = member
        } else {
            workspace.members.append(member)
        }
        workspaces[workspaceID] = workspace
    }
}

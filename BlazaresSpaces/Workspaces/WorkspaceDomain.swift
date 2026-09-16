import CoreGraphics
import Foundation

struct WorkspaceScreenAssignment: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let displayID: UInt32
    let displayName: String

    init(workspaceID: WorkspaceID, displayID: UInt32, displayName: String) {
        self.workspaceID = workspaceID
        self.displayID = displayID
        self.displayName = displayName
    }
}

/// Stable in-memory identity for a logical workspace. The collection is dynamic;
/// the two values below are only convenient defaults for the first experiment.
struct WorkspaceID: RawRepresentable, Hashable, Identifiable, Sendable, Codable, CustomStringConvertible {
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
    /// Durable logical identity. Runtime identity remains the compatibility ID
    /// for the active AX session, but must never be serialized as this value.
    let managedWindowID: ManagedWindowID
    let authorizedWindow: AuthorizedExternalWindow
    var logicalSnapshot: WindowSnapshot
    /// Explicit memberships. `visibleOnAllWorkspaces` is intentionally separate
    /// so a sticky window also appears in workspaces created later.
    var workspaceIDs: Set<WorkspaceID>
    var visibleOnAllWorkspaces: Bool
    var screenAssignments: [WorkspaceID: WorkspaceScreenAssignment]
    var isParked = false
    var parkedFrame: CGRect?

    init(
        managedWindowID: ManagedWindowID = ManagedWindowID(),
        authorizedWindow: AuthorizedExternalWindow,
        logicalSnapshot: WindowSnapshot,
        workspaceIDs: Set<WorkspaceID> = [],
        visibleOnAllWorkspaces: Bool = false,
        screenAssignments: [WorkspaceID: WorkspaceScreenAssignment] = [:]
    ) {
        id = authorizedWindow.runtimeIdentity
        self.managedWindowID = managedWindowID
        self.authorizedWindow = authorizedWindow
        self.logicalSnapshot = logicalSnapshot
        self.workspaceIDs = workspaceIDs
        self.visibleOnAllWorkspaces = visibleOnAllWorkspaces
        self.screenAssignments = screenAssignments
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
    /// The one canonical copy of every managed member. `LogicalWorkspace.members`
    /// values returned by `workspace(for:)` are resolved projections only.
    private var membersByManagedWindowID: [ManagedWindowID: WorkspaceMember] = [:]

    var activeWorkspace: LogicalWorkspace { workspace(for: activeWorkspaceID) }
    var workspaceIDs: [WorkspaceID] { workspaceOrder.filter { workspaces[$0] != nil } }

    struct Configuration: Codable, Equatable, Sendable {
        struct Entry: Codable, Equatable, Sendable {
            let id: String
            let name: String
        }

        let workspaces: [Entry]
        let activeWorkspaceID: String

        init(manager: WorkspaceManager) {
            workspaces = manager.workspaceOrder.compactMap { id in
                guard let workspace = manager.workspaces[id] else { return nil }
                return Entry(id: id.rawValue, name: workspace.name)
            }
            activeWorkspaceID = manager.activeWorkspaceID.rawValue
        }
    }

    func workspace(for id: WorkspaceID) -> LogicalWorkspace {
        guard var workspace = workspaces[id] else {
            return LogicalWorkspace(id: id, name: id.rawValue)
        }
        workspace.members = members(in: id)
        return workspace
    }

    func members(in workspaceID: WorkspaceID) -> [WorkspaceMember] {
        guard workspaces[workspaceID] != nil else { return [] }
        return membersByManagedWindowID.values.filter {
            $0.visibleOnAllWorkspaces || $0.workspaceIDs.contains(workspaceID)
        }.sorted {
            (
                $0.authorizedWindow.applicationName,
                $0.id.processIdentifier,
                $0.id.enumerationIndex,
                $0.managedWindowID.rawValue.uuidString
            ) < (
                $1.authorizedWindow.applicationName,
                $1.id.processIdentifier,
                $1.id.enumerationIndex,
                $1.managedWindowID.rawValue.uuidString
            )
        }
    }

    func member(for identity: WindowRuntimeIdentity) -> WorkspaceMember? {
        membersByManagedWindowID.values.first(where: { $0.id == identity })
    }

    func member(for managedWindowID: ManagedWindowID) -> WorkspaceMember? {
        membersByManagedWindowID[managedWindowID]
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

    mutating func reorderWorkspaces(_ orderedIDs: [WorkspaceID]) -> Bool {
        guard Set(orderedIDs) == Set(workspaceIDs), orderedIDs.count == workspaceIDs.count else { return false }
        workspaceOrder = orderedIDs
        return true
    }

    mutating func moveWorkspace(_ id: WorkspaceID, by offset: Int) -> Bool {
        guard let index = workspaceOrder.firstIndex(of: id) else { return false }
        let target = index + offset
        guard workspaceOrder.indices.contains(target) else { return false }
        workspaceOrder.swapAt(index, target)
        return true
    }

    func nextWorkspaceID(after id: WorkspaceID? = nil, wraps: Bool = true) -> WorkspaceID? {
        guard !workspaceOrder.isEmpty else { return nil }
        let current = id ?? activeWorkspaceID
        guard let index = workspaceOrder.firstIndex(of: current) else { return workspaceOrder.first }
        let next = index + 1
        if next < workspaceOrder.count { return workspaceOrder[next] }
        return wraps ? workspaceOrder.first : nil
    }

    func previousWorkspaceID(before id: WorkspaceID? = nil, wraps: Bool = true) -> WorkspaceID? {
        guard !workspaceOrder.isEmpty else { return nil }
        let current = id ?? activeWorkspaceID
        guard let index = workspaceOrder.firstIndex(of: current) else { return workspaceOrder.first }
        let previous = index - 1
        if previous >= 0 { return workspaceOrder[previous] }
        return wraps ? workspaceOrder.last : nil
    }

    mutating func apply(configuration: Configuration) {
        var configured: [WorkspaceID: LogicalWorkspace] = [:]
        var order: [WorkspaceID] = []
        for item in configuration.workspaces {
            let id = WorkspaceID(item.id)
            guard configured[id] == nil else { continue }
            let trimmedName = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            configured[id] = LogicalWorkspace(id: id, name: trimmedName.isEmpty ? item.id : trimmedName)
            order.append(id)
        }
        if order.isEmpty { return }
        workspaces = configured
        workspaceOrder = order
        activeWorkspaceID = order.contains(WorkspaceID(configuration.activeWorkspaceID))
            ? WorkspaceID(configuration.activeWorkspaceID)
            : order[0]
        for (managedWindowID, var member) in membersByManagedWindowID {
            member.workspaceIDs.formIntersection(Set(order))
            member.screenAssignments = member.screenAssignments.filter { order.contains($0.key) }
            if member.workspaceIDs.isEmpty && !member.visibleOnAllWorkspaces {
                membersByManagedWindowID.removeValue(forKey: managedWindowID)
            } else {
                membersByManagedWindowID[managedWindowID] = member
            }
        }
    }

    var configuration: Configuration { Configuration(manager: self) }

    /// Deletes only the logical container. When members would otherwise lose all
    /// membership, a destination must be supplied explicitly; windows are never
    /// closed or destroyed by this operation.
    mutating func deleteWorkspace(_ id: WorkspaceID, moveExclusiveMembersTo destination: WorkspaceID? = nil) -> Bool {
        guard workspaces[id] != nil, workspaceOrder.count > 1 else { return false }
        if let destination {
            guard destination != id, workspaces[destination] != nil else { return false }
        }
        guard id != activeWorkspaceID || destination != nil else { return false }
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
        if activeWorkspaceID == id { activeWorkspaceID = destination ?? workspaceOrder[0] }
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
        storeCanonical(updated)
    }

    /// ADD TO / SHOW ON WORKSPACE: retain existing memberships.
    mutating func addToWorkspace(_ member: WorkspaceMember, workspaceID: WorkspaceID) {
        guard workspaces[workspaceID] != nil else { return }
        var updated = self.member(for: member.id) ?? member
        updated.workspaceIDs.insert(workspaceID)
        storeCanonical(updated)
    }

    mutating func setVisibleOnAllWorkspaces(_ member: WorkspaceMember, visible: Bool) {
        var updated = self.member(for: member.id) ?? member
        updated.visibleOnAllWorkspaces = visible
        storeCanonical(updated)
    }

    mutating func replaceMember(_ member: WorkspaceMember, in workspaceID: WorkspaceID) {
        guard workspaces[workspaceID] != nil else { return }
        storeCanonical(member)
    }

    mutating func assignScreen(_ display: DisplaySnapshot, to identity: WindowRuntimeIdentity, in workspaceID: WorkspaceID) -> Bool {
        guard var member = member(for: identity), workspaces[workspaceID] != nil else { return false }
        guard member.visibleOnAllWorkspaces || member.workspaceIDs.contains(workspaceID) else { return false }
        member.screenAssignments[workspaceID] = WorkspaceScreenAssignment(
            workspaceID: workspaceID, displayID: display.id, displayName: display.name
        )
        storeCanonical(member)
        return true
    }

    mutating func replaceWorkspace(_ workspace: LogicalWorkspace) {
        guard var stored = workspaces[workspace.id] else { return }
        stored.name = workspace.name
        stored.members = []
        workspaces[workspace.id] = stored
        for member in workspace.members {
            guard let existing = membersByManagedWindowID[member.managedWindowID], existing != member else { continue }
            storeCanonical(member)
        }
    }

    @discardableResult
    mutating func remove(_ identity: WindowRuntimeIdentity) -> WorkspaceMember? {
        let removed = member(for: identity)
        if let removed { membersByManagedWindowID.removeValue(forKey: removed.managedWindowID) }
        return removed
    }

    var allMembers: [WorkspaceMember] {
        membersByManagedWindowID.values.sorted {
            $0.managedWindowID.rawValue.uuidString < $1.managedWindowID.rawValue.uuidString
        }
    }

    private mutating func addMembership(_ identity: WindowRuntimeIdentity, to workspaceID: WorkspaceID) {
        guard let member = member(for: identity) else { return }
        addToWorkspace(member, workspaceID: workspaceID)
    }

    private mutating func removeMembershipFromAllMembers(_ workspaceID: WorkspaceID) {
        for member in allMembers {
            var updated = member
            updated.workspaceIDs.remove(workspaceID)
            updated.screenAssignments.removeValue(forKey: workspaceID)
            storeCanonical(updated)
        }
    }

    private mutating func storeCanonical(_ member: WorkspaceMember) {
        if let existing = self.member(for: member.id), existing.managedWindowID != member.managedWindowID {
            var canonical = member
            canonical = WorkspaceMember(
                managedWindowID: existing.managedWindowID,
                authorizedWindow: member.authorizedWindow,
                logicalSnapshot: member.logicalSnapshot,
                workspaceIDs: member.workspaceIDs,
                visibleOnAllWorkspaces: member.visibleOnAllWorkspaces,
                screenAssignments: member.screenAssignments
            )
            canonical.isParked = member.isParked
            canonical.parkedFrame = member.parkedFrame
            membersByManagedWindowID[existing.managedWindowID] = canonical
        } else {
            membersByManagedWindowID[member.managedWindowID] = member
        }
    }
}

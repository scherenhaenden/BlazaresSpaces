import Foundation

/// A pure description of the membership transition. It contains no AX calls and
/// can be validated before any external window is mutated.
struct WorkspaceSwitchPlan: Equatable, Sendable {
    let sourceWorkspaceID: WorkspaceID
    let targetWorkspaceID: WorkspaceID
    let membersToPark: [WorkspaceMember]
    let membersToRestore: [WorkspaceMember]

    var managedWindowIDsToPark: [ManagedWindowID] {
        membersToPark.map(\.managedWindowID)
    }

    var managedWindowIDsToRestore: [ManagedWindowID] {
        membersToRestore.map(\.managedWindowID)
    }
}

struct WorkspaceSwitchPlanner: Equatable, Sendable {
    func plan(from source: LogicalWorkspace, to target: LogicalWorkspace) -> WorkspaceSwitchPlan {
        let sourceIDs = Set(source.members.map(\.managedWindowID))
        let targetIDs = Set(target.members.map(\.managedWindowID))

        let toPark = source.members.filter {
            !$0.isParked
                && !$0.visibleOnAllWorkspaces
                && !targetIDs.contains($0.managedWindowID)
        }
        let toRestore = target.members.filter {
            !$0.visibleOnAllWorkspaces
                && !sourceIDs.contains($0.managedWindowID)
        }

        return WorkspaceSwitchPlan(
            sourceWorkspaceID: source.id,
            targetWorkspaceID: target.id,
            membersToPark: toPark,
            membersToRestore: toRestore
        )
    }

    func membersToPark(
        in workspace: LogicalWorkspace,
        excludingVisibleRuntimeIDs: Set<WindowRuntimeIdentity> = []
    ) -> [WorkspaceMember] {
        workspace.members.filter {
            !$0.isParked
                && !$0.visibleOnAllWorkspaces
                && !excludingVisibleRuntimeIDs.contains($0.id)
        }
    }
}

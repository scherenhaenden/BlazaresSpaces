import CoreGraphics
import Foundation
import Testing
@testable import BlazaresSpaces

struct WorkspaceDomainTests {
    private func snapshot(
        identifier: String,
        pid: pid_t = 100,
        frame: CGRect = CGRect(x: 20, y: 30, width: 800, height: 600)
    ) -> WindowSnapshot {
        WindowSnapshot(
            runtimeIdentity: WindowRuntimeIdentity(
                processIdentifier: pid,
                accessibilityIdentifier: identifier,
                enumerationIndex: 0
            ),
            applicationName: "Browser",
            bundleIdentifier: "com.example.browser",
            title: nil,
            role: "AXWindow",
            subrole: "AXStandardWindow",
            frame: frame,
            isMinimized: false,
            isFullscreen: false,
            displayID: 7
        )
    }

    private func member(
        managedWindowID: ManagedWindowID = ManagedWindowID(),
        identifier: String,
        workspaces: Set<WorkspaceID> = []
    ) -> WorkspaceMember {
        let snapshot = snapshot(identifier: identifier)
        let authorized = try! WindowAuthorization.authorize(
            snapshot,
            policy: .developmentDefaults
        ).get()
        return WorkspaceMember(
            managedWindowID: managedWindowID,
            authorizedWindow: authorized,
            logicalSnapshot: snapshot,
            workspaceIDs: workspaces
        )
    }

    @Test func managedWindowIdentityIsStableAcrossMembershipChanges() {
        var manager = WorkspaceManager()
        let original = member(identifier: "stable")

        manager.moveToWorkspace(original, workspaceID: .workspace1)
        manager.addToWorkspace(original, workspaceID: .workspace2)
        manager.moveToWorkspace(original, workspaceID: .workspace2)

        #expect(manager.member(for: original.id)?.managedWindowID == original.managedWindowID)
        #expect(manager.workspaceContaining(original.id) == [.workspace2])
    }

    @Test func screenPlacementIsScopedToVirtualSpaceAndRequiresMembership() {
        var manager = WorkspaceManager()
        let first = member(identifier: "screened", workspaces: [.workspace1])
        let second = DisplaySnapshot(id: 9, name: "Studio", frame: .zero, visibleFrame: .zero, backingScale: 1, isMain: false)
        manager.moveToWorkspace(first, workspaceID: .workspace1)

        #expect(manager.assignScreen(second, to: first.id, in: .workspace1))
        #expect(manager.member(for: first.id)?.screenAssignments[.workspace1]?.displayID == 9)
        #expect(!manager.assignScreen(second, to: first.id, in: .workspace2))
    }

    @Test func screenPlacementRoundTripsThroughPersistedState() throws {
        var manager = WorkspaceManager()
        let first = member(identifier: "persisted-screen", workspaces: [.workspace1])
        manager.moveToWorkspace(first, workspaceID: .workspace1)
        let display = DisplaySnapshot(id: 42, name: "Studio", frame: .zero, visibleFrame: .zero, backingScale: 2, isMain: false)
        #expect(manager.assignScreen(display, to: first.id, in: .workspace1))

        let state = PersistedStateV1.make(
            from: manager,
            shortcuts: GlobalShortcutConfiguration(),
            displays: [display]
        )
        let decoded = try JSONDecoder().decode(PersistedStateV1.self, from: JSONEncoder().encode(state))
        #expect(decoded.managedWindows.first?.screenAssignments == [
            WorkspaceScreenAssignment(workspaceID: .workspace1, displayID: 42, displayName: "Studio")
        ])
    }

    @Test func deletingWorkspacePrunesItsScreenPlacement() {
        var manager = WorkspaceManager()
        var first = member(identifier: "pruned-screen", workspaces: [.workspace1, .workspace2])
        manager.moveToWorkspace(first, workspaceID: .workspace1)
        manager.addToWorkspace(first, workspaceID: .workspace2)
        let display = DisplaySnapshot(id: 42, name: "Studio", frame: .zero, visibleFrame: .zero, backingScale: 2, isMain: false)
        #expect(manager.assignScreen(display, to: first.id, in: .workspace2))

        #expect(manager.deleteWorkspace(.workspace2, moveExclusiveMembersTo: .workspace1))
        first = manager.member(for: first.id)!
        #expect(first.screenAssignments[.workspace2] == nil)
    }

    @Test func managerKeepsOneCanonicalMemberForSharedWorkspaceProjections() {
        var manager = WorkspaceManager()
        var shared = member(identifier: "shared")
        manager.moveToWorkspace(shared, workspaceID: .workspace1)
        manager.addToWorkspace(shared, workspaceID: .workspace2)

        shared = manager.member(for: shared.id)!
        shared.logicalSnapshot = snapshot(
            identifier: "shared",
            frame: CGRect(x: 400, y: 300, width: 900, height: 700)
        )
        manager.replaceMember(shared, in: .workspace1)

        #expect(manager.allMembers.count == 1)
        #expect(manager.workspace(for: .workspace1).members[0].logicalSnapshot.frame == shared.logicalSnapshot.frame)
        #expect(manager.workspace(for: .workspace2).members[0].logicalSnapshot.frame == shared.logicalSnapshot.frame)
    }

    @Test func newlyConstructedRuntimeCopyCannotReplaceDurableIdentity() {
        var manager = WorkspaceManager()
        let original = member(identifier: "same-runtime")
        let reconstructed = member(identifier: "same-runtime")
        #expect(original.managedWindowID != reconstructed.managedWindowID)

        manager.moveToWorkspace(original, workspaceID: .workspace1)
        manager.addToWorkspace(reconstructed, workspaceID: .workspace2)

        #expect(manager.allMembers.count == 1)
        #expect(manager.member(for: original.id)?.managedWindowID == original.managedWindowID)
        #expect(manager.workspaceContaining(original.id) == [.workspace1, .workspace2])
    }

    @Test func activeWorkspaceDeletionRejectsInvalidReplacement() {
        var manager = WorkspaceManager()

        let sameIDRejected = manager.deleteWorkspace(.workspace1, moveExclusiveMembersTo: .workspace1)
        let missingIDRejected = manager.deleteWorkspace(.workspace1, moveExclusiveMembersTo: WorkspaceID("missing"))
        #expect(!sameIDRejected)
        #expect(!missingIDRejected)
        #expect(manager.activeWorkspaceID == .workspace1)
        #expect(manager.workspaceIDs == [.workspace1, .workspace2])
    }

    @Test func plannerUsesDurableLogicalIdentityRatherThanRuntimeIdentity() {
        let firstID = ManagedWindowID()
        let secondID = ManagedWindowID()
        let sourceMember = member(
            managedWindowID: firstID,
            identifier: "same-runtime",
            workspaces: [.workspace1]
        )
        let targetMember = member(
            managedWindowID: secondID,
            identifier: "same-runtime",
            workspaces: [.workspace2]
        )
        let source = LogicalWorkspace(id: .workspace1, name: "One", members: [sourceMember])
        let target = LogicalWorkspace(id: .workspace2, name: "Two", members: [targetMember])

        let plan = WorkspaceSwitchPlanner().plan(from: source, to: target)

        #expect(plan.managedWindowIDsToPark == [firstID])
        #expect(plan.managedWindowIDsToRestore == [secondID])
    }

    @Test func plannerLeavesSharedAndStickyMembersUntouched() {
        let sharedID = ManagedWindowID()
        let shared = member(
            managedWindowID: sharedID,
            identifier: "shared",
            workspaces: [.workspace1, .workspace2]
        )
        var sticky = member(identifier: "sticky", workspaces: [.workspace1])
        sticky.visibleOnAllWorkspaces = true
        let source = LogicalWorkspace(id: .workspace1, name: "One", members: [shared, sticky])
        let target = LogicalWorkspace(id: .workspace2, name: "Two", members: [shared, sticky])

        let plan = WorkspaceSwitchPlanner().plan(from: source, to: target)

        #expect(plan.membersToPark.isEmpty)
        #expect(plan.membersToRestore.isEmpty)
    }

    @Test func durableDescriptorEncodingContainsNoRuntimeOrSensitiveFields() throws {
        let descriptor = PersistedWindowDescriptor(
            bundleIdentifier: "com.example.browser",
            applicationName: "Browser",
            role: "AXWindow",
            subrole: "AXStandardWindow",
            userAlias: "Development browser"
        )

        let encoded = try JSONEncoder().encode(descriptor)
        let json = String(decoding: encoded, as: UTF8.self)

        #expect(!json.contains("title"))
        #expect(!json.contains("processIdentifier"))
        #expect(!json.contains("accessibilityIdentifier"))
        #expect(!json.contains("displayID"))
        #expect(!json.contains("parked"))
    }

    @Test func logicalGeometryRoundTripsAbsoluteNormalizedAndDisplayDescriptor() throws {
        let absolute = WindowGeometryRect(x: -1200, y: 100, width: 900, height: 700)
        let normalized = WindowGeometryRect(x: 0.1, y: 0.2, width: 0.5, height: 0.7)
        let display = PersistedDisplayDescriptor(
            name: "External Display",
            frameSize: WindowGeometryRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrameSize: WindowGeometryRect(x: 0, y: 0, width: 1920, height: 1040),
            backingScale: 2,
            wasMain: false
        )
        let geometry = LogicalWindowGeometry(
            absolute: absolute,
            normalized: normalized,
            display: display
        )

        let decoded = try JSONDecoder().decode(
            LogicalWindowGeometry.self,
            from: JSONEncoder().encode(geometry)
        )

        #expect(decoded == geometry)
        #expect(decoded.absolute.cgRect == CGRect(x: -1200, y: 100, width: 900, height: 700))
    }

    @Test func persistedWorkspaceOrderIsRestoredFromWorkspaceOrderField() {
        let third = WorkspaceID("workspace-3")
        let state = PersistedStateV1(
            workspaces: [
                .init(id: WorkspaceID.workspace1.rawValue, name: "One"),
                .init(id: WorkspaceID.workspace2.rawValue, name: "Two"),
                .init(id: third.rawValue, name: "Three")
            ],
            workspaceOrder: [third.rawValue, WorkspaceID.workspace1.rawValue, WorkspaceID.workspace2.rawValue],
            activeWorkspaceID: third.rawValue,
            shortcuts: .init(modifierRawValue: 0, desktopKeyCodes: [], nextKeyCode: 0, previousKeyCode: 0),
            preferences: .init(),
            managedWindows: []
        )
        var manager = WorkspaceManager()
        manager.apply(configuration: .init(persisted: state))
        #expect(manager.workspaceOrder == [third, .workspace1, .workspace2])
        #expect(manager.activeWorkspaceID == third)
    }

    @Test func workspaceCrudPreservesPositionalOrderAndActiveSelection() {
        var manager = WorkspaceManager()
        let research = manager.addWorkspace(name: "Research")
        let personal = manager.addWorkspace(name: "Personal")

        #expect(manager.workspaceOrder == [.workspace1, .workspace2, research, personal])
        #expect(manager.renameWorkspace(research, name: "Writing"))
        #expect(manager.reorderWorkspaces([personal, .workspace1, research, .workspace2]))
        #expect(manager.workspaceOrder == [personal, .workspace1, research, .workspace2])
        #expect(manager.activate(research))
        #expect(manager.activeWorkspaceID == research)

        #expect(manager.deleteWorkspace(personal))
        #expect(manager.workspaceOrder == [.workspace1, research, .workspace2])
        #expect(manager.activeWorkspaceID == research)
        #expect(manager.workspace(for: research).name == "Writing")
    }

    @Test func persistenceRoundTripRetainsOrderMembershipsAndStickyState() throws {
        var manager = WorkspaceManager()
        let development = manager.addWorkspace(name: "Development")
        let personal = manager.addWorkspace(name: "Personal")
        #expect(manager.reorderWorkspaces([development, .workspace1, personal, .workspace2]))
        #expect(manager.activate(personal))

        var managed = member(identifier: "persisted", workspaces: [.workspace1, development])
        managed.visibleOnAllWorkspaces = true
        manager.moveToWorkspace(managed, workspaceID: .workspace1)
        manager.addToWorkspace(managed, workspaceID: development)
        var canonical = manager.member(for: managed.id)!
        canonical.visibleOnAllWorkspaces = true
        manager.setVisibleOnAllWorkspaces(canonical, visible: true)

        let state = PersistedStateV1.make(
            from: manager,
            shortcuts: GlobalShortcutConfiguration(),
            displays: []
        )
        let decoded = try JSONDecoder().decode(
            PersistedStateEnvelope.self,
            from: JSONEncoder().encode(PersistedStateEnvelope(state: state))
        ).state

        #expect(decoded.workspaceOrder == manager.workspaceOrder.map(\.rawValue))
        #expect(decoded.activeWorkspaceID == manager.activeWorkspaceID.rawValue)
        #expect(decoded.managedWindows.count == 1)
        #expect(decoded.managedWindows[0].workspaceIDs == Set([WorkspaceID.workspace1.rawValue, development.rawValue]))
        #expect(decoded.managedWindows[0].sticky)
        #expect(PersistedStateValidator().validate(decoded).isEmpty)
    }

    @Test func migratorRejectsInvalidPositionalOrderWithoutApplyingIt() throws {
        let state = PersistedStateV1(
            workspaces: [
                .init(id: WorkspaceID.workspace1.rawValue, name: "One"),
                .init(id: WorkspaceID.workspace2.rawValue, name: "Two")
            ],
            workspaceOrder: [WorkspaceID.workspace1.rawValue],
            activeWorkspaceID: WorkspaceID.workspace1.rawValue,
            shortcuts: .init(modifierRawValue: 0, desktopKeyCodes: [], nextKeyCode: 0, previousKeyCode: 0),
            preferences: .init(),
            managedWindows: []
        )

        let result = PersistedStateMigrator().decode(
            JSONEncoder().encode(PersistedStateEnvelope(state: state))
        )
        if case .corrupted = result { #expect(true) }
        else { #expect(Bool(false), "Invalid positional order must be rejected") }
    }
}

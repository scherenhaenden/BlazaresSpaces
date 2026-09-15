//
//  BlazaresSpacesTests.swift
//  BlazaresSpacesTests
//
//  Created by Edward Flores on 15.09.26.
//

import CoreGraphics
import Foundation
import Testing
@testable import BlazaresSpaces

struct BlazaresSpacesTests {
    private func display(id: CGDirectDisplayID, frame: CGRect) -> DisplaySnapshot {
        DisplaySnapshot(id: id, name: "Display \(id)", frame: frame, visibleFrame: frame, backingScale: 1, isMain: id == 1)
    }

    private func window(
        app: String = "Safe App",
        bundle: String? = "com.example.safe",
        identifier: String? = "window-1",
        pid: pid_t = 42,
        frame: CGRect = CGRect(x: 10, y: 20, width: 400, height: 300)
    ) -> WindowSnapshot {
        WindowSnapshot(
            runtimeIdentity: WindowRuntimeIdentity(processIdentifier: pid, accessibilityIdentifier: identifier, enumerationIndex: 0),
            applicationName: app,
            bundleIdentifier: bundle,
            title: nil,
            role: "AXWindow",
            subrole: nil,
            frame: frame,
            isMinimized: nil,
            isFullscreen: nil,
            displayID: 1
        )
    }

    private func authorizedMember(_ snapshot: WindowSnapshot, workspaces: Set<WorkspaceID> = []) -> WorkspaceMember {
        let authorized = try! WindowAuthorization.authorize(snapshot, policy: .developmentDefaults).get()
        return WorkspaceMember(authorizedWindow: authorized, logicalSnapshot: snapshot, workspaceIDs: workspaces)
    }

    @Test func mapsWindowToDisplayWithLargestIntersection() {
        let displays = [
            display(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 800)),
            display(id: 2, frame: CGRect(x: 1000, y: 0, width: 1000, height: 800)),
        ]

        let result = DisplayMapper.displayID(
            for: CGRect(x: 900, y: 100, width: 500, height: 500),
            among: displays
        )

        #expect(result == 2)
    }

    @Test func tieBreakingUsesStableDisplayOrder() {
        let displays = [
            display(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 800)),
            display(id: 2, frame: CGRect(x: 1000, y: 0, width: 1000, height: 800)),
        ]

        #expect(DisplayMapper.displayID(for: CGRect(x: 900, y: 100, width: 200, height: 500), among: displays) == 1)
    }

    @Test func mapsAcrossNegativeDisplayCoordinates() {
        let displays = [
            display(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900)),
            display(id: 2, frame: CGRect(x: -1920, y: -180, width: 1920, height: 1080)),
        ]

        #expect(DisplayMapper.displayID(for: CGRect(x: -1200, y: 50, width: 800, height: 600), among: displays) == 2)
    }

    @Test func mapsOffscreenWindowToNearestDisplay() {
        let displays = [
            display(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 800)),
            display(id: 2, frame: CGRect(x: 1000, y: 0, width: 1000, height: 800)),
        ]

        #expect(DisplayMapper.displayID(for: CGRect(x: 2200, y: 100, width: 100, height: 100), among: displays) == 2)
    }

    @Test func returnsNilWhenNoDisplaysExist() {
        #expect(DisplayMapper.displayID(for: CGRect(x: 0, y: 0, width: 100, height: 100), among: []) == nil)
    }

    @Test func convertsAppKitFrameToAccessibilityCoordinates() {
        let aboveMain = CGRect(x: 100, y: 900, width: 1200, height: 800)
        let converted = DisplayManager.accessibilityFrame(fromAppKitFrame: aboveMain, primaryHeight: 900)

        #expect(converted == CGRect(x: 100, y: -800, width: 1200, height: 800))
    }

    @Test func workspaceSnapshotReportsRepresentedDisplays() {
        let snapshot = WorkspaceSnapshot(
            capturedAt: Date(timeIntervalSince1970: 123),
            displays: [display(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100))],
            windows: [
                WindowSnapshot(
                    runtimeIdentity: WindowRuntimeIdentity(processIdentifier: 10, accessibilityIdentifier: nil, enumerationIndex: 0),
                    applicationName: "Example",
                    bundleIdentifier: "com.example",
                    title: nil,
                    role: "AXWindow",
                    subrole: nil,
                    frame: CGRect(x: 0, y: 0, width: 50, height: 50),
                    isMinimized: nil,
                    isFullscreen: nil,
                    displayID: 1
                )
            ]
        )

        #expect(snapshot.windows.count == 1)
        #expect(snapshot.representedDisplayIDs == [1])
    }

    @Test func snapshotStoreReplacesPreviousCapture() {
        var store = WorkspaceSnapshotStore()
        let first = WorkspaceSnapshot(capturedAt: Date(timeIntervalSince1970: 1), displays: [], windows: [])
        let second = WorkspaceSnapshot(capturedAt: Date(timeIntervalSince1970: 2), displays: [], windows: [])

        store.replace(with: first)
        #expect(store.current?.capturedAt == first.capturedAt)
        store.replace(with: second)
        #expect(store.current?.capturedAt == second.capturedAt)
    }

    @Test func defaultPolicyExcludesCitrixByBundleAndName() {
        let policy = WindowManagementPolicy.developmentDefaults
        #expect(policy.exclusionReason(for: window(app: "Citrix Viewer", bundle: "com.citrix.receiver")) != nil)
        #expect(policy.exclusionReason(for: window(app: "Citrix Workspace", bundle: "com.other.client")) != nil)
        #expect(policy.exclusionReason(for: window()) == nil)
    }

    @Test func externalAuthorizationRequiresAXRuntimeIdentifier() {
        let result = WindowAuthorization.authorize(window(identifier: nil), policy: .developmentDefaults)
        let isExpectedFailure: Bool

        if case .failure(.missingRuntimeIdentifier) = result {
            isExpectedFailure = true
        } else {
            isExpectedFailure = false
        }
        #expect(isExpectedFailure)
    }

    @Test func externalAuthorizationRejectsExcludedWindow() {
        let result = WindowAuthorization.authorize(
            window(app: "Citrix Workspace", bundle: "com.citrix.workspace"),
            policy: .developmentDefaults
        )
        let isExpectedFailure: Bool

        if case .failure(.excluded) = result {
            isExpectedFailure = true
        } else {
            isExpectedFailure = false
        }
        #expect(isExpectedFailure)
    }

    @Test func restoreReportCountsPartialFailuresWithoutStopping() {
        let first = WindowRestoreResult(
            id: window(identifier: "one").runtimeIdentity,
            applicationName: "Safe App",
            processIdentifier: 42,
            requestedFrame: window(identifier: "one").frame,
            actualFrame: window(identifier: "one").frame,
            status: .restoredExactly,
            message: "ok"
        )
        let second = WindowRestoreResult(
            id: window(identifier: "two").runtimeIdentity,
            applicationName: "Closed App",
            processIdentifier: 43,
            requestedFrame: window(identifier: "two").frame,
            actualFrame: nil,
            status: .windowMissing,
            message: "missing"
        )

        let report = WindowRestoreReport(results: [first, second])
        #expect(report.requestedCount == 2)
        #expect(report.exactCount == 1)
        #expect(report.failedCount == 1)
    }

    @Test func frameComparisonClassifiesTolerance() {
        let requested = CGRect(x: 10, y: 20, width: 400, height: 300)
        #expect(WindowFrameComparison.isWithinTolerance(requested: requested, actual: requested.offsetBy(dx: 1, dy: -1), tolerance: 2))
        #expect(!WindowFrameComparison.isWithinTolerance(requested: requested, actual: requested.offsetBy(dx: 3, dy: 0), tolerance: 2))
    }

    @Test func runtimeIdentityDistinguishesTwoWindowsFromSameApplication() {
        let first = window(identifier: "window-a")
        let second = window(identifier: "window-b")
        #expect(first.runtimeIdentity.processIdentifier == second.runtimeIdentity.processIdentifier)
        #expect(first.runtimeIdentity.accessibilityIdentifier != second.runtimeIdentity.accessibilityIdentifier)
    }

    @Test func windowCanBelongToOneWorkspace() {
        var manager = WorkspaceManager()
        manager.moveToWorkspace(authorizedMember(window()), workspaceID: .workspace1)
        #expect(manager.workspaceContaining(window().runtimeIdentity) == [.workspace1])
        #expect(manager.workspace(for: .workspace1).members.count == 1)
    }

    @Test func windowCanBelongToMultipleWorkspacesAndAddPreservesMembership() {
        var manager = WorkspaceManager()
        let member = authorizedMember(window())
        manager.moveToWorkspace(member, workspaceID: .workspace1)
        manager.addToWorkspace(member, workspaceID: .workspace2)
        #expect(manager.workspaceContaining(member.id) == [.workspace1, .workspace2])
        #expect(manager.workspace(for: .workspace1).members.count == 1)
        #expect(manager.workspace(for: .workspace2).members.count == 1)
    }

    @Test func moveToReplacesExistingMemberships() {
        var manager = WorkspaceManager()
        let member = authorizedMember(window())
        manager.moveToWorkspace(member, workspaceID: .workspace1)
        manager.addToWorkspace(member, workspaceID: .workspace2)
        manager.moveToWorkspace(member, workspaceID: .workspace2)
        #expect(manager.workspaceContaining(member.id) == [.workspace2])
    }

    @Test func stickyWindowAppearsOnCurrentAndFutureWorkspaces() {
        var manager = WorkspaceManager()
        let member = authorizedMember(window())
        manager.moveToWorkspace(member, workspaceID: .workspace1)
        manager.setVisibleOnAllWorkspaces(member, visible: true)
        let newID = manager.addWorkspace()
        #expect(manager.workspace(for: .workspace2).members.contains(where: { $0.id == member.id }))
        #expect(manager.workspace(for: newID).members.contains(where: { $0.id == member.id }))
        #expect(manager.member(for: member.id)?.visibleOnAllWorkspaces == true)
    }

    @Test func sharedAndStickyWindowsRemainVisibleDuringSwitchPolicy() {
        var manager = WorkspaceManager()
        let shared = authorizedMember(window(identifier: "shared"))
        let sticky = authorizedMember(window(identifier: "sticky"))
        let sourceOnly = authorizedMember(window(identifier: "source"))
        let targetOnly = authorizedMember(window(identifier: "target"))
        manager.moveToWorkspace(shared, workspaceID: .workspace1)
        manager.addToWorkspace(shared, workspaceID: .workspace2)
        manager.moveToWorkspace(sticky, workspaceID: .workspace1)
        manager.setVisibleOnAllWorkspaces(sticky, visible: true)
        manager.moveToWorkspace(sourceOnly, workspaceID: .workspace1)
        manager.moveToWorkspace(targetOnly, workspaceID: .workspace2)

        let engine = WorkspaceSwitchEngine()
        let toPark = engine.membersToPark(from: manager.workspace(for: .workspace1), to: manager.workspace(for: .workspace2))
        let toRestore = engine.membersToRestore(from: manager.workspace(for: .workspace1), to: manager.workspace(for: .workspace2))
        #expect(toPark.map(\.id) == [sourceOnly.id])
        #expect(toRestore.map(\.id) == [targetOnly.id])
    }

    @Test func deletingWorkspaceDoesNotDestroyWindowsAndRequiresSafeDestination() {
        var manager = WorkspaceManager()
        let member = authorizedMember(window())
        manager.moveToWorkspace(member, workspaceID: .workspace2)
        #expect(manager.deleteWorkspace(.workspace2, moveExclusiveMembersTo: .workspace1) == true)
        #expect(manager.member(for: member.id) != nil)
        #expect(manager.workspaceContaining(member.id) == [.workspace1])
    }

    @Test func dynamicWorkspaceCreationRenameAndDeletion() {
        var manager = WorkspaceManager()
        let id = manager.addWorkspace(name: "Research")
        #expect(manager.workspaceIDs.contains(id))
        #expect(manager.renameWorkspace(id, name: "Writing") == true)
        #expect(manager.workspace(for: id).name == "Writing")
        #expect(manager.deleteWorkspace(id) == true)
        #expect(!manager.workspaceIDs.contains(id))
    }

    @Test func parkingUsesUnionTopologyAndDeterministicSlots() {
        let calculator = ParkingPositionCalculator(gap: 50, rowSpacing: 200)
        let displays = [
            display(id: 1, frame: CGRect(x: -1000, y: -100, width: 1000, height: 800)),
            display(id: 2, frame: CGRect(x: 0, y: 0, width: 1600, height: 900))
        ]
        let first = calculator.parkingFrame(slot: 0, windowSize: CGSize(width: 400, height: 300), displays: displays)!
        let second = calculator.parkingFrame(slot: 1, windowSize: CGSize(width: 400, height: 300), displays: displays)!
        #expect(first.minX > 1600)
        #expect(second.minY > first.minY)
    }

    @Test func workspaceOrderSupportsReorderingAndNextPreviousWrap() {
        var manager = WorkspaceManager()
        let third = manager.addWorkspace(name: "University")
        #expect(manager.workspaceOrder.count == 3)
        #expect(manager.workspaceOrder.last == third)
        let moved = manager.reorderWorkspaces([third, .workspace1, .workspace2])
        #expect(moved)
        #expect(manager.workspaceOrder.first == third)
        #expect(manager.nextWorkspaceID(after: .workspace2) == third)
        #expect(manager.previousWorkspaceID(before: third) == .workspace2)
    }

    @Test func deletingSharedWorkspaceRemovesOnlyThatMembership() {
        var manager = WorkspaceManager()
        let member = authorizedMember(window())
        manager.moveToWorkspace(member, workspaceID: .workspace1)
        manager.addToWorkspace(member, workspaceID: .workspace2)
        let deleted = manager.deleteWorkspace(.workspace2, moveExclusiveMembersTo: .workspace1)
        #expect(deleted)
        #expect(manager.member(for: member.id) != nil)
        #expect(manager.workspaceContaining(member.id) == [.workspace1])
    }

    @Test func activeWorkspaceDeletionRequiresExplicitReplacement() {
        var manager = WorkspaceManager()
        #expect(manager.deleteWorkspace(.workspace1) == false)
        #expect(manager.deleteWorkspace(.workspace1, moveExclusiveMembersTo: .workspace2) == true)
        #expect(manager.activeWorkspaceID == .workspace2)
    }

    @Test func emptyAndZeroManagedWorkspaceStatesAreValid() {
        var manager = WorkspaceManager()
        #expect(manager.allMembers.isEmpty)
        let empty = manager.addWorkspace(name: "Personal")
        #expect(manager.workspace(for: empty).members.isEmpty)
        let activated = manager.activate(empty)
        #expect(activated)
        #expect(manager.activeWorkspaceID == empty)
    }

    @Test func stopManagingRemovesOnlyTheManagedWindow() {
        var manager = WorkspaceManager()
        let member = authorizedMember(window())
        manager.moveToWorkspace(member, workspaceID: .workspace1)
        let removed = manager.remove(member.id)
        #expect(removed?.id == member.id)
        #expect(manager.allMembers.isEmpty)
    }

    @Test func workspaceConfigurationPersistsNamesOrderAndActiveOnly() {
        var manager = WorkspaceManager()
        let third = manager.addWorkspace(name: "University")
        let activated = manager.activate(third)
        #expect(activated)
        let configuration = manager.configuration
        var restored = WorkspaceManager()
        restored.apply(configuration: configuration)
        #expect(restored.workspaceOrder == manager.workspaceOrder)
        #expect(restored.workspace(for: third).name == "University")
        #expect(restored.activeWorkspaceID == third)
        #expect(restored.allMembers.isEmpty)
    }

    @Test func switchQueueKeepsOnlyLatestPendingTarget() {
        var queue = WorkspaceSwitchRequestQueue()
        #expect(queue.request(.workspace1) == .workspace1)
        #expect(queue.request(.workspace2) == nil)
        let third = WorkspaceID("workspace-3")
        #expect(queue.request(third) == nil)
        #expect(queue.finish() == third)
        #expect(queue.state == .switching(target: third))
        #expect(queue.finish() == nil)
        #expect(queue.state == .idle)
    }

    @Test func shortcutConfigurationHasDeterministicDefaults() {
        let configuration = GlobalShortcutConfiguration()
        #expect(configuration.desktopKeyCodes.count == 9)
        #expect(configuration.nextKeyCode == 124)
        #expect(configuration.previousKeyCode == 123)
        #expect(configuration.enabled)
    }

    @Test func recoveryPlannerUsesVisibleMainDisplayWhenOriginalDisplayDisappears() {
        let snapshot = window(frame: CGRect(x: 2400, y: 100, width: 900, height: 700))
        let displays = [display(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900))]
        let adjusted = snapshot.recoveryAdjusted(to: displays)
        #expect(adjusted.displayID == 1)
        #expect(adjusted.frame.intersects(displays[0].visibleFrame))
        #expect(adjusted.frame != snapshot.frame)
    }

    @Test func emptyTargetDesktopParksOnlyNonStickySourceMembers() {
        var manager = WorkspaceManager()
        let sourceOnly = authorizedMember(window(identifier: "source-empty"))
        let sticky = authorizedMember(window(identifier: "sticky-empty"))
        manager.moveToWorkspace(sourceOnly, workspaceID: .workspace1)
        manager.moveToWorkspace(sticky, workspaceID: .workspace1)
        manager.setVisibleOnAllWorkspaces(sticky, visible: true)
        let engine = WorkspaceSwitchEngine()
        let candidates = engine.membersToPark(from: manager.workspace(for: .workspace1), to: manager.workspace(for: .workspace2))
        #expect(candidates.map(\.id) == [sourceOnly.id])
    }

    @Test func parkingIsAcceptedOnlyWhenActualFrameIsOutsideVisibleDisplays() {
        let displays = [display(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 800))]
        let engine = WorkspaceSwitchEngine()
        #expect(engine.isSafelyParked(CGRect(x: 1100, y: 10, width: 300, height: 200), displays: displays))
        #expect(!engine.isSafelyParked(CGRect(x: 900, y: 10, width: 300, height: 200), displays: displays))
    }
}

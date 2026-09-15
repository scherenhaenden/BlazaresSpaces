import Foundation

struct WorkspaceSwitchExecution: Equatable, Sendable {
    let sourceWorkspace: LogicalWorkspace?
    let targetWorkspace: LogicalWorkspace
    let result: WorkspaceSwitchResult
}

struct WorkspaceSwitchEngine {
    let controller: AXExternalWindowController
    let parkingCalculator: ParkingPositionCalculator

    init(
        controller: AXExternalWindowController = AXExternalWindowController(),
        parkingCalculator: ParkingPositionCalculator = ParkingPositionCalculator()
    ) {
        self.controller = controller
        self.parkingCalculator = parkingCalculator
    }

    func parkInactiveWorkspace(
        _ workspace: LogicalWorkspace,
        displays: [DisplaySnapshot]
    ) -> WorkspaceSwitchExecution {
        let start = Date()
        var updated = workspace
        var results: [WorkspaceWindowResult] = []
        var captureDuration = 0.0
        var parkingDuration = 0.0

        for (index, member) in workspace.members.enumerated() where !member.isParked && !member.visibleOnAllWorkspaces {
            let captureStart = Date()
            let current: WindowSnapshot?
            switch controller.capture(member.authorizedWindow, displays: displays) {
            case let .success(snapshot):
                current = snapshot
                results.append(.init(
                    id: member.id,
                    applicationName: member.authorizedWindow.applicationName,
                    processIdentifier: member.authorizedWindow.processIdentifier,
                    workspaceID: workspace.id,
                    operation: .capture,
                    requestedFrame: nil,
                    actualFrame: snapshot.frame,
                    outcome: .captured,
                    message: "Active geometry captured before parking."
                ))
            case let .failure(error):
                current = nil
                results.append(captureFailure(member: member, workspaceID: workspace.id, error: error))
            }
            captureDuration += Date().timeIntervalSince(captureStart)

            guard let current,
                  let parkingFrame = parkingCalculator.parkingFrame(slot: index, windowSize: current.frame.size, displays: displays) else {
                if current == nil {
                    results.append(.init(
                        id: member.id,
                        applicationName: member.authorizedWindow.applicationName,
                        processIdentifier: member.authorizedWindow.processIdentifier,
                        workspaceID: workspace.id,
                        operation: .park,
                        requestedFrame: nil,
                        actualFrame: nil,
                        outcome: .failed,
                        message: "Window was not parked because its current geometry could not be captured."
                    ))
                }
                continue
            }

            let parkingStart = Date()
            let parking = controller.park(member.authorizedWindow, current: current, at: parkingFrame.origin)
            parkingDuration += Date().timeIntervalSince(parkingStart)
            let mapped = map(parking, member: member, workspaceID: workspace.id, operation: .park)
            results.append(mapped)
            if parking.status == .restoredExactly || parking.status == .restoredWithAdjustment,
               let actualFrame = parking.actualFrame {
                var updatedMember = member
                updatedMember.isParked = true
                updatedMember.parkedFrame = actualFrame
                if let memberIndex = updated.members.firstIndex(where: { $0.id == updatedMember.id }) {
                    updated.members[memberIndex] = updatedMember
                }
            }
        }

        let total = Date().timeIntervalSince(start)
        let metrics = WorkspaceSwitchMetrics(
            captureMilliseconds: captureDuration * 1_000,
            parkingMilliseconds: parkingDuration * 1_000,
            restoreMilliseconds: 0,
            totalMilliseconds: total * 1_000,
            windowsProcessed: workspace.members.count
        )
        return WorkspaceSwitchExecution(
            sourceWorkspace: nil,
            targetWorkspace: updated,
            result: WorkspaceSwitchResult(sourceWorkspaceID: nil, targetWorkspaceID: workspace.id, results: results, metrics: metrics)
        )
    }

    func switchWorkspace(
        from source: LogicalWorkspace,
        to target: LogicalWorkspace,
        displays: [DisplaySnapshot]
    ) -> WorkspaceSwitchExecution {
        let start = Date()
        var updatedSource = source
        var updatedTarget = target
        var results: [WorkspaceWindowResult] = []
        var captureDuration = 0.0
        var parkingDuration = 0.0
        var restoreDuration = 0.0
        var capturedSnapshots: [WindowRuntimeIdentity: WindowSnapshot] = [:]

        let membersToPark = membersToPark(from: source, to: target)

        for member in membersToPark {
            let captureStart = Date()
            switch controller.capture(member.authorizedWindow, displays: displays) {
            case let .success(snapshot):
                capturedSnapshots[member.id] = snapshot
                var updatedMember = member
                updatedMember.logicalSnapshot = snapshot
                if let memberIndex = updatedSource.members.firstIndex(where: { $0.id == updatedMember.id }) {
                    updatedSource.members[memberIndex] = updatedMember
                }
                results.append(.init(
                    id: member.id,
                    applicationName: member.authorizedWindow.applicationName,
                    processIdentifier: member.authorizedWindow.processIdentifier,
                    workspaceID: source.id,
                    operation: .capture,
                    requestedFrame: nil,
                    actualFrame: snapshot.frame,
                    outcome: .captured,
                    message: "Active workspace geometry captured."
                ))
            case let .failure(error):
                results.append(captureFailure(member: member, workspaceID: source.id, error: error))
            }
            captureDuration += Date().timeIntervalSince(captureStart)
        }

        for (index, member) in membersToPark.enumerated() {
            guard let current = capturedSnapshots[member.id] else {
                results.append(.init(
                    id: member.id,
                    applicationName: member.authorizedWindow.applicationName,
                    processIdentifier: member.authorizedWindow.processIdentifier,
                    workspaceID: source.id,
                    operation: .park,
                    requestedFrame: nil,
                    actualFrame: nil,
                    outcome: .failed,
                    message: "Parking skipped because capture failed."
                ))
                continue
            }
            guard let parkingFrame = parkingCalculator.parkingFrame(slot: index, windowSize: current.frame.size, displays: displays) else {
                results.append(.init(
                    id: member.id,
                    applicationName: member.authorizedWindow.applicationName,
                    processIdentifier: member.authorizedWindow.processIdentifier,
                    workspaceID: source.id,
                    operation: .park,
                    requestedFrame: nil,
                    actualFrame: nil,
                    outcome: .failed,
                    message: "No connected-display topology is available for parking."
                ))
                continue
            }
            let parkingStart = Date()
            let parking = controller.park(member.authorizedWindow, current: current, at: parkingFrame.origin)
            parkingDuration += Date().timeIntervalSince(parkingStart)
            results.append(map(parking, member: member, workspaceID: source.id, operation: .park))
            if parking.status == .restoredExactly || parking.status == .restoredWithAdjustment {
                var updatedMember = updatedSourceMember(updatedSource, id: member.id, workspaceID: source.id) ?? member
                updatedMember.isParked = true
                updatedMember.parkedFrame = parking.actualFrame
                if let memberIndex = updatedSource.members.firstIndex(where: { $0.id == updatedMember.id }) {
                    updatedSource.members[memberIndex] = updatedMember
                }
            }
        }

        let membersToRestore = membersToRestore(from: source, to: target)
        for member in membersToRestore {
            let restoreStart = Date()
            let restore = controller.restore(member.authorizedWindow, requested: member.logicalSnapshot)
            restoreDuration += Date().timeIntervalSince(restoreStart)
            results.append(map(restore, member: member, workspaceID: target.id, operation: .restore))
            if restore.status == .restoredExactly || restore.status == .restoredWithAdjustment {
                var updatedMember = member
                updatedMember.isParked = false
                updatedMember.parkedFrame = nil
                if let memberIndex = updatedTarget.members.firstIndex(where: { $0.id == updatedMember.id }) {
                    updatedTarget.members[memberIndex] = updatedMember
                }
            }
        }

        let total = Date().timeIntervalSince(start)
        let metrics = WorkspaceSwitchMetrics(
            captureMilliseconds: captureDuration * 1_000,
            parkingMilliseconds: parkingDuration * 1_000,
            restoreMilliseconds: restoreDuration * 1_000,
            totalMilliseconds: total * 1_000,
            windowsProcessed: source.members.count + target.members.count
        )
        return WorkspaceSwitchExecution(
            sourceWorkspace: updatedSource,
            targetWorkspace: updatedTarget,
            result: WorkspaceSwitchResult(sourceWorkspaceID: source.id, targetWorkspaceID: target.id, results: results, metrics: metrics)
        )
    }

    private func updatedSourceMember(_ manager: LogicalWorkspace, id: WindowRuntimeIdentity, workspaceID: WorkspaceID) -> WorkspaceMember? {
        manager.members.first(where: { $0.id == id })
    }

    private func captureFailure(member: WorkspaceMember, workspaceID: WorkspaceID, error: ExternalWindowOperationError) -> WorkspaceWindowResult {
        .init(
            id: member.id,
            applicationName: member.authorizedWindow.applicationName,
            processIdentifier: member.authorizedWindow.processIdentifier,
            workspaceID: workspaceID,
            operation: .capture,
            requestedFrame: member.logicalSnapshot.frame,
            actualFrame: nil,
            outcome: map(error),
            message: error.localizedDescription
        )
    }

    func map(_ result: WindowRestoreResult, member: WorkspaceMember, workspaceID: WorkspaceID, operation: WorkspaceWindowOperation) -> WorkspaceWindowResult {
        let outcome: WorkspaceWindowOutcome
        switch result.status {
        case .restoredExactly: outcome = operation == .park ? .parked : .restoredExactly
        case .restoredWithAdjustment: outcome = .adjusted
        case .windowMissing: outcome = .missing
        case .windowChanged: outcome = .changed
        case .excluded: outcome = .excluded
        case .unsupported: outcome = .unsupported
        case .permissionDenied: outcome = .permissionDenied
        case .failed: outcome = .failed
        }
        return WorkspaceWindowResult(
            id: member.id,
            applicationName: member.authorizedWindow.applicationName,
            processIdentifier: member.authorizedWindow.processIdentifier,
            workspaceID: workspaceID,
            operation: operation,
            requestedFrame: result.requestedFrame,
            actualFrame: result.actualFrame,
            outcome: outcome,
            message: result.message
        )
    }

    /// Pure transition policy, kept separate so it can be tested without AX.
    func membersToPark(from source: LogicalWorkspace, to target: LogicalWorkspace) -> [WorkspaceMember] {
        let targetIDs = Set(target.members.map(\.id))
        return source.members.filter {
            !$0.isParked && !$0.visibleOnAllWorkspaces && !targetIDs.contains($0.id)
        }
    }

    func membersToRestore(from source: LogicalWorkspace, to target: LogicalWorkspace) -> [WorkspaceMember] {
        let sourceIDs = Set(source.members.map(\.id))
        return target.members.filter {
            !$0.visibleOnAllWorkspaces && (!sourceIDs.contains($0.id) || $0.isParked)
        }
    }

    private func map(_ error: ExternalWindowOperationError) -> WorkspaceWindowOutcome {
        switch error {
        case .windowMissing: return .missing
        case .windowChanged: return .changed
        case .unsupported: return .unsupported
        case .permissionDenied: return .permissionDenied
        case .axFailure: return .failed
        }
    }
}

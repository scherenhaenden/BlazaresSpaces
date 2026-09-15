import Foundation
import CoreGraphics

/// A read-only capture of the complete current desktop context. This is not yet
/// a logical workspace and has no activation, hiding, or restoration behavior.
struct WorkspaceSnapshot: Equatable, Sendable {
    let capturedAt: Date
    let displays: [DisplaySnapshot]
    let windows: [WindowSnapshot]

    var representedDisplayIDs: Set<CGDirectDisplayID> {
        Set(windows.compactMap(\.displayID))
    }
}

struct WorkspaceSnapshotStore: Equatable, Sendable {
    private(set) var current: WorkspaceSnapshot?

    mutating func replace(with snapshot: WorkspaceSnapshot) {
        current = snapshot
    }
}

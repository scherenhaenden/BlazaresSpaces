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
}

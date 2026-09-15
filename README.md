# BlazaresSpaces

KDE-style global virtual desktops for macOS.

BlazaresSpaces is an experimental, open-source macOS virtual desktop manager focused on multi-monitor context switching. One workspace spans all connected displays.

```text
Desktop 1
+-------------+-------------+-------------+
| Display 1   | Display 2   | Display 3   |
| Work        | Work        | Work        |
+-------------+-------------+-------------+

                    SWITCH

Desktop 2
+-------------+-------------+-------------+
| Display 1   | Display 2   | Display 3   |
| Development | Development | Development |
+-------------+-------------+-------------+
```

BlazaresSpaces does not tile windows, create or manipulate native macOS Spaces, use private Mission Control/WindowServer APIs, or require disabling SIP. It is currently a proof of concept using public AppKit, CoreGraphics, and Accessibility APIs.

## Current status — 0.0.1 Window & Display Inspector

The app can:

- report Accessibility authorization and request access;
- enumerate connected displays with IDs, global frames, visible frames, and scale factors;
- read normal application windows exposed through Accessibility;
- show application metadata, window geometry/state, and the display with the largest overlap;
- report discovery failures without terminating or mutating other applications.

The inspector remains read-only for every external application. This iteration also includes an explicitly opened **Window Control Lab**: a dedicated BlazaresSpaces-owned window with Capture, Move, Resize, and Restore controls. Those controls are hard-scoped to that test window and never target unselected applications.

The inspector can also capture an in-memory, read-only snapshot of all currently discovered external windows. Snapshots are diagnostic only: they are not persisted and cannot restore or switch workspaces yet.

Window titles are hidden by default in the inspector and can be revealed explicitly for local debugging because they may contain sensitive work information.

The external test mode is opt-in per window. A discovered window is never mutable by default. The user must explicitly select one eligible window or a temporary test set. Conservative application exclusions are marked **NEVER MANAGE** by the default policy. External restore requires a usable AX runtime identifier, rechecks the exact PID/bundle/identifier, and reports the requested versus resulting frame.

## Running

1. Open `BlazaresSpaces.xcodeproj` in Xcode and run the `BlazaresSpaces` scheme.
2. Click **Request Access**.
3. Enable BlazaresSpaces in **System Settings → Privacy & Security → Accessibility**. If macOS lists an older build, remove it and request access again.
4. Return to the app and click **Refresh**.

Accessibility permission is tied to the built app's signing identity and location. Rebuilding or changing signing may require granting it again. Some apps expose incomplete attributes, protected windows, or no AX windows at all. Window titles are shown in the local diagnostics UI but deliberately omitted from logs because they may be sensitive.

## Directional milestones

- **0.0.1:** Window and display inspector
- **0.0.2:** Capture/restore layouts
- **0.0.3:** Two global logical workspaces
- **0.1.0:** Usable workspace-switching MVP
- **0.2.0:** Persistence and robust display topology handling
- **0.3.0:** Application/window rules and exclusions
- **0.4.0:** Menu bar UX and configuration
- **0.5.0:** Transition framework
- **0.6.0:** Optional Desktop Cube-style transition
- **1.0.0:** Stable global desktop manager

These milestones are direction, not promises. See [the vision](docs/vision.md) and [architecture notes](docs/architecture.md).

## Safe 0.0.2 verification

After granting Accessibility access, click **Window Control Lab**. Use **Capture Frame**, move or resize the lab manually, then use **Restore Captured Frame**. The explicit **Move Test Window** and **Resize Test Window** actions are limited to this window. Drag it between monitors and repeat the experiment; external applications must never move.

Click **Capture Desktop Snapshot** in the inspector to record the current external desktop state in memory. It only reads AX attributes and reports the number of windows and represented displays.

For an external restore experiment, select a safe disposable window with **Use as Capture/Restore Test Window**, click **Capture Selected Window**, manually move or resize that window, then click **Restore Selected Window**. The UI reports exact, adjusted, missing, excluded, unsupported, permission-denied, and failed outcomes. There is no automatic external move action.

### Manual verification checklist

- **A — Accessibility:** Confirm Granted/Not Granted and that Refresh never changes other windows.
- **B — Displays:** Confirm all physical displays, IDs, frames, visible frames, scale, and negative coordinates.
- **C — Inspector:** Confirm expected applications and geometry without any visible changes.
- **D — Control Lab:** Capture, move, resize, and restore only the BlazaresSpaces lab window.
- **E — Multi-display restore:** Manually drag the lab to another display, capture, move it, and restore it.
- **F — Full snapshot:** Capture Desktop Snapshot and confirm approximate window/display counts; verify nothing external changed.

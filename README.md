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

## Current status — 0.2.0 in development

The 0.1.0 daily-driver global workspace MVP is the current functional baseline. The active 0.2.0 milestone is modularizing that baseline and adding versioned persistence plus conservative session restoration. The architectural rules and the exact distinction between current and pending behavior are documented in [ARCHITECTURE.md](docs/ARCHITECTURE.md).

The target 0.2.0 design keeps runtime AX identity separate from durable window identity. Workspace configuration, many-to-many window membership, sticky semantics, and logical geometry will use an explicit versioned model. Relaunch discovery and matching remain read-only: an ambiguous candidate is never guessed, and no external window moves merely because BlazaresSpaces launched or loaded saved state.

The repository now contains the initial pure durable-window models, versioned JSON persistence, deterministic matching, conservative topology mapping, and switch planning for 0.2.0. They are not yet fully wired into the application lifecycle. The app UI therefore does not yet provide durable window membership, matching review, corrupted-state recovery, or crash recovery. Those behaviors become available only after integration and automated/manual validation; this README does not treat the architecture contract as shipped functionality.

### 0.1.0 functional baseline

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

The 0.0.3 experiment adds a controller for logical workspaces spanning all connected displays. Runtime window memberships are held in memory only. A selected window can be moved to one workspace, added to several workspaces, or marked **Show on all workspaces**; that sticky semantic also applies to workspaces created later. Shared windows remain visible during a switch, while only source-only windows are temporarily parked outside the union of display frames. Logical frames are kept separately from temporary parking frames.

The 0.1.0 controller turns that experiment into a daily-driver MVP: desktops can be added, renamed, reordered, activated, and safely deleted; manageable windows expose explicit Move, Add, sticky, and Stop Managing actions; keyboard shortcuts and a menu-bar controller offer fast activation; and switching requests are serialized with latest-target semantics. Desktop names, order, active desktop, and shortcut configuration may be persisted, but runtime AX identities and window memberships are never persisted across restarts.

Workspace switching is deliberately opt-in and reversible: enable desktop switching, switch from the desktop manager, menu bar, or configured shortcuts, and use **RECOVER MANAGED WINDOWS** or **Exit & Recover** to restore selected windows. Partial failures, missing windows, unsupported minimized/fullscreen states, adjusted frames, topology changes, and timing metrics are reported per window. New or unselected windows remain unmanaged. There is no automatic adoption, native macOS Spaces integration, tiling, persistence of runtime identities, or crash recovery.

## Running

1. Open `BlazaresSpaces.xcodeproj` in Xcode and run the `BlazaresSpaces` scheme.
2. Click **Request Access**.
3. Enable BlazaresSpaces in **System Settings → Privacy & Security → Accessibility**. If macOS lists an older build, remove it and request access again.
4. Return to the app and click **Refresh**.

Accessibility permission is tied to the built app's signing identity and location. Rebuilding or changing signing may require granting it again. Some apps expose incomplete attributes, protected windows, or no AX windows at all. Window titles are shown in the local diagnostics UI but deliberately omitted from logs because they may be sensitive.

## Directional milestones

- **0.0.1:** Window and display inspector
- **0.0.2:** Capture/restore layouts
- **0.0.3:** Dynamic global logical workspaces (initially tested with two)
- **0.1.0:** Daily-driver global workspace MVP
- **0.2.0:** Modular architecture, versioned persistence, and conservative session restoration
- **0.3.0:** Application/window rules and exclusions
- **0.4.0:** Menu bar UX and configuration
- **0.5.0:** Transition framework
- **0.6.0:** Optional Desktop Cube-style transition
- **1.0.0:** Stable global desktop manager

These milestones are direction, not promises. See [the vision](docs/vision.md) and the canonical [architecture document](docs/ARCHITECTURE.md).

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

### 0.1.0 daily-driver verification

1. Create and rename **Work**, **Development**, **University**, and **Personal**; reorder them and verify the active desktop indicator.
2. Explicitly manage disposable windows only. Assign one window to one desktop, another to two desktops, and a third to all desktops.
3. Switch Work → Development → University → Personal using the desktop manager, menu bar, and configured shortcuts. Confirm shared/sticky windows are not moved unnecessarily.
4. Keep real work and excluded applications open but unmanaged; confirm they never move.
5. Rapidly request several desktops and confirm only serialized, deterministic switching occurs.
6. Delete an empty desktop, a shared desktop, and a uniquely-owned desktop; verify explicit replacement is required and no window closes.
7. Stop managing a parked disposable window and confirm it is recovered and remains open.
8. Use **RECOVER MANAGED WINDOWS**, test clean application exit, and confirm no window intentionally remains parked.
9. If safe, disconnect/reconnect a display and revoke/re-enable Accessibility. Confirm switching pauses, state is reported, and recovery remains explicit.
10. Test minimized/fullscreen windows conservatively; confirm they are reported as unsupported rather than unexpectedly unminimized or moved.

### 0.2.0 real-Mac validation after integration

Run this checklist only after the 0.2.0 restoration UI is integrated, using disposable windows and a Mac with Accessibility enabled:

1. Create several desktops.
2. Assign multiple windows.
3. Assign two windows from the same application differently.
4. Assign one window to multiple desktops.
5. Make one managed window sticky.
6. Quit BlazaresSpaces cleanly.
7. Relaunch BlazaresSpaces.
8. Verify workspace configuration returns.
9. Verify launch alone moves no external window.
10. Review the detected restorable windows.
11. Explicitly confirm one safe restoration.
12. Verify ambiguous same-application windows are not guessed.
13. Launch a previously missing application later.
14. Re-run discovery and verify its missing record is reconsidered.
15. Test restoration with three monitors.
16. Change the display topology, if safe.
17. Verify the conservative geometry fallback remains visible and is reported.
18. Verify Citrix remains untouched.
19. Verify unmanaged windows remain untouched.
20. Use **Recover Managed Windows** and inspect all outcomes.
21. Quit while disposable managed windows are parked and verify clean-exit recovery.

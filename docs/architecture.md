# Architecture

## 0.0.1 boundaries

- **Domain diagnostics:** immutable `DisplaySnapshot`, `WindowSnapshot`, and runtime identity values contain no `AXUIElement` references.
- **Display integration:** `DisplayManager` combines public `NSScreen` metadata with `CGDisplayBounds`. Diagnostics and mapping use the same top-left global coordinate system as Accessibility.
- **Accessibility integration:** `AccessibilityPermissionManager` owns trust checks/prompts. `AXWindowDiscovery` reads normal windows from regular running applications and converts fallible attributes into snapshots and visible issues.
- **Application/UI:** `DiagnosticsViewModel` coordinates refreshes on the main actor. SwiftUI only renders state and invokes explicit actions.
- **Window Control Lab:** `AXWindowController` is scoped to the current process and the exact `Window Control Lab` title. `WindowControlLabViewModel` exposes explicit test actions only; it has no workspace, hiding, or external-window behavior.
- **Snapshots:** `WorkspaceSnapshot` and `WorkspaceSnapshotStore` hold an in-memory read-only capture. `DiagnosticsViewModel.captureAllWindows()` re-discovers external windows and never writes AX attributes.

The app sandbox is disabled because sandboxed processes cannot serve as a desktop-wide Accessibility client. No private entitlement or API is used.

## Identity and coordinates

`WindowRuntimeIdentity` is intentionally runtime-only. PID, enumeration order, titles, and optional AX identifiers are not reliable persistent identities across application restarts. A later persisted window description must be a distinct type and restoration will require explicit matching heuristics.

CoreGraphics/AX global coordinates use a top-left origin and may be negative for displays above or left of the primary display. Display array order is never treated as identity. Window mapping selects the greatest intersection area, falling back to the nearest display for a fully offscreen frame.

## Known platform uncertainty

- Applications decide which AX attributes and windows they expose; minimized, fullscreen, title, and identifiers may be unavailable.
- Protected/system applications can reject inspection even when trust is granted.
- Native Spaces may limit which windows are returned by an application's AX window list.
- Display IDs are useful for a running topology but may change after reconnects; robust persisted topology matching needs more public metadata and testing.
- Mixed scaling does not change AX point coordinates, but physical-pixel assumptions would be incorrect.
- Accessibility trust changes are not delivered as a simple app callback, so the user explicitly refreshes after changing System Settings.

## Safe mutation boundary

The only write path in this iteration is `AXWindowController`, and its process identifier defaults to BlazaresSpaces itself. It resolves exactly one AX window by the fixed lab title before every operation. There is no API that accepts an arbitrary external application or window. Move, resize, and restore are explicit button actions in a separately opened lab window.

Fullscreen and minimized values remain diagnostic fields only. They are not mutated or restored because support is not yet proven.

## Next boundary

The next iteration should validate the lab on real monitor topologies and applications, then add a separate restorable snapshot description. Any future external mutation must remain user initiated, report each failure, and be tested manually before workspace switching is considered.

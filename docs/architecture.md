# Architecture

## 0.0.1 boundaries

- **Domain diagnostics:** immutable `DisplaySnapshot`, `WindowSnapshot`, and runtime identity values contain no `AXUIElement` references.
- **Display integration:** `DisplayManager` combines public `NSScreen` metadata with `CGDisplayBounds`. Diagnostics and mapping use the same top-left global coordinate system as Accessibility.
- **Accessibility integration:** `AccessibilityPermissionManager` owns trust checks/prompts. `AXWindowDiscovery` reads normal windows from regular running applications and converts fallible attributes into snapshots and visible issues.
- **Application/UI:** `DiagnosticsViewModel` coordinates refreshes on the main actor. SwiftUI only renders state and invokes explicit actions.

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

## Next boundary

0.0.2 should add a separate restorable snapshot description and explicit capture/restore actions. Any mutation must be user initiated, exclude BlazaresSpaces itself, report each failure, and be tested manually before workspace switching is considered.

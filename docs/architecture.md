# Architecture

## 0.0.1 boundaries

- **Domain diagnostics:** immutable `DisplaySnapshot`, `WindowSnapshot`, and runtime identity values contain no `AXUIElement` references.
- **Display integration:** `DisplayManager` combines public `NSScreen` metadata with `CGDisplayBounds`. Diagnostics and mapping use the same top-left global coordinate system as Accessibility.
- **Accessibility integration:** `AccessibilityPermissionManager` owns trust checks/prompts. `AXWindowDiscovery` reads normal windows from regular running applications and converts fallible attributes into snapshots and visible issues.
- **Application/UI:** `DiagnosticsViewModel` coordinates refreshes on the main actor. SwiftUI only renders state and invokes explicit actions.
- **Window Control Lab:** `AXWindowController` is scoped to the current process and the exact `Window Control Lab` title. `WindowControlLabViewModel` exposes explicit test actions only; it has no workspace, hiding, or external-window behavior.
- **Snapshots:** `WorkspaceSnapshot` and `WorkspaceSnapshotStore` hold an in-memory read-only capture. `DiagnosticsViewModel.captureAllWindows()` re-discovers external windows and never writes AX attributes.
- **External test authorization:** `WindowManagementPolicy` excludes conservative application defaults. `WindowAuthorization` turns one explicitly selected discovered snapshot into an `AuthorizedExternalWindow`; discovery itself never creates authorization.
- **External mutation:** `AXExternalWindowController` accepts only an authorized token, requires a usable AX runtime identifier, re-locates the exact PID/bundle/AX identifier before every operation, writes size then position, and reads the resulting frame for classification.

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

The internal lab write path is `AXWindowController`, and its process identifier defaults to BlazaresSpaces itself. It resolves exactly one AX window by the fixed lab title before every operation. There is no API that accepts an arbitrary application or window for the lab. Move, resize, and restore are explicit button actions in a separately opened lab window.

External writes are a separate path and require explicit user selection. `AXExternalWindowController` does not accept `[WindowSnapshot]`; each operation receives one `AuthorizedExternalWindow`. It will not fall back to enumeration order, title matching, or another window if the selected runtime identity disappears. Conservative application and bundle exclusions are visible as `NEVER MANAGE` entries.

Restoration uses size-then-position as the current experiment order, then reads the actual frame. A result is classified as exact, adjusted, missing, changed, excluded, unsupported, permission denied, or failed. This is an empirical POC choice, not a universal macOS guarantee.

Fullscreen and minimized values remain diagnostic fields only. They are not mutated or restored because support is not yet proven.

## Next boundary

The next iteration should validate external selection and restoration on real monitor topologies and applications. Any future external mutation must remain user initiated, report each failure, and be tested manually before workspace switching is considered. See [window-deactivation.md](window-deactivation.md) for strategies that remain intentionally unimplemented.

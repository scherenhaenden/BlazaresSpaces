# Architecture

## 0.0.1–0.0.3 boundaries

- **Domain diagnostics:** immutable `DisplaySnapshot`, `WindowSnapshot`, and runtime identity values contain no `AXUIElement` references.
- **Display integration:** `DisplayManager` combines public `NSScreen` metadata with `CGDisplayBounds`. Diagnostics and mapping use the same top-left global coordinate system as Accessibility.
- **Accessibility integration:** `AccessibilityPermissionManager` owns trust checks/prompts. `AXWindowDiscovery` reads normal windows from regular running applications and converts fallible attributes into snapshots and visible issues.
- **Application/UI:** `DiagnosticsViewModel` coordinates refreshes on the main actor. SwiftUI only renders state and invokes explicit actions.
- **Window Control Lab:** `AXWindowController` is scoped to the current process and the exact `Window Control Lab` title. `WindowControlLabViewModel` exposes explicit test actions only; it has no workspace, hiding, or external-window behavior.
- **Snapshots:** `WorkspaceSnapshot` and `WorkspaceSnapshotStore` hold an in-memory read-only capture. `DiagnosticsViewModel.captureAllWindows()` re-discovers external windows and never writes AX attributes.
- **External test authorization:** `WindowManagementPolicy` excludes conservative application defaults. `WindowAuthorization` turns one explicitly selected discovered snapshot into an `AuthorizedExternalWindow`; discovery itself never creates authorization.
- **External mutation:** `AXExternalWindowController` accepts only an authorized token, requires a usable AX runtime identifier, re-locates the exact PID/bundle/AX identifier before every operation, writes size then position, and reads the resulting frame for classification.
- **Logical workspace domain:** `WorkspaceManager` owns a dynamic ordered collection of logical workspaces and an in-memory many-to-many window relationship. `WorkspaceMember.workspaceIDs` supports one or many memberships; `visibleOnAllWorkspaces` is a separate sticky semantic so future workspaces include the window without copying a fixed list forever.
- **Workspace controller:** `WorkspaceSwitchEngine` compares the source and target membership views. A source window is parked only when it is source-only and non-sticky. A shared or sticky window remains visible and keeps its current geometry. Target-only windows restore their saved logical frame. The first implementation uses one global geometry per shared window; workspace-specific geometry remains a later extension.
- **Experimental parking:** `ParkingPositionCalculator` derives deterministic parking slots from the union of connected display frames. `WorkspaceMember.logicalSnapshot` is never replaced by the temporary `parkedFrame`. All operations are in memory, explicit, and reported through `WorkspaceSwitchResult` metrics and per-window outcomes.
- **Daily-driver controller:** `DiagnosticsViewModel` now exposes the desktop manager, explicit Manage/Stop Managing actions, next/previous navigation, menu-bar commands, and configurable public AppKit key monitors. `WorkspaceSwitchRequestQueue` serializes requests with latest-target semantics so rapid commands cannot create overlapping AX pipelines.
- **Configuration boundary:** `WorkspaceConfigurationStore` persists only desktop names/order/active desktop; `GlobalShortcutConfigurationStore` persists shortcut preferences. Runtime AX identities, window membership, frames, and parked state are never persisted across launches.
- **Lifecycle safety:** the controller listens for screen-parameter changes and Accessibility loss, pauses switching when assumptions become unsafe, and attempts recovery of windows parked during the current process on clean termination. Force-kill and crash recovery are intentionally not claimed.

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

## Dynamic workspace safety

Workspace creation, rename, activation, and deletion operate only on logical containers. Deletion requires an explicit destination when an exclusive member would otherwise become orphaned; no window is closed or destroyed. A newly discovered window is never adopted automatically. Assignment is available only after explicit external-window authorization, and the UI distinguishes **Move to workspace**, **Add to workspace**, and **Show on all workspaces**.

Minimized and fullscreen windows are conservatively rejected by the write path. Native macOS Spaces, private WindowServer APIs, tiling, automatic adoption, persistent runtime identities, and crash recovery remain out of scope. Keyboard shortcuts use public AppKit event monitors, require Accessibility before registration, and can be disabled; they never enroll or mutate unmanaged windows.

Switching wraps from the last desktop to the first and from the first to the last for Next/Previous. Desktop order controls shortcut indexes and is persisted as configuration. Deleting an active desktop requires an explicit replacement; deleting a desktop with exclusively assigned windows also requires an explicit destination. The operation changes membership/container state only and never closes windows.

## Next boundary

The next iteration should validate switching and recovery on real monitor topologies and applications, including same-application windows with different runtime identities. Any future external mutation must remain user initiated, report each failure, and be tested manually. See [window-deactivation.md](window-deactivation.md) for the parking tradeoffs and remaining experiments.

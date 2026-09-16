# BlazaresSpaces architecture

## Product vocabulary and native Spaces boundary

The user-facing context managed by BlazaresSpaces is a **Virtual Space**. It
is a logical, application-owned context spanning all connected displays. Native
Mission Control Spaces are an optional infrastructure backend; its boundary,
risks and fallback policy are recorded in [0.4.0-NATIVE-SPACES-ARCHITECTURE.md](0.4.0-NATIVE-SPACES-ARCHITECTURE.md).

Activation is deliberately behind an application boundary. The shipped
`LogicalVirtualSpaceActivationAdapter` routes Virtual Space changes through the
serialized managed-window parking/restoration engine. The experimental native
adapter is capability-gated and independently verified. Private APIs are
isolated in Infrastructure; see ADR 0004.

This document describes the checked-in implementation at the start of the 0.2.0 milestone. Where it states an **0.2.0 integration boundary**, that boundary is required work, not a claim that the behavior is already available.

## 1. Product invariants

- One workspace is one complete window context across all connected displays; workspaces are global.
- A managed window may belong to one or many workspaces.
- A sticky window is visible on every current and future workspace. Sticky is a semantic flag, not a copied list of current workspace IDs.
- Discovery is read-only and does not grant authorization.
- Unmanaged windows remain untouched.
- `NEVER MANAGE` exclusions, including Citrix defaults, apply before mutation.
- Launch, persistence load, or a match result does not by itself authorize a window move.
- Logical geometry and temporary parking geometry are distinct. Parking must never overwrite the desired logical frame.

## 2. High-level architecture

```text
┌──────────────────────────┐
│ UI                       │
│ SwiftUI / menu bar       │
└─────────────┬────────────┘
              │ user intent
┌─────────────▼────────────┐
│ Application coordination │
└─────────────┬────────────┘
              │ domain operations
┌─────────────▼────────────┐
│ Domain                   │
│ workspaces / membership  │
└──────────┬───────┬───────┘
           │       │ ports
   ┌───────▼───┐ ┌─▼────────────┐
   │Persistence│ │ macOS adapters│
   └───────────┘ │ AX/displays   │
                 └───────────────┘
```

Current source includes legacy `Accessibility`, `App`, `Displays`, `Shortcuts`, `Windows`, and `Workspaces` folders plus new pure `Domain` and adapter-oriented `Infrastructure` folders. These are organizational boundaries, not separate Swift modules. `Domain` now contains durable window values and a pure switch planner. `Infrastructure` contains a versioned atomic JSON store, matcher, and topology mapper. `DiagnosticsViewModel` still coordinates the legacy concrete discovery, switching, persistence, recovery, and hotkey objects, and `WorkspaceSwitchEngine` still performs AX execution.

The 0.2.0 integration boundary is to expose UI intent through an application facade, retain pure state and plans in `Domain`, and place concrete AX, display, persistence, and hotkey implementations in `Infrastructure`. Until that migration is complete, the current controller coupling is a known limitation.

## 3. Module responsibilities

| Area | Responsibility | May depend on | Must not depend on |
| --- | --- | --- | --- |
| `Domain` | Workspace identity/order, membership, sticky semantics, durable descriptors, matching and plans | Foundation and value-only frameworks | SwiftUI, AppKit UI, `AXUIElement`, `UserDefaults`, files, concrete adapters |
| `Application` | Execute user intents, coordinate restoration, serialize switching, publish presentation state | Domain and port protocols | SwiftUI views, direct AX calls, concrete persistence |
| `Infrastructure/Accessibility` | Discover, capture, revalidate and mutate runtime AX windows | Domain/Application contracts and public macOS APIs | Workspace membership policy and UI presentation |
| `Infrastructure/Displays` | Snapshot displays and provide geometry mapping inputs | Domain geometry values and public display APIs | Workspace mutation and UI |
| `Infrastructure/Persistence` | Encode/decode a versioned state, migrate and write safely | Domain persistence DTOs and Foundation file APIs | SwiftUI, AX runtime identity, parked state |
| `Infrastructure/Hotkeys` | Translate public keyboard events into application intents | Application command types and AppKit event APIs | Workspace algorithms, AX mutation, cached workspace state |
| `UI` | Render presentation state and send explicit intents | Application facade and SwiftUI | Concrete AX controllers or persistence stores |
| `Recovery` | Pure recovery planning and application-level coordination | Domain and application ports | Implicit authorization or unreviewed fuzzy matching |

Current exceptions are explicit: the legacy `WorkspaceMember` still contains `AuthorizedExternalWindow` and `WindowSnapshot`; `WorkspaceSwitchEngine` depends on `AXExternalWindowController`; and `DiagnosticsViewModel` spans several rows above. The new durable values and pure planner exist, but the application/UI migration is not complete.

## 4. Dependency direction and source of truth

Allowed dependencies are:

```text
UI ──▶ Application ──▶ Domain
          ▲              ▲
          │ protocols    │ values
Infrastructure ──────────┘
```

`WorkspaceApplicationService` is the sole live source of truth shared by the main UI (`ContentView`), menu bar (`MenuBarControllerView`), and shortcut adapter. Persistence is an asynchronous serialized snapshot via `AtomicJSONWorkspaceStateStore`, not an independent live model. Runtime discovery results are ephemeral session state and never replace durable records.

`WorkspaceManager` maintains the canonical durable-window collection (`membersByManagedWindowID`), deriving workspace member views dynamically without drift. Boundaries are formalized with explicit protocols: `WindowDiscovering`, `WindowControlling`, `DisplayTopologyProviding`, `HotkeyRegistering`, and `WorkspaceStatePersisting`.

## 5. Window identity model

`WindowRuntimeIdentity` contains a PID, optional AX identifier, and enumeration index. It is valid only in the current runtime. `AuthorizedExternalWindow` is also session-only. Neither survives an application restart safely.

A durable managed-window ID and descriptor are separate concepts. A descriptor may contain privacy-conscious signals such as bundle identifier, role/subrole, an optional user alias, normalized geometry, approximate dimensions, and display relationship. Raw titles are not persisted by default because they may reveal documents, URLs, customers, or private messages.

```text
durable managed-window ID ── persists ──▶ membership / logical geometry
          │
          └── reviewed session match ──▶ runtime identity + authorization
```

The 0.2.0 durable model defines `ManagedWindowID`, a privacy-safe `PersistedWindowDescriptor`, `LogicalWindowGeometry`, and `PersistedDisplayDescriptor` under `Domain/Windows`. Runtime identities, PIDs, enumeration indexes, AX objects, authorization tokens, raw titles, and parking frames never enter durable state. This durable model is fully integrated into `WorkspaceApplicationService` and persisted authoritatively through `AtomicJSONWorkspaceStateStore`.

## 6. Workspace model

`WorkspaceManager` supports an ordered dynamic collection of `N` workspaces, an active workspace, many-to-many membership, and sticky semantics. Multiple runtime windows from one application remain distinct. Workspace deletion never closes windows and requires an explicit destination when an active workspace or exclusive member needs one.

Each durable window record owns its independent membership set and sticky flag. Sticky remains independent from explicit membership so a newly created workspace includes sticky records automatically.

## 7. Switching pipeline

The checked-in switching pipeline is:

1. Require experimental switching, Accessibility, a valid target, and non-degraded topology.
2. Serialize requests with latest-pending-target semantics.
3. Resolve source and target members.
4. Leave shared and sticky windows visible.
5. Capture each eligible source-only window, then park it outside the display union.
6. Restore target-only or parked target windows to their logical snapshots.
7. Update parked state, activate the target, and publish per-window outcomes and timing.
8. Execute the latest pending target, if present.

The 0.2.0 boundary separates a pure `SwitchPlan` from an AX executor. Only explicitly managed, current-session-authorized bindings may enter an execution plan. Matching and persistence must never execute mutations directly.

## 8. Parking and deactivation

`ParkingPositionCalculator` creates deterministic slots beyond the union of current display frames. Before parking, the current implementation captures geometry. A successful move stores `parkedFrame` and `isParked` separately; it does not replace `logicalSnapshot`.

Capture failure prevents parking. Missing, minimized, fullscreen, excluded, unsupported, or unauthorized windows are reported rather than coerced. Recovery uses logical geometry and may adjust it to a visible display. Parking coordinates and flags are session-only and must never be persisted.

Clean termination currently attempts to recover members known to be parked in the running process. Crash and force-kill recovery cannot rely on the termination callback and are not claimed.

## 9. Persistence, schema, migrations, and failures

`AtomicJSONWorkspaceStateStore` is the sole authoritative persistence engine. Legacy `UserDefaults` stores (`WorkspaceConfigurationStore` and `GlobalShortcutConfigurationStore`) are superseded and only consulted during a one-time migration if no JSON store exists.

Persistence uses an explicit envelope with `schemaVersion: 1` (`PersistedStateEnvelope` and `PersistedStateV1`), containing workspace configuration, shortcut preferences, durable window records, many-to-many membership, sticky flags, logical geometry, and non-sensitive display topology descriptors.

The actor performs serialized atomic writes via temporary files, preserves a `state.last-valid.json` backup before overwriting, and refuses to overwrite corrupted or unsupported state.

Loading returns typed outcomes (`missing`, `loaded`, `corrupted`, `unsupported`, `ioFailure`). Corrupted or unsupported files never cause crashes and never manipulate external windows. The UI offers explicit reset options (`Reset Saved Configuration`), safely quarantining the bad file as `state.reset-backup.json`.

## 10. Restoration and matching

The conservative restoration flow is:

```text
load logical configuration
        ▼
discover runtime windows read-only
        ▼
score candidates per durable descriptor
        ▼
high confidence / probable / ambiguous / missing
        ▼
review + explicit confirmation before physical restoration
```

`WindowMatcher` is implemented as a deterministic, non-mutating component and returns candidates, scores, and reasons. Bundle identity is a gate or strong signal; role/subrole, approximate size, and position refine the current score. Absolute position has low weight and raw titles/AX enumeration order contribute no confidence. User aliases and topology relationship are represented by domain values.

A tie or insufficient score separation is ambiguous and never resolved by discovery order. Missing descriptors remain persisted, do not launch applications, and can be reconsidered when the user retries or a late application appears. Same-application windows are independent; indistinguishable Chrome windows remain ambiguous rather than being collapsed to “Chrome”.

`SessionRestorationCoordinator` and the review UI in `ContentView` are fully integrated. On launch, logical configuration is loaded, runtime windows are discovered read-only, candidates are scored, and restorable candidates are presented to the user for explicit confirmation before physical restoration occurs.

## 11. Safety model

- Discovery and matching are read-only.
- Mutation requires an explicitly managed record, a reviewed runtime binding, current-session authorization, and policy revalidation.
- `NEVER MANAGE` and Citrix exclusions apply during enrollment and immediately before execution.
- Unmanaged windows never enter a mutation plan.
- Fullscreen and minimized windows remain conservative unsupported outcomes until proven.
- Accessibility loss pauses AX operations.
- Topology change pauses switching; compatible topology may use exact geometry, otherwise fallback must be deterministic, normalized/clamped, and reported.
- Corrupted or future-version persistence disables restoration from that state.
- Logs omit raw titles and sensitive content by default.
- Only public macOS APIs are used. The app does not manipulate native Spaces, use private WindowServer/Mission Control APIs, disable SIP, tile, relaunch applications, or restore z-order.

## 12. Concurrency and state machine

`WorkspaceApplicationService` coordinates application operations on `@MainActor`. `WorkspaceSwitchRequestQueue` retains only the latest target while marked active. Topology or Accessibility failures move switching to a degraded state.

`WorkspaceApplicationService` owns transitions among `idle`, `switching`, `recovering`, and `degraded`. Only one switch/restoration/recovery operation may mutate windows at once; saves commit serially to disk. New switch requests coalesce latest-wins. Recovery returns typed outcomes, ensuring degraded state remains active if partial failures occur.

## 13. Test architecture

Pure Swift tests cover workspace rules, many-to-many/sticky behavior, schema dispatch and migration, persistence round trips, corrupted data, matching scores and ambiguity, topology fallback, and switch/recovery planning. Repository tests use temporary directories and injectable file operations.

Application tests use fakes/spies for discovery, control, persistence, and hotkeys. Critical zero-mutation cases are launch, corrupt/future state, ambiguous/missing match, missing authorization, `NEVER MANAGE`, fullscreen/minimized state, and Accessibility/topology loss.

Architecture fitness tests scan executable source under `Domain` and the canonical `UI` folder. While UI files are still being migrated, the test scans every source that imports SwiftUI rather than silently skipping that boundary. Domain cannot import UI/AX frameworks or reference `AXUIElement`/`UserDefaults`; UI cannot reference concrete AX controllers or persistence adapters. The scanner removes comments and string contents before checking symbols.

Physical AX behavior, permission prompts, real global shortcuts, clean-exit recovery, and multi-monitor movement require manual validation on a Mac with Accessibility enabled. UI tests complement but do not replace those experiments.

## 14. Known limitations

- Public AX has no universal durable window identifier.
- Applications expose inconsistent attributes, and native Spaces may restrict discovery.
- Same-app windows may remain ambiguous without an alias or stable metadata.
- Raw titles are intentionally unavailable as a default persistence signal.
- Display IDs may change after reconnect; topology fallback is heuristic.
- The current model has one logical geometry per window, not per workspace, and does not restore z-order.
- AppKit global event monitors cannot consume another application's event, so shortcut conflicts remain possible.
- Crash/force-kill recovery and apps that reject AX writes have no guarantee.
- Hotplugging displays during an active window animation defaults to conservative topology fallback.

## 15. Future extension points

- User-defined aliases and richer privacy-preserving matching metadata.
- Explicit application/window rules and exclusions.
- Per-workspace geometry after the single-geometry model is proven.
- Stronger topology descriptors and user-guided monitor mapping.
- Alternative deactivation strategies behind the control port.
- A transition engine and optional Cube-style visualization after restoration is stable.
- Human-inspectable configuration import/export.

These are not implemented capabilities. Aggressive fuzzy matching, native Spaces/private APIs, automatic relaunch, tiling, cloud sync, telemetry, and z-order reconstruction remain outside 0.2.0.

## Decision records

- [ADR 0001: Runtime and persistent window identity are separate](adr/0001-runtime-vs-persistent-window-identity.md)
- [ADR 0002: Ambiguous matches are never guessed](adr/0002-ambiguity-no-guessing.md)
- [ADR 0003: Membership is many-to-many and sticky is semantic](adr/0003-many-to-many-sticky.md)
- [Window deactivation notes](window-deactivation.md)

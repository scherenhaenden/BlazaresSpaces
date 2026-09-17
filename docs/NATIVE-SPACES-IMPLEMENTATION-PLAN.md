# Native Spaces Implementation Plan

## Goal

BlazaresSpaces must make a Virtual Space correspond to real macOS Mission
Control Native Spaces. Creating a Virtual Space must create its Native Space
bindings, and `Activate`, `Previous`, and `Next` must visibly change macOS and
verify the destination afterwards.

The initial target configuration is **Displays have separate Spaces enabled**.
Each Virtual Space is therefore a group with one Native Space per display.

## Binding model

| Virtual Space | Display A | Display B | Display C |
| --- | --- | --- | --- |
| Work | Native Space A1 | Native Space B1 | Native Space C1 |
| Development | Native Space A2 | Native Space B2 | Native Space C2 |
| University | Native Space A3 | Missing | Native Space C3 |

Each binding stores the display identifier, runtime native Space ID, observed
position, Space kind, and verification state. Runtime IDs are session data;
the virtual name and verified bindings are the durable product model.

A group can be complete, partial, missing, or stale. Display reconnects,
manual Mission Control changes, native Space removal, and topology changes
must trigger reconciliation instead of silently changing a Virtual Space's
meaning.

## Current failure analysis

The existing `Control-Left` / `Control-Right` backend is not sufficient:

- It blocks the main actor while it waits for a notification.
- It chooses the first current Space even though several displays have a
  current Space when separate Spaces are enabled.
- It can report success before a physical transition has been verified.
- Repeated arrow events are not verified one by one.
- Full-screen and non-user Spaces make positional arrow arithmetic ambiguous.
- The experimental toggle only changes a setting; it does not itself switch a
  Space.

`kAXErrorCannotComplete` (`-25204`) from an application such as Numbers is a
separate discovery problem. It must not block the UI or prevent a native Space
operation.

## Chosen path: Mission Control Accessibility

Use the Dock's Mission Control Accessibility hierarchy. The adapter opens
Mission Control, waits for its AX elements, locates a Desktop thumbnail or add
button, performs the AX action, and verifies the result by reading topology
again.

Mission Control will be visibly shown during these operations. Hammerspoon
documents this same practical approach: its Space creation, removal, and
activation functions use Dock Accessibility controls and require waiting for
Mission Control's elements to appear.

Keyboard synthesis remains a diagnostic fallback only. Product activation must
be based on a verified destination control.

## Components

| Component | Responsibility |
| --- | --- |
| `NativeSpacesProviding` | Read displays, native Spaces, types, and active IDs. |
| `MissionControlAXAdapter` | Open/close Mission Control and invoke Native Space, add, and remove controls. |
| `NativeSpaceOperationCoordinator` | Serialize native operations, manage timeouts, verify results, and publish progress. |
| `NativeSpaceBindingStore` | Reconcile Virtual Spaces with native bindings and retain partial work. |
| Inspector | Display topology, bindings, actions, failures, and recovery paths. |

Slow AX work must execute outside the UI actor. No synchronous semaphore wait
or retry loop may run on the main actor.

## Phase 1: inspect Mission Control

Before mutating Spaces:

1. Open Mission Control.
2. Wait asynchronously for the Dock AX hierarchy.
3. Capture display containers, Desktop thumbnails, add buttons, remove buttons,
   AX identifiers, actions, frames, and parent relationships.
4. Close Mission Control.
5. Correlate controls with the native topology.

Prefer AX identifiers and structural attributes to localized labels such as
“Desktop” or “Schreibtisch”. Do not assume the first display container is the
focused display.

Exit criterion: identify a known Desktop and the add button on every display
without mutation.

## Phase 2: activate an existing Desktop

For a requested Virtual Space and display:

1. Read fresh topology and resolve the binding.
2. Open Mission Control and wait for the target AX thumbnail.
3. Perform its activation action.
4. Observe `activeSpaceDidChangeNotification`.
5. Re-read topology until the target runtime ID is current or the operation
   times out.
6. Record the per-display result.

The UI marks a Virtual Space active only after verified success. A failure
keeps the previous active state and reports the failed step.

## Phase 3: activate a multi-display group

With separate Spaces enabled, activate one verified target per display. This
is sequential and can partially succeed.

| Result | UI state |
| --- | --- |
| Every target verified | Virtual Space active |
| Some targets verified | Partially active; identify the affected displays |
| No target verified | Keep the previous active Virtual Space |
| Target missing | Mark binding missing and offer reconciliation |

`Previous` and `Next` call this same coordinator. They select a target group;
they must not calculate a number of arrow-key presses.

## Phase 4: create native Desktops

Adding a Virtual Space becomes a native operation. For each participating
display:

1. Capture topology before creation.
2. Open Mission Control.
3. Locate and press that display's add Desktop button.
4. Re-read topology.
5. Identify the new ordinary Desktop by comparing the before/after topology.
6. Verify its display and store a pending binding.

After every display succeeds, store a complete Virtual Space binding. If a
display fails, retain successful bindings and mark the group partial. Offer
“Complete missing Desktops” so retries do not create duplicates.

Native creation must report complete success, partial success, or failure. It
must not create a logical-only Virtual Space when native creation was requested.

## Responsiveness and diagnostics

Window discovery runs per application outside the UI actor, with bounded retry
and timeout handling. A transient AX `-25204` records an application-level
diagnostic but cannot prevent native Space operations.

The inspector must provide a copyable operation log with:

- requested action and Virtual Space;
- timestamps and duration;
- source and target runtime IDs per display;
- Mission Control AX elements found;
- AX action result;
- topology before and after;
- notification receipt;
- timeout, failure, or partial-success reason.

## Later structural operations

Deletion and reordering follow creation and activation verification.

Deletion counts ordinary native Desktops per display and refuses to remove the
last one. Reordering must use captured Mission Control AX controls and only
update logical order after native order is read back and confirmed.

Window-to-native-Space movement is outside this milestone.

## Acceptance tests

| Test | Expected result |
| --- | --- |
| Activate one existing Desktop | Visible transition and verified runtime ID |
| Activate a three-display group | All requested targets verified |
| Add a Virtual Space | One native Desktop per display and verified bindings |
| One display creation fails | Partial record retained; retry fills only the missing display |
| Numbers returns AX `-25204` | UI remains responsive and native operations continue |
| Rapid clicks | One operation at a time; no duplicate Desktops |
| Manual Mission Control change | Bindings and active state refresh correctly |
| Full-screen Space or display disconnect | Explicit missing/stale/unsupported state; no guessed mapping |

The milestone is complete only when a real Mac proves both flows:

1. Creating a Virtual Space creates visible native Desktops in Mission Control.
2. Activating it visibly changes macOS and verifies the resulting topology.

## Sources

- [Apple: Work in multiple spaces](https://support.apple.com/en-za/guide/mac-help/mh14112/mac)
- [Hammerspoon `hs.spaces`](https://www.hammerspoon.org/docs/hs.spaces.html)
- [CGEventPost](https://developer.apple.com/documentation/coregraphics/cgevent/post%28tap%3A%29?language=objc)

# Window deactivation research notes

This document records candidate strategies for the logical-workspace engine. In 0.1.0, moving explicitly authorized source-only windows outside the visible union of displays is implemented as an opt-in, recoverable parking path. It remains subject to the failure modes below.

The future model must be window-based, not application-based. For example, Chrome Window A may belong to WORK while Chrome Window B belongs to DEV; hiding Chrome as an application would incorrectly affect both.

| Strategy | Benefits | Risks / open questions | Same-application windows | Reversibility / performance |
| --- | --- | --- | --- | --- |
| Move windows outside visible display bounds | Uses public AX position writes; does not require native Spaces; can preserve geometry in a snapshot | Some applications clamp or reposition windows; offscreen windows may remain in Mission Control; dialogs and child windows may escape; focus behavior is uncertain | Potentially workable per window, but child windows and app-level focus need testing | Position can be restored if the exact runtime window survives; likely cheap, but every write can fail |
| Minimize windows | Public AX state in many applications; visually removes a window | Minimized state may be unsupported; apps may change behavior; Dock and user expectations are affected; restore/focus semantics vary | Window-level in theory, but applications may apply policy to all windows | Reversible only where AX exposes reliable state; likely cheap but semantically disruptive |
| Hide the owning application | Simple for applications whose windows all belong to one workspace | Hides unrelated windows from another workspace; changes Dock state, focus, activation, and user interaction; not safe for mixed membership | Not acceptable as a general strategy because one app can have windows in multiple workspaces | Reversible at app level but wrong granularity; potentially fast |
| Use app-specific visibility rules | Can handle known applications with custom behavior | Fragile, unbounded maintenance, and unsafe as a default; remote-desktop behavior is especially sensitive | Could be tailored per window only with substantial testing | Reversibility varies; performance and correctness are application-dependent |
| Native macOS Spaces / private WindowServer APIs | Would align with Mission Control concepts | Explicitly prohibited for this project; private APIs, SIP concerns, and OS-version fragility | Not applicable | Not permitted |

## Current conclusion

Moving an explicitly selected window outside the topology-derived union of display frames is the current public-API experiment. The engine preserves the logical frame separately, verifies the actual parking frame, and reports adjusted, missing, changed, unsupported, permission-denied, and failed outcomes. It must still be tested with normal windows, dialogs, minimized/fullscreen windows, mixed monitor topologies, focus, Mission Control, and applications with multiple windows before this can become a general-purpose switching feature.

The switching rule is membership-aware: a window is parked only when it belongs to the source workspace, does not belong to the target workspace, and is not sticky. Shared windows keep their current geometry while moving between workspaces where they are visible. The first implementation intentionally uses one global geometry for shared windows rather than inventing per-workspace frames.

Minimization is a fallback experiment, not an assumption. Application hiding is unsuitable as the default because workspace membership is per-window. Native Spaces and private APIs remain out of scope.

## Required future experiments

1. Use a dedicated controlled set, never an automatically discovered set.
2. Record requested and actual frame/state after every operation.
3. Test a single application with two windows assigned to different future workspaces.
4. Test dialogs and child windows.
5. Test focus, Dock, Mission Control, and monitor reconnect behavior.
6. Keep excluded and remote-desktop applications out of mutation experiments.
7. Exercise dynamic workspace creation, rename, deletion with explicit orphan handling, and sticky membership on a newly created workspace.

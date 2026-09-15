# BlazaresSpaces

**KDE-style global virtual desktops for macOS.**

BlazaresSpaces is an experimental open-source macOS workspace manager built around one simple idea:

> **One workspace spans all connected displays.**

If you use several monitors, switching context should switch the *entire desk* — not one display at a time.

BlazaresSpaces is being designed for people who keep multiple parallel contexts open during the day: work, development, study, personal projects, research, or anything else that benefits from a clean mental boundary.

---

## The problem

macOS Spaces are useful, but their multi-monitor model does not always match the way KDE/Linux users think about virtual desktops.

BlazaresSpaces uses a different mental model:

```text
Workspace 1 — WORK

┌──────────────────┬──────────────────┬──────────────────┐
│    Display 1     │    Display 2     │    Display 3     │
│                  │                  │                  │
│      Citrix      │      Citrix      │  Outlook / Teams │
│                  │                  │                  │
└──────────────────┴──────────────────┴──────────────────┘

                         ⇅ SWITCH

Workspace 2 — DEVELOPMENT

┌──────────────────┬──────────────────┬──────────────────┐
│    Display 1     │    Display 2     │    Display 3     │
│                  │                  │                  │
│       IDE        │ ChatGPT / Browser│     Terminal     │
│                  │                  │                  │
└──────────────────┴──────────────────┴──────────────────┘
```

The user decides where every window goes. BlazaresSpaces should remember that complete arrangement and eventually restore it as one global workspace.

The key invariant is:

```text
ONE WORKSPACE = THE COMPLETE WINDOW STATE ACROSS ALL DISPLAYS
```

Workspaces are therefore **global**, not assigned independently to individual monitors.

---

## What BlazaresSpaces is not

BlazaresSpaces is **not another tiling window manager**.

It is intentionally not trying to become AeroSpace, i3, yabai, Amethyst, or a layout engine. It does not want to decide where your windows belong.

The project is focused on **context switching**, not automatic window arrangement.

For the initial versions this also means:

- no tiling;
- no i3-style window trees;
- no automatic layouts;
- no per-monitor workspaces;
- no replacement of Mission Control;
- no manipulation of native macOS Spaces;
- no SIP modifications;
- no private Mission Control or WindowServer APIs;
- no cloud synchronization or telemetry.

The long-term goal is to stay as close as practical to public macOS APIs.

---

## Current status

### `0.0.2` — Safe Capture / Restore

The project has moved beyond the read-only inspector foundation and now includes explicit, safety-scoped capture and restoration experiments for external windows.

Implemented so far:

- Accessibility authorization detection and permission request;
- connected-display discovery;
- global display frames, visible frames, and scale/backing information;
- Accessibility-based application-window discovery;
- application metadata, runtime window identity, geometry, and state inspection;
- window-to-display mapping using largest display overlap;
- diagnostics that tolerate inaccessible or disappearing windows;
- a BlazaresSpaces-owned **Window Control Lab** for safe move/resize/restore experiments;
- explicit authorization of external test windows;
- conservative `NEVER MANAGE` exclusions;
- single-window capture and explicit restore;
- selected multi-window capture and restore with per-window failure isolation;
- requested-versus-actual frame verification;
- read-only in-memory global desktop snapshots;
- hidden window titles by default to reduce exposure of sensitive information.

Discovery remains read-only by default. Finding a window does **not** grant permission to mutate it. External restore requires explicit user selection, a usable AX runtime identity, and a re-check of the exact runtime window before mutation.

`0.0.2` is code-complete but still requires physical validation on real multi-monitor macOS hardware before it should be treated as fully verified.

---

## Versioning

BlazaresSpaces uses milestone-oriented pre-1.0 versions. Each version is intended to represent a concrete increase in capability rather than an arbitrary build number.

The current development milestone is **`0.0.2`**. Until a milestone has been implemented and manually verified on real macOS hardware, it should be treated as development work rather than a completed stable release.

The version progression is intentionally conservative:

```text
0.0.x  → prove the low-level macOS/window-management foundation
0.1.x  → first genuinely usable global-workspace MVP
0.2.x+ → robustness, persistence, rules and UX
1.0.0  → stable global desktop manager suitable for regular use
```

Once milestones become releasable, Git tags and GitHub Releases should use the same version numbers so that the README, source tree and published builds remain aligned.

---

## Safety-first development

BlazaresSpaces is being developed and tested on a machine that is also used for real work.

That has shaped the development strategy from the beginning:

```text
OBSERVE
   ↓
CAPTURE
   ↓
CONTROL A SAFE TEST WINDOW
   ↓
RESTORE
   ↓
ONLY THEN MANAGE REAL WORKSPACES
```

The inspector and Refresh remain read-only. External mutation is opt-in per window and happens only after explicit selection. Conservative exclusions remain visible as `NEVER MANAGE`, and there is no fallback to a merely similar window if the selected runtime identity disappears.

---

## Planned architecture

BlazaresSpaces is a native macOS application written in Swift.

The current direction is:

```text
Swift / SwiftUI / AppKit
        │
        ├── Accessibility
        │     AXUIElement inspection and controlled mutation
        │
        ├── Displays
        │     CoreGraphics + NSScreen topology
        │
        ├── Windows
        │     identity, authorization, geometry, snapshots, restoration
        │
        ├── Workspaces
        │     global multi-display logical contexts
        │
        └── UI / Diagnostics
              inspection, safe testing and configuration
```

The domain model is deliberately kept separate from macOS-specific Accessibility objects so that workspace logic can be tested without physically moving real windows.

See [`docs/architecture.md`](docs/architecture.md) for architecture notes, [`docs/vision.md`](docs/vision.md) for the product vision, and [`docs/window-deactivation.md`](docs/window-deactivation.md) for the current analysis of future inactive-workspace window strategies.

---

## Why not native macOS Spaces?

The first versions deliberately avoid building on top of native Spaces.

BlazaresSpaces instead explores **application-managed logical workspaces** using public APIs such as:

- Accessibility / `AXUIElement`;
- AppKit;
- CoreGraphics;
- `NSScreen`;
- `NSWorkspace`.

This keeps the project independent from private Mission Control internals and avoids requiring SIP changes.

The exact strategy for deactivating windows that belong to an inactive logical workspace remains experimental and will only be chosen after controlled testing.

---

## Roadmap

| Version | Goal |
|---|---|
| `0.0.1` | Window & display inspector |
| `0.0.2` | Safe capture / restore of layouts |
| `0.0.3` | Global logical workspaces |
| `0.1.0` | Usable workspace-switching MVP |
| `0.2.0` | Persistence and robust display-topology handling |
| `0.3.0` | Application/window rules and exclusions |
| `0.4.0` | Menu-bar UX and configuration |
| `0.5.0` | Transition framework |
| `0.6.0` | Optional Desktop Cube-style transition |
| `1.0.0` | Stable global desktop manager |

These are directional milestones, not release promises.

The optional Cube is intentionally late in the roadmap. First the underlying global workspace model has to be reliable. Visual transitions can then be layered on top without turning the project into a compositor replacement.

---

## Running the current build

Requirements:

- macOS;
- Xcode with macOS platform support;
- Accessibility permission for BlazaresSpaces.

Then:

1. Open `BlazaresSpaces.xcodeproj` in Xcode.
2. Run the `BlazaresSpaces` scheme.
3. Click **Request Access** if Accessibility permission has not yet been granted.
4. Open **System Settings → Privacy & Security → Accessibility** and enable BlazaresSpaces.
5. Return to the app and click **Refresh**.

Accessibility authorization is tied to the built application's identity/location. Rebuilding or changing signing may require granting permission again.

Some applications expose incomplete Accessibility information, protected windows, unusual child windows, or no manageable windows at all. Those cases are part of what the current inspector exists to discover.

Window titles may contain sensitive information. They are hidden by default and are not intended to be persisted or logged verbosely.

---

## Safe `0.0.2` verification

After granting Accessibility access, click **Window Control Lab**. Use **Capture Frame**, move or resize the lab manually, then use **Restore Captured Frame**. The explicit **Move Test Window** and **Resize Test Window** actions are limited to this BlazaresSpaces-owned test window.

Click **Capture Desktop Snapshot** in the inspector to record the current external desktop state in memory. This operation only reads AX attributes and reports the number of windows and represented displays.

For an external restore experiment, explicitly select a safe disposable window with **Use as Capture/Restore Test Window**, click **Capture Selected Window**, manually move or resize that window, then click **Restore Selected Window**. The UI reports exact, adjusted, missing, excluded, unsupported, permission-denied, and failed outcomes. There is no automatic external move action.

A temporary set of explicitly selected safe windows can also be captured and restored together. Restoration proceeds per window so one failure does not prevent unrelated selected windows from being processed.

### Manual verification checklist

- **A — Accessibility:** Confirm Granted/Not Granted and that Refresh never changes other windows.
- **B — Displays:** Confirm all physical displays, IDs, frames, visible frames, scale, and negative coordinates.
- **C — Inspector:** Confirm expected applications and geometry without any visible changes.
- **D — Control Lab:** Capture, move, resize, and restore only the BlazaresSpaces lab window.
- **E — Single external restore:** Explicitly select one safe disposable external window, capture it, move/resize it manually, restore it, and verify requested vs actual frame.
- **F — Multi-display external restore:** Capture a selected test window on one display, manually move it to another, restore it, and verify it returns correctly.
- **G — Exclusions:** Confirm `NEVER MANAGE` applications cannot be selected for mutation.
- **H — Selected-set restore:** Capture several explicitly selected safe windows, rearrange them manually, restore the set, and inspect individual outcomes.
- **I — Partial failure:** Close one selected window before restore and confirm the remaining selected windows are still processed.
- **J — Full snapshot:** Capture the global read-only desktop snapshot and confirm no unselected external window changes.

---

## Design principle

The most important design rule in the project is deliberately boring:

> **BlazaresSpaces should remember the user's layout, not invent one.**

If a user puts eleven windows across three monitors exactly where they want them, the job of BlazaresSpaces is to preserve that context and bring it back reliably.

That is the product.

---

## Project maturity

BlazaresSpaces is currently a proof of concept and **not yet a daily-driver workspace manager**.

The project is public early on purpose: the difficult part is not drawing a UI, but discovering which combinations of macOS Accessibility behavior, multi-display coordinate systems, application quirks and restoration strategies are robust enough to support a real global desktop model.

Expect experiments, diagnostics and architecture changes before `0.1.0`.

---

## License

Open source. See the repository license for details.

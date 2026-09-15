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

### `0.0.1` — Window & Display Inspector

The project is currently validating the low-level foundation needed before any real workspace switching is attempted.

Implemented so far:

- Accessibility authorization detection and permission request;
- connected-display discovery;
- global display frames and visible frames;
- scale/backing information;
- Accessibility-based application-window discovery;
- application metadata and runtime window information;
- window geometry and state inspection;
- window-to-display mapping using display overlap;
- diagnostics that tolerate inaccessible or disappearing windows;
- unit-tested display/window mapping logic.

**0.0.1 is intentionally read-only.**

It does **not** move, resize, minimize, hide, close, restore, focus, or otherwise mutate existing application windows. This is deliberate: the project first needs to prove that it understands the desktop correctly before it is allowed to change it.

---

## Versioning

BlazaresSpaces uses milestone-oriented pre-1.0 versions. Each version is intended to represent a concrete increase in capability rather than an arbitrary build number.

The current development target is **`0.0.1`**. Until a milestone has been implemented and manually verified on real macOS hardware, it should be treated as development work rather than a completed release.

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

Window mutation experiments will first target a dedicated BlazaresSpaces-owned test window. External application windows are not to be modified automatically during the inspector phase.

---

## Planned architecture

BlazaresSpaces is a native macOS application written in Swift.

The current direction is:

```text
Swift / SwiftUI / AppKit
        │
        ├── Accessibility
        │     AXUIElement inspection and later controlled mutation
        │
        ├── Displays
        │     CoreGraphics + NSScreen topology
        │
        ├── Windows
        │     identity, geometry, snapshots, restoration
        │
        ├── Workspaces
        │     global multi-display logical contexts
        │
        └── UI / Diagnostics
              inspection, testing and configuration
```

The domain model is deliberately kept separate from macOS-specific Accessibility objects so that workspace logic can be tested without physically moving real windows.

See [`docs/architecture.md`](docs/architecture.md) for architecture notes and [`docs/vision.md`](docs/vision.md) for the product vision.

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

The exact strategy for hiding/deactivating inactive workspace windows is still experimental and will only be chosen after controlled testing.

---

## Roadmap

| Version | Goal |
|---|---|
| `0.0.1` | Window & display inspector |
| `0.0.2` | Safe capture / restore of layouts |
| `0.0.3` | Two global logical workspaces |
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

Window titles may contain sensitive information. They are therefore not intended to be persisted or logged verbosely by default.

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

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

## Current status — 0.0.1 Window & Display Inspector

The app can:

- report Accessibility authorization and request access;
- enumerate connected displays with IDs, global frames, visible frames, and scale factors;
- read normal application windows exposed through Accessibility;
- show application metadata, window geometry/state, and the display with the largest overlap;
- report discovery failures without terminating or mutating other applications.

This version is strictly read-only. It does not move, resize, minimize, hide, or restore windows.

## Running

1. Open `BlazaresSpaces.xcodeproj` in Xcode and run the `BlazaresSpaces` scheme.
2. Click **Request Access**.
3. Enable BlazaresSpaces in **System Settings → Privacy & Security → Accessibility**. If macOS lists an older build, remove it and request access again.
4. Return to the app and click **Refresh**.

Accessibility permission is tied to the built app's signing identity and location. Rebuilding or changing signing may require granting it again. Some apps expose incomplete attributes, protected windows, or no AX windows at all. Window titles are shown in the local diagnostics UI but deliberately omitted from logs because they may be sensitive.

## Directional milestones

- **0.0.1:** Window and display inspector
- **0.0.2:** Capture/restore layouts
- **0.0.3:** Two global logical workspaces
- **0.1.0:** Usable workspace-switching MVP
- **0.2.0:** Persistence and robust display topology handling
- **0.3.0:** Application/window rules and exclusions
- **0.4.0:** Menu bar UX and configuration
- **0.5.0:** Transition framework
- **0.6.0:** Optional Desktop Cube-style transition
- **1.0.0:** Stable global desktop manager

These milestones are direction, not promises. See [the vision](docs/vision.md) and [architecture notes](docs/architecture.md).


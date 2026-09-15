# Product vision

BlazaresSpaces brings a global virtual-desktop mental model to macOS: a workspace represents the complete user-arranged window state across every connected display. Switching a workspace will eventually switch the whole multi-display context at once, never one display independently.

The product remembers where users put windows; it does not choose layouts for them. Tiling, i3-style trees, native Spaces replacement, private APIs, SIP changes, cloud services, and transition effects are outside the initial scope.

Version 0.0.1 validates the read-only foundation: Accessibility permission, display topology, exposed windows, geometry, and window-to-display mapping. Capture/restore and window mutation must remain explicit future work.


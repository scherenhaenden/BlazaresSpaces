# ADR 0004: Isolate private native Spaces APIs

## Decision

0.4.0 may use private SkyLight/CGEvent techniques only inside
`Infrastructure/NativeSpaces`, behind capability-gated ports. The Domain and UI
must not reference SkyLight, CGS, scripting additions, or WindowServer details.

## Rationale

Public macOS APIs do not provide the required durable per-display Space
enumeration and coordinated manipulation. Research projects show useful private
primitives, but their ABIs and behavior are undocumented and can change across
macOS releases. Therefore discovery, focus, create, destroy and window movement
are independent capabilities, and the logical backend remains the fallback.

## Safety

Missing symbols are unavailable. Native IDs are revalidated immediately before
mutation. Unknown, fullscreen, stale, or unowned Spaces are not destructive
targets. Native Space destruction is disabled until ownership can be proven.

## Consequences

The app needs real-Mac validation and may ship with discovery-only native support
after an OS update. Distribution must account for private API risk and user
permissions. No SIP-disabling or scripting-addition prerequisite is hidden in
the product.

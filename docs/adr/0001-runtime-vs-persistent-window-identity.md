# ADR 0001: Separate runtime and persistent window identity

- Status: Accepted for 0.2.0
- Date: 2026-09-15

## Context

PID, AX identifiers, enumeration order, and AX elements identify or relocate a window only during a running session. Persisting them as identity could bind a logical record to the wrong window after either application restarts.

## Decision

Each managed logical window receives an application-owned durable ID and a privacy-conscious descriptor. Runtime identity and authorization live in a separate session binding created after discovery, matching, policy validation, and explicit confirmation before physical restoration.

Raw titles, PIDs, enumeration indexes, AX objects, authorization tokens, and parking frames are not persisted. A previous managed record expresses intent for that logical record; it does not authorize a new runtime candidate.

## Consequences

Restart restoration requires matching and may report missing or ambiguous. Multiple same-application windows remain independent. Persisted configuration can be tested without Accessibility APIs.

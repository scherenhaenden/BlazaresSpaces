# ADR 0002: Never guess an ambiguous window match

- Status: Accepted for 0.2.0
- Date: 2026-09-15

## Context

Several runtime windows may share bundle, role, size, and similar geometry. Choosing the first or nominally highest candidate without score separation makes discovery order an unsafe tie-breaker.

## Decision

Matching returns candidates, scores, and reasons as high confidence, probable, ambiguous, or missing. A tie or insufficient margin is ambiguous. Candidate order cannot change the result. Ambiguous and probable results do not authorize mutation; the user may choose a candidate or leave the record unbound.

Launch performs read-only discovery and matching. For 0.2.0, even high-confidence associations are explicitly confirmed before the first physical restoration.

## Consequences

The app may decline a restoration that looks obvious. This is safer than moving the wrong window. Missing records remain durable and can be reconsidered when an application appears later.

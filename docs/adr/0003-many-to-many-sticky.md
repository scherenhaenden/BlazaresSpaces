# ADR 0003: Window membership is many-to-many and sticky is semantic

- Status: Accepted for 0.2.0
- Date: 2026-09-15

## Context

A window may belong to several global workspaces, while a sticky window must also appear on workspaces created later. Storing membership per application collapses distinct same-app windows. Expanding sticky into today's IDs loses its future behavior.

## Decision

Each durable managed-window record owns a set of workspace IDs. Separate windows from one application have different durable IDs and sets. Sticky is an independent Boolean semantic. Workspace member lists are derived rather than competing mutable copies.

## Consequences

Persistence round trips must preserve same-app records, membership sets, and sticky state. Creating a workspace includes sticky records without rewriting explicit membership. Workspace deletion removes its ID while requiring a safe destination for exclusive records.

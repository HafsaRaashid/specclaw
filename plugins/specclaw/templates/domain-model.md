# Domain Model: {{title}}

**Path analyzed:** {{path}}
**Date analyzed:** {{date}}

## Entities

{{entities}}

## Relationships

```mermaid
erDiagram
{{relationships_diagram}}
```

{{relationships_narrative}}

## Business Rules

<!--
  Every business rule carries a permanent DR-NNN ID, assigned in the order
  rules are found, e.g.:

  1. **DR-007 — Promised-vs-delivered verdict computation** — <rule prose>

  (or the closest fit to this document's existing heading/list style — the
  ID is the stable part, not the surrounding markdown shape). DR-NNN IDs
  are permanent identifiers, not position — a later re-run may find rules
  in a different order, but an already-assigned ID is never reused or
  renumbered. A new rule takes the next free ID. A rule that no longer
  applies leaves a tombstone in place rather than disappearing, e.g.:

  4. **DR-004 — withdrawn 2026-08-01, superseded by DR-015**

  so that any other document citing DR-004 (clarifications.md, a rebuild
  backlog item, a golden-master scenario) fails loudly instead of silently
  pointing at whatever rule happens to occupy that position now.
-->

{{business_rules}}

## Enumerations

{{enumerations}}

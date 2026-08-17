# Proposal: {{title}}

**Created:** {{date}}
**Status:** 🟡 Draft

## Problem

_What problem are we solving? Why does it matter?_

{{problem}}

## Proposed Solution

_What are we building? High-level approach._

{{solution}}

## Scope

### In Scope
{{in_scope}}

### Out of Scope
{{out_scope}}

## Impact

- **Files affected:** {{file_count}} (estimated)
- **Complexity:** {{complexity}} (small / medium / large)
- **Risk:** {{risk}} (low / medium / high)

## Open Questions

{{questions}}

## Dependency Bypass

<!--
  PRESENT ONLY when this item is being built ahead of a module it depends on.
  Omit the whole section for a normal proposal — the overwhelming majority.

  Written by /specclaw:propose from the human's own answer to the bypass
  elicitation, never drafted speculatively and never filled in with a default.
  One bullet per bypassed dependency:

    - **BL-014 (MOD-005 — Auth)** → `ST-001`, strategy `stub-interface`.
      Chosen by <name>, <YYYY-MM-DD>.
      Stands in with: <the one-line concrete sketch the human picked>.

  The registry (.specclaw/analysis/module-stubs.md) is the source of truth for
  each entry; this section is the record of the decision made at propose time
  and the pointer /specclaw:plan follows to carry the bypass into spec.md.

  A dependency the human said was ALREADY BUILT is not listed here — that is
  not a bypass. A same-module prerequisite is never listed here at all: it is
  the item's own groundwork, propose refuses to bypass it, and the item waits.

  AN ITEM SPLIT IS NOT LISTED HERE EITHER. It fakes nothing, so it has no
  ST-### and no stub to retire; it gets its own section below.

  See templates/CONTRACT.md (m) and references/stub-discipline.md.
-->

{{dependency_bypass}}

## Item Split

<!--
  PRESENT ONLY when this proposal recorded an IS-### split — i.e. the human
  chose to implement part of this backlog item now and defer the rest until
  the items it depends on exist. Omit the whole section otherwise.

  Written by /specclaw:propose from the human's own choice. Shape:

    - **IS-001** — BL-010 (MOD-002). Chosen by <name>, <YYYY-MM-DD>.
      - **Implemented now:** patient listing · search/filter · paging ·
        backend API · React Patient Grid — rules DR-014, DR-015
      - **Deferred:** BL-001 authentication integration · BL-003 route-guard
        integration — rules DR-002
      - **Blocked until:** BL-001 BUILT, BL-003 BUILT
      - **Layer removal confirmed by:** <name>, <date>   (only if a whole
        layer was cut)

  THE SCOPE SECTION ABOVE MUST NAME THE DEFERRED SCOPE IN ITS "OUT" LIST.
  A split whose deferral appears nowhere in the scope section is a split the
  spec will quietly widen — which is exactly how a screen-bearing item once
  shipped with no user interface at all.

  The registry (.specclaw/analysis/item-splits.md) is the source of truth;
  this section is the record of the decision made at propose time and the
  pointer /specclaw:plan follows to scope spec.md to the now-slice.

  See templates/CONTRACT.md (o) and references/split-discipline.md.
-->

{{item_split}}

## Resumes Split

<!--
  PRESENT ONLY when this proposal RESUMES an earlier split — the backlog item
  was partly built before, and this change implements the remainder. Omit the
  whole section otherwise.

    - **Resumes IS-001** on BL-010.
      - **Already built:** <what the earlier slice implemented> — rules
        DR-014, DR-015
      - **By:** change `view-patient-grid`, PR #61, replay run
        2026-08-18-142230
      - **This change implements:** the deferred auth integration — rule
        DR-002

  THIS PROPOSAL COVERS THE REMAINDER ONLY. Never re-propose completed scope:
  the whole point of the IS-### record is that choosing item-split must not
  make implementation history disappear, and a resume that rebuilds the
  finished slice from scratch throws away exactly what the record preserved.
-->

{{resumes_split}}

---

**To proceed:** Review this proposal and approve to begin planning.

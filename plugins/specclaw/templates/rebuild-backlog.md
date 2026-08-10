# Rebuild Backlog: {{title}}

**Path analyzed:** {{path}}
**Date generated:** {{date}}
**Source documents:** codebase-report.md, architecture.md, domain-model.md, functional-spec.md

<!--
  NOTE ON THIS COMMENT: never write a literal double-brace placeholder
  token inside this comment's own prose (not even to describe it) — the
  render step's template substitution is a dumb global string replace, and
  a token mentioned here would get overwritten by that token's rendered
  value along with the real placeholder below, corrupting this comment.
  Refer to placeholders by section name instead (e.g. "the status block
  below", "the Backlog section").

  The status block right after this comment is bash-computed, never
  agent-drafted — date, which optional inputs (decisions.md,
  clarifications.md, baseline/manifest.json, baseline/scenarios.md) were
  consumed vs. missing (with the command that produces each),
  Gate/Verification counts, and the single recommended next item to
  propose. This block, and every item's Gate:/Verification: field below,
  is recomputed from scratch on every run — never hand-maintained.

  Expected per-item sub-structure inside the Backlog section below — one
  entry per backlog item, in readiness order (dependency rank first — a hard
  constraint — then within the same rank: CLEAR+VERIFIABLE, then
  CLEAR+PENDING CAPTURE/NO BASELINE DATA/UNVERIFIABLE, then OPEN QUESTIONS,
  then BLOCKED):

  ### BL-NNN — <Feature Title>

  **Maps to capability:** <functional-spec.md capability name/quote>
  **Depends on:** <earlier items' BL-NNN IDs, or "None">
  **Acceptance basis (domain-model.md):**
  - <entity/business-rule/enumeration reference, quoted — cite a business
    rule's DR-NNN ID (from domain-model.md) directly wherever the
    acceptance basis rests on a numbered rule, e.g. "DR-007: ..."; this is
    the join key /specclaw:bf-clarify and /specclaw:bf-baseline key their own
    CQ-NNN/GM-NNN citations against, so the ID itself must be textually
    present, not just implied by the quoted prose>

  **Verification inputs needed:**
  - <golden-master capture, external-format/DLL/COM semantics, or other
    human-supplied input this item's fidelity check will need — never
    leave this field blank; if genuinely nothing beyond the acceptance
    criteria above applies, say so explicitly rather than omitting it>

  **Gate:** <bash-computed: BLOCKED — blocked by <CQ-NNN + one-line title,
    ...> | OPEN QUESTIONS — risk from unanswered, non-blocking: <CQ-NNN,
    ...> | CLEAR>
  **Verification:** <bash-computed: VERIFIABLE — fixtures: <GM-NNN (legacy
    commit sha), ...> | PENDING CAPTURE — scenarios designed, no recorded
    fixture yet: <GM-NNN, ...> | UNVERIFIABLE — acceptance must come from a
    stakeholder decision, not fixture comparison (see CQ-NNN) | NO BASELINE
    DATA — baseline not run (or not designed) for these rules>
  **Settled constraints (from decisions):** <optional — only present when a
    mechanical-adopt decision applies to this item; omit the field entirely
    otherwise, never render it empty>

  **Status notes (human-added):** <optional — anything a human types under
    this exact heading (e.g. "built and merged, PR #12") survives every
    future /specclaw:bf-rebuild-plan --refresh verbatim, byte for byte. Nothing
    else in this document offers that guarantee — this is the one place a
    human note is safe to leave.>

  If two or more functional-spec capabilities are merged into a single
  backlog item, the item must state why in a "Merge rationale:" line —
  merging is a judgment call, never silent. A revised item (its acceptance
  basis rewritten because a decision changed its shape) states so inline,
  e.g. a line reading "⟲ revised per CQ-005, 2026-08-01" placed right after
  the heading.

  PROVISIONAL marker: an item touched by an open pending question — either
  a direct DR-NNN/BL-NNN join to a CQ-NNN promoted from a PQ-NNN (bash-
  computed), or a prose-level match the planner agent found and directed
  via a PROVISIONAL: line (agent-judged, mechanically re-verified by bash
  the same way an UNVERIFIABLE: directive is) — carries its own line right
  after the heading: "⚠ PROVISIONAL — pending PQ-NNN/CQ-NNN (proposed
  default: <x>)". This is soft-block: the item is still fully drafted,
  sequenced, and gated/verified exactly as any other; the marker rides
  alongside Gate/Verification, not instead of them, and both this line and
  Gate/Verification are recomputed from scratch on every run — it clears
  automatically once decisions.md answers the underlying question, no
  manual cleanup.

  BL-NNN IDs are permanent identifiers, not position — assigned once in
  dependency order on the first-ever run and never renumbered afterward.
  A later /specclaw:bf-rebuild-plan --refresh may append a genuinely new item
  (next free BL-NNN, dependency-placed correctly) or strike/defer an
  existing one, but an already-assigned ID is never reused, renumbered, or
  silently deleted — a struck item stays in the Backlog section as a
  one-line tombstone ("### BL-NNN — STRUCK — <reason>, <date>"); a deferred
  item moves in full to the Deferred section, out of the ready ordering.
  "Depends on:" always cites BL-NNN IDs, never bare position, for exactly
  this reason.
-->

{{status_header}}

## Backlog

{{backlog_items}}

## Deferred

{{deferred_items}}

## Sequencing Rationale

{{sequencing_rationale}}

## Coverage Check

{{coverage_check}}

## Change Report

<!--
  Populated only by /specclaw:bf-rebuild-plan --refresh — bash-computed by
  diffing this run's fresh Gate/Verification against the prior file's own
  stored Gate:/Verification: lines, never agent-narrated. On a first-ever
  run this section reads "Not applicable."
-->

{{change_report}}

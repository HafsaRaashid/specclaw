# Baseline Scenarios: {{title}}

**Date generated:** {{date}}
**Grounded in:** .specclaw/analysis/domain-model.md's numbered Business Rules{{supplementary_docs_note}}

<!--
  Every scenario carries:

  ### GM-NNN — <short title>

  - **Seam:** <from seams.md>
  - **Seam layer:** pure-function | service | http | persistence
  - **Business rules pinned:** <rule number(s) from domain-model.md, e.g. "rule 7">
  - **Arrange:** <state to set up>
  - **Act:** <call/action under test>
  - **Assert (shape):** <what the fixture must capture to prove the rule held>
  - **Kind:** boundary | edge case
  - **Verifies backlog item:** <rebuild-backlog.md item, or "not yet backlog-linked —
    rebuild-backlog.md does not exist yet">

  GM-NNN IDs are permanent, never renumbered — a future /specclaw:trace
  keys on them. Scenarios are derived directly from domain-model.md's
  documented rules; never invent a rule or a rationale the source document
  doesn't state.

  SEAM LAYER is a closed enum (templates/CONTRACT.md (i)), copied from the
  seam's own declaration in seams.md — never re-derived from this scenario's
  prose. `specclaw-bf-baseline record` extracts it verbatim into
  manifest.json and HARD-FAILS on a missing or non-enum value; there is no
  default. It exists so /specclaw:bf-replay can enforce that the replay test
  exercises the rebuild at the same layer the fixture was captured at — a
  service-layer fixture replayed through HTTP measures transport and
  middleware, not the business rule this scenario pins.

  IDENTITY AND IDEMPOTENCY SCENARIOS (CONTRACT.md (k)): when the rule is
  about identity or idempotency, the Assert (shape) must name boolean
  ASSERTIONS the seam itself can answer — first_call_created,
  second_call_same_entity, second_call_created_duplicate — never a raw
  generated id. Two independently seeded databases never produce the same
  key, so comparing one is guaranteed noise and the rule goes unverified. A
  raw id recorded as evidence belongs in the fixture's normalized_fields, as
  a canonical path (CONTRACT.md (g)).

  A scenario the legacy app can never actually reach (no code path sets
  that state) does not belong here — list it under "No Legacy Behaviour
  Exists" instead, since there is no legacy behaviour to pin as a golden
  master.

  PROVISIONAL marker: when a scenario's pinned business rule is itself
  provisional (domain-model.md already marks it, or a clarifications.md CQ
  promoted from a PQ touches it), append
  `⚠ PROVISIONAL — pending PQ-NNN/CQ-NNN (proposed default: <x>)` to that
  scenario's own "Business rules pinned" line. This is soft-block — the
  scenario is still fully designed, just like any other; the Rule Coverage
  Check below groups these under their own "Provisional pending decision"
  heading. `specclaw-bf-baseline record` detects this literal marker text
  mechanically to set the matching manifest.json fixture entry's `status`
  to `PROVISIONAL` (see templates/CONTRACT.md) — never rename or reformat
  the marker string, or that detection silently stops working.
-->

## Scenarios

{{scenarios}}

## No Legacy Behaviour Exists

{{unreachable_states}}

## Rule Coverage Check

{{rule_coverage}}

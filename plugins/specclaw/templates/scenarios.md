# Baseline Scenarios: {{title}}

**Date generated:** {{date}}
**Grounded in:** .specclaw/analysis/domain-model.md's numbered Business Rules{{supplementary_docs_note}}

<!--
  Every scenario carries:

  ### GM-NNN — <short title>

  - **Seam:** <from seams.md>
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

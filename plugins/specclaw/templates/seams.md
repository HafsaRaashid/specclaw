# Baseline Seams: {{title}}

**Date generated:** {{date}}
**Grounded in:** .specclaw/analysis/domain-model.md{{supplementary_docs_note}}

<!--
  A seam is a place where the legacy app's behaviour can be observed as
  input -> output without driving its UI. Every candidate must be ranked
  into exactly one of these classes:

  | Class                     | Cost   | Fidelity | Notes |
  |----------------------------|--------|----------|-------|
  | Pure function              | lowest | highest  | No setup, fully deterministic. Capture these first. |
  | Stateful service boundary   | medium | high     | Needs a database arrange step per scenario. |
  | Data/persistence boundary   | medium | medium   | Good for cascade and delete-rule behaviour. |
  | UI automation               | highest| lowest   | Excluded — explain why in this document, don't just omit it. |

  Every ranking must be justified with a real citation (file:line, or a
  quote from an analysis document) — a seam listed without justification is
  not a finding. Determinism findings belong in "Capture Blockers" below,
  not folded into a seam's description.

  /specclaw:bf-baseline does not run the legacy app and does not capture
  fixtures itself — this document designs the harness; a human runs the
  capture (`--harness` then `--record`). That boundary is deliberate, not a
  gap to paper over.
-->

## Seam Ranking

{{seam_ranking}}

## Excluded: UI Automation

{{ui_exclusion_rationale}}

## Capture Blockers (Determinism Audit)

{{determinism_audit}}

## Recommended Seam

{{recommended_seam}}

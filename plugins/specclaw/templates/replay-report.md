# Replay Report: {{target}}

**Date:** {{date}}
**Legacy commit:** {{legacy_commit_sha}}
**Backlog item:** {{bl_item}}
**Selected fixtures:** {{selected_count}}
**Overall verdict:** {{overall_verdict}}

## Summary

| Verdict | Count |
|---|---|
| MATCH | {{match_count}} |
| DIVERGES | {{diverges_count}} |
| ERROR | {{error_count}} |
| NOT REPLAYABLE | {{not_replayable_count}} |

<!--
  MATCH/DIVERGES/ERROR are computed mechanically by `specclaw-replay compare`
  — never asserted by an agent. Every DIVERGES row's sanction citation below
  was independently re-verified by `specclaw-replay sanction-check` against
  decisions.md's own `### CQ-0NN —` headings; an agent's claim alone never
  promotes a row to SANCTIONED.
-->

## Fixtures

| Scenario | Verdict | Sanction | Detail |
|---|---|---|---|
{{fixture_table_rows}}

## Not Replayable

{{not_replayable_list}}

## DR Rules Left Uncovered

_Business rules from domain-model.md not exercised by any REPLAYABLE fixture in this run (MATCH, DIVERGES, or ERROR — NOT REPLAYABLE fixtures don't count as coverage):_

{{dr_uncovered_list}}

## Verdict

**{{overall_verdict}}**

- **PASS** — every REPLAYABLE fixture MATCHed, or every DIVERGES is SANCTIONED by a decided CQ.
- **FAIL** — at least one ERROR, or at least one DIVERGES with no sanctioning decided CQ. "Looks more correct" is never a sanction.
- **INCOMPLETE** — the selected fixture set was non-empty but nothing in it was actually replayable this run.

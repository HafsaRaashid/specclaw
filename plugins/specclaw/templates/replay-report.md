# Replay Report: {{target}}

**Date:** {{date}}
**Stack:** {{stack}}
**Legacy commit:** {{legacy_commit_sha}}
**Backlog item:** {{bl_item}}
**Selected fixtures:** {{selected_count}}
**Overall verdict:** {{overall_verdict}}

{{evidence_block}}

## Summary

| Verdict | Count |
|---|---|
| MATCH | {{match_count}} |
| DIVERGES | {{diverges_count}} |
| ERROR | {{error_count}} |
| NOT REPLAYABLE | {{not_replayable_count}} |

<!--
  MATCH/DIVERGES/ERROR are computed mechanically by `specclaw-bf-replay compare`
  — never asserted by an agent. Every DIVERGES row's sanction citation below
  was independently re-verified by `specclaw-bf-replay sanction-check` against
  decisions.md's own `### CQ-0NN —` headings; an agent's claim alone never
  promotes a row to SANCTIONED.
-->

## Fixtures

| Scenario | Verdict | Sanction | Detail |
|---|---|---|---|
{{fixture_table_rows}}

## Not Replayable

{{not_replayable_list}}

## Open Decisions Blocking PASS

<!--
  Soft-block, not a refusal to run: an exercised (MATCH/DIVERGES/ERROR)
  fixture whose underlying scenario still rests on an open pending question
  never reaches a plain PASS, no matter how clean its own comparison came
  back. This section — and the -PROVISIONAL suffix on the affected rows in
  the Fixtures table above — clears automatically, with no manual cleanup,
  the next time this report is rendered after the cited PQ/CQ is answered
  under decisions.md's ## Decisions.
-->

{{open_decisions_blocking_pass}}

## DR Rules Left Uncovered

_Business rules from domain-model.md not exercised by any REPLAYABLE fixture in this run (MATCH, DIVERGES, or ERROR — NOT REPLAYABLE fixtures don't count as coverage):_

{{dr_uncovered_list}}

## Verdict

**{{overall_verdict}}**

- **PASS** — every REPLAYABLE fixture MATCHed (or every DIVERGES is SANCTIONED by a decided CQ), and none of them are PROVISIONAL.
- **PASS-PENDING-DECISIONS** — same as PASS, except at least one exercised fixture is still PROVISIONAL — see Open Decisions Blocking PASS above. Gates CI/PR exactly like FAIL (exit code 1); analysis and build keep moving, but this run is not yet citable as final proof.
- **FAIL** — at least one ERROR, or at least one DIVERGES with no sanctioning decided CQ. "Looks more correct" is never a sanction.
- **INCOMPLETE** — the selected fixture set was non-empty but nothing in it was actually replayable this run.

{{ui_fidelity_footer}}

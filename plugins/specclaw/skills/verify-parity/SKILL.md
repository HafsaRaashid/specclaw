---
name: verify-parity
description: Zero-tolerance parity check between a modernized SpecClaw implementation and its legacy golden master. Reads .specclaw/matrix-inputs.json and .specclaw/golden-master-legacy.json, evaluates the modern code against every case, and writes a pass/fail Markdown audit report. Trigger before /specclaw:verify or /specclaw:pr on any legacy migration change, whenever the user asks to check parity, compare modern vs legacy output, or validate a modernized module against its baseline, or automatically inside /specclaw:loop's build/verify cycle when a golden master exists for the change.
---

# Verify Parity

## Purpose
Answer one question with no ambiguity: does the modernized code produce
byte-for-byte identical output and exception messages to the legacy
system, for every input in the boundary matrix? This is a hard gate —
not an advisory check — so it must fail loudly and specifically rather
than rounding up a "close enough" result.

## Step 0 — Setup
**First, run** `specclaw-ensure-init .specclaw` — idempotently creates
`.specclaw/` if it doesn't exist (silent if already initialized).

**Then archive the prior audit report, if any**, before writing a new
one, so a past run's result is never silently lost:
```bash
mkdir -p .specclaw/analysis/archive
[ -f .specclaw/parity-audit-report.md ] && mv .specclaw/parity-audit-report.md \
  .specclaw/analysis/archive/$(date +%Y-%m-%d-%H%M%S)-parity-audit-report.md
```
Skip the move if that file doesn't exist yet.

## Non-interactive execution contract
- Never prompt for file paths; both inputs are fixed:
  `.specclaw/matrix-inputs.json` and `.specclaw/golden-master-legacy.json`.
- If either file is missing, do not fabricate results: write a report
  stating golden master is absent, set status `BLOCKED`, and stop.
- Resolve the modern implementation the same way `extract-golden-master`
  resolves its legacy target: from the active `.specclaw/changes/<name>/`
  context first, falling back to matching module names against the
  current build output.

## Step 1 — Load inputs
Read both JSON files fully. Confirm every `case_id` in
`matrix-inputs.json` has a matching entry in
`golden-master-legacy.json`; if any are missing, list them explicitly
in the report under "Golden master gaps" rather than skipping silently.

## Step 2 — Evaluate the modern implementation
For each case:
- Invoke the modern function/endpoint with the exact inputs from the
  matrix.
- Capture its output or thrown exception exactly as produced.
- Compare against the legacy result:
  - **Numeric/currency/tax/domain-calculation fields**: exact equality
    only. 0.00% tolerance — no epsilon, no rounding-to-display-precision
    before comparing. A legacy `19.995` vs modern `20.00` is a mismatch
    even though it looks trivial.
  - **Exception cases**: both the exception *type/category* and the
    *message text* must match verbatim; a correct exception with a
    reworded message is still a discrepancy and must be logged as one.
  - **String/other fields**: exact equality.

## Step 3 — Write the audit report
Write `.specclaw/parity-audit-report.md`:

```markdown
# Parity Audit Report
Generated: <ISO-8601 timestamp>
Golden master: .specclaw/golden-master-legacy.json
Matrix: .specclaw/matrix-inputs.json

## Summary
- Total cases evaluated: <N>
- Matches: <N>
- Discrepancies: <N>
- Match percentage: <XX.XX%>
- Status: PASS | BLOCKED

## Discrepancies
| Case ID | Input | Legacy Output | Modern Output | Delta |
|---|---|---|---|---|
| MOD01-C001 | {...} | 1042.50 | 1042.45 | -0.05 |

## Golden Master Gaps
(cases present in matrix-inputs.json with no corresponding legacy result — investigate before trusting a PASS)

## Notes
<any low-confidence CFG branches inherited from extract-golden-master that affected this run>
```

- The Delta column is blank/`—` for exception-message or string
  mismatches (put "message differs" or "type differs" there instead
  of a numeric delta).
- Sort the discrepancy table by module, then case_id, so re-runs diff
  cleanly.

## Step 4 — Set gate status
- Status is `PASS` **only if** match percentage is exactly 100.00% and
  there are zero golden-master gaps.
- Any discrepancy, any gap, or any missing input file sets status
  `BLOCKED`.
- When `BLOCKED`, the summary section must be the first thing in the
  file (already satisfied by the template above) so `/specclaw:loop`
  can parse it and route the discrepancy table back into the
  build step for auto-correction.
- Do not soften a `BLOCKED` status based on "close" numeric deltas —
  there is no partial credit on financial/domain-calculation fields.

## Completion criteria
Print a one-line summary matching the report's Summary block, and exit
with the Status value so `/specclaw:loop` can branch on it without
re-parsing the Markdown.

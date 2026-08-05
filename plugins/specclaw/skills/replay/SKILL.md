---
description: Golden-master comparison — replays captured legacy fixtures (.specclaw/baseline/manifest.json + fixtures/) against the new app's own behaviour and reports MATCH/DIVERGES/ERROR per fixture, with every divergence checked against decisions.md for an explicit sanctioning CQ. Runs in the new (rebuild) repo, after /specclaw:verify and before /specclaw:pr. `<change-name>` scopes to that change's BL item(s); `--all` runs the full regression sweep across every fixture in the manifest. Read-only with respect to app source, fixtures, and the manifest. Writes .specclaw/changes/<name>/replay-report.md (or .specclaw/replay/report-<timestamp>.md for --all) and, by default, retains a durable evidence package — the generated tests (source), actual outputs, a fixture-manifest excerpt, and run metadata — under .specclaw/changes/<name>/replay-evidence/run-<timestamp>/, meant to be committed alongside the change's PR as citable proof of mechanical verification. `--discard` opts a single run out of evidence retention (never recommended for an acceptance run); `--keep` is accepted for backward compatibility and behaves identically to the default. `--prune-evidence <n>` keeps only the newest n evidence runs for a change, on request only. Exit code reflects the verdict (0 PASS, 1 FAIL, 2 INCOMPLETE) so it can gate CI.
---

# specclaw replay

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized).

Compares the new app's actual behaviour against `.specclaw/baseline/`'s captured golden-master fixtures. This is **not** `/specclaw:verify` — verify checks a change against its own spec/tasks; replay checks the rebuild against the *legacy app's own recorded behaviour*. Neither command modifies the other; do not merge this flow into `verify`.

Invocation:
```
/specclaw:replay <change-name>                    # fixtures relevant to this change's BL item(s); retains evidence
/specclaw:replay --all                            # full regression: every fixture in the manifest; retains evidence
/specclaw:replay <change-name> --keep              # accepted for compatibility — identical to the default
/specclaw:replay <change-name> --discard           # opt this one run out of evidence retention (never for an acceptance run)
/specclaw:replay <change-name> --prune-evidence <n> # keep only the newest n evidence runs for this change; no new replay run
```

## Evidence Retention

Retention is the default, not an opt-in. A verdict alone ("PASS") is a claim; the generated tests and their actual results are the proof — that the rebuilt application was mechanically compared against recorded behaviour of the original application, not just asserted to be. Deleting them after the run, as this command used to do by default, threw the proof away and kept only the claim.

**Where evidence lives** — a per-change run:
```
.specclaw/changes/<name>/replay-evidence/
├── evidence-summary.md        # the ONE mutable file — regenerated in full every run
└── run-<timestamp>/
    ├── report.md               # identical content to replay-report.md for this run
    ├── run-metadata.json        # legacy SHA, new-repo SHA, plugin version, dotnet
    │                            # version, date, fixture counts by verdict, overall verdict
    ├── tests/                   # the generated test project — SOURCE ONLY (never
    │                            # bin/, obj/, or restored packages — an explicit
    │                            # exclusion list in the copy step, not a hoped-for
    │                            # dotnet clean)
    ├── actual-results/          # actual-output JSON per fixture, from this run
    └── expected/                # manifest excerpt: fixture IDs + hashes replayed
                                  # against (never a copy of the fixture files
                                  # themselves — those stay the single source of
                                  # truth in .specclaw/baseline/fixtures/)
```
For `--all` runs, the same `run-<timestamp>/` structure lives under `.specclaw/replay/evidence/` instead (no `evidence-summary.md` there — that index is change-scoped by design).

**Rules:**
- Every part of a `run-<timestamp>/` folder, once written, is immutable — a later run never modifies or deletes it. Runs accumulate. `evidence-summary.md` is the sole exception: it's fully regenerated (never appended to) on every run and by `--prune-evidence`.
- `--keep` is accepted and silently treated identically to the default — retention already keeps everything that matters, so there's nothing left for `--keep` to additionally preserve.
- `--discard` is the genuine opt-out, for a throwaway run (mid-debugging iteration, say) — the report is still written, but no evidence folder is created and `evidence-summary.md` is left untouched. **Never use `--discard` for a run whose result is meant to gate an acceptance decision or a PR.**
- `--prune-evidence <n>` keeps only the newest `n` run folders for a change (or the `--all` evidence pool), deleting the rest and regenerating `evidence-summary.md` to match. This never happens automatically — only when explicitly requested.
- Evidence is committable by design — nothing this command writes is gitignored. `finalize` checks whether the target repo's own `.gitignore` would swallow the evidence path anyway and warns loudly if so, rather than letting "proof" silently end up untracked. The expectation is that a change's final passing run's evidence is committed alongside its PR — that's what makes it citable later, to a client or anyone else.
- `replay-report.md` (and the identical `report.md` inside the evidence folder) carries a short evidence-pointer header: the evidence path (or a plain statement that this run's evidence was discarded), a brief run-metadata summary, and — for client consumption — one sentence naming what the package actually contains.

**Full proof chain, in one place:** legacy-side evidence is `.specclaw/baseline/harness/` + `fixtures/` + `manifest.json` — already permanent (harness and manifest are archived-then-replaced on re-record, per `/specclaw:baseline`'s own convention; fixture files are additive and never deleted by any specclaw command). New-side evidence is this command's `replay-evidence/` folders. Together they are the complete, durable record of what was captured from the original application and what the rebuild was actually checked against.

## Step 0 — Setup

Generate a run id: `run_id=$(date +%Y-%m-%d-%H%M%S)`. This ids both the run directory (`.specclaw/replay/run-<run_id>/`) and, for `--all`, the report filename (`.specclaw/replay/report-<run_id>.md`).

**If `--prune-evidence <n>` was passed**, this is the entire job — run `specclaw-replay prune-evidence .specclaw <change-name-or---all> <n>`, relay its one-line summary, and stop. No new replay happens; nothing below this point runs.

**Archive the prior report, if any, before writing a new one** — for a per-change run only (an `--all` report is already uniquely timestamped, nothing to archive):
```bash
mkdir -p .specclaw/analysis/archive
[ -f .specclaw/changes/<change>/replay-report.md ] && mv .specclaw/changes/<change>/replay-report.md \
  .specclaw/analysis/archive/$(date +%Y-%m-%d-%H%M%S)-replay-report-<change>.md
```
Skip the move if that file doesn't exist yet. Same convention as `verify-parity`/`extract-golden-master`'s own archive step.

## Step 1 — Resolve fixture selection

```bash
specclaw-replay resolve .specclaw <change-name-or---all> .specclaw/replay/run-<run_id>/selection.json
```

Deterministic, no agent. For a named change: reads `.specclaw/changes/<change>/proposal.md` and `spec.md`, extracts its cited backlog item(s) (`BL-0\d\d\d` literally, or `item N`/`backlog item N` mapped to `BL-0<N>` and cross-checked against `rebuild-backlog.md`'s own `### BL-0NN —` headers), then joins against `.specclaw/baseline/manifest.json`'s `verifies_backlog_item` field to select every `GM-###` fixture behind that BL item. For `--all`, selects every fixture in the manifest, ignoring change scoping entirely.

This subcommand also **is** the preconditions check — it fails loudly (non-zero exit, no report written) if:
- the change cites no BL item at all ("replay only makes sense for backlog-driven changes")
- the cited `BL-0NN` doesn't exist in `rebuild-backlog.md`
- `.specclaw/baseline/manifest.json` or the fixtures directory is missing
- any selected fixture's file is missing, or its recomputed sha256 doesn't match the manifest's recorded `content_hash` (fixtures were edited or half-copied — **never compare against a tampered baseline**)

**If it exits non-zero, surface its stderr message verbatim and stop.** On success it writes `selection.json` (selected fixtures with their seam/DR/hash/anchor metadata, the BL items and DR rules covered, the legacy commit SHA, and the selected count) and prints a one-line summary.

## Step 2 — Scaffold the run directory

```bash
specclaw-replay init-rundir .specclaw .specclaw/replay/run-<run_id>
```

Deterministic. Creates the run directory, copies the fixed (non-agent-written) harness files from `$CLAUDE_PLUGIN_ROOT/templates/replay-harness/` (`Capture.cs`, `ResultWriter.cs`) verbatim, and resolves `ReplayHarness.csproj.template`'s `{{core_project_reference}}` placeholder by searching `src/**/*.csproj` for the new repo's own Core/domain project — **fails loudly if zero or more than one candidate is found**, naming the candidates rather than guessing. Also resolves `{{target_framework}}` from that project's own `<TargetFramework>`.

## Step 3 — Spawn the replay-mapper agent

`Agent` tool, `subagent_type: "replay-mapper"`, model from `config.yaml` `models.review` (default: `anthropic/claude-sonnet-4-5`). Pass as context:
- `selection.json` from Step 1 (the fixtures to map).
- Resolved paths of `.specclaw/baseline/scenarios.md`, `.specclaw/baseline/seams.md`, `.specclaw/analysis/decisions.md`, `.specclaw/analysis/domain-model.md`.
- The project root, so the agent reads the new repo's actual current source for each selected fixture's seam.
- The resolved run directory path and `$CLAUDE_PLUGIN_ROOT/templates/replay-harness/Arrange.example.cs` to imitate.

For each selected fixture the agent decides **REPLAYABLE** or **NOT REPLAYABLE** (with reason — the three named categories below, or a stated general reason; never a silent skip), and for every REPLAYABLE fixture generates one xUnit `[Fact]` file under the run directory that arranges via the new repo's own `DbContext.Database.Migrate()` (per ADR-0003 — the migration path itself is under test, never `EnsureCreated`), pins the clock where the seam has an injectable override, feeds the fixture's `input`, and writes the result via `ResultWriter.Write(scenarioId, runDir, output)`.

Known NOT REPLAYABLE reasons the agent must recognize explicitly (never invent a fourth silently — if none of these fit, state the real reason in full):
- **Clock dependency**: the seam's behaviour depends on "now" and the new code still has no injectable override for that call site → reason names the exact call site, remediation says "adopt an injectable clock/TimeProvider in `PlanningService`" and cites `seams.md`'s CB-1 recommendation (or a newer ADR if one now exists).
- **Shape changed under a decided CQ**: the seam's input/output shape changed because of a `decisions.md` entry under `## Decisions` (not "Outstanding") — replayable only via a documented input translation that cites that CQ's ID.
- **No-legacy-behaviour scenario**: the fixture is listed under `scenarios.md`'s "No Legacy Behaviour Exists" section — NOT REPLAYABLE by definition; point at the stakeholder-decided acceptance criteria for that behaviour instead of attempting a capture.

The agent writes `.specclaw/replay/run-<run_id>/mapping.json` itself (one entry per selected fixture: verdict REPLAYABLE/NOT REPLAYABLE, reason, remediation if applicable, generated test file path if replayable) — this skill does not write it.

**The agent never declares MATCH or DIVERGES for anything.** Its only verdicts are REPLAYABLE / NOT REPLAYABLE; the actual behavioural comparison happens mechanically in Step 5.

## Step 4 — Run the generated tests

```bash
specclaw-replay run-tests .specclaw/replay/run-<run_id>
```

Deterministic. Runs `dotnet build` then `dotnet test` inside the run directory, captures output (capped), and reports which fixtures wrote a valid `actual/<GM-ID>.json` and which didn't (a missing/invalid actual-result file after the test run is the ERROR signal — the generated Fact crashed before completing capture). This command does not itself decide MATCH/DIVERGES.

## Step 5 — Compare (deterministic)

```bash
specclaw-replay compare .specclaw .specclaw/replay/run-<run_id>
```

For every REPLAYABLE fixture: loads the fixture's expected `output` and the run's actual `output`, walks both field-by-field, skips any path listed in the fixture's own `normalized_fields`, and compares `ExceptionType`/`InnerExceptionType` fields by **short type name only** (the part after the last `.`) — the rebuild renamed `ExecutivePlanning.Core` to its own namespace per ADR-0002, so a bare namespace difference must never itself register as a divergence. Writes `compare.json`: `MATCH` / `DIVERGES` (with every differing field path and both values) / `ERROR` (with the captured `dotnet test` failure detail) per fixture. NOT REPLAYABLE fixtures pass through untouched with their Step 3 reason. **This verdict is computed entirely in this script — never asserted by an agent.**

## Step 6 — Spawn the replay-auditor agent (only if any DIVERGES)

If `compare.json` has zero `DIVERGES` entries, skip straight to Step 7 (nothing to sanction).

Otherwise: `Agent` tool, `subagent_type: "replay-auditor"`, same model routing as Step 3. Pass `compare.json`'s DIVERGES entries, `selection.json` (for each fixture's DR rule), and resolved paths of `.specclaw/analysis/decisions.md` and `.specclaw/analysis/domain-model.md`. For each DIVERGES fixture the agent searches `decisions.md`'s `## Decisions` section for a CQ that explicitly covers the affected rule and explicitly chose to diverge (e.g. a DEFECT question answered "fix in rebuild") — if found, cites the CQ ID and quotes the deciding language; if not, says so plainly rather than inventing a citation. Writes `.specclaw/replay/run-<run_id>/sanction.json` itself.

**"Looks more correct" is never a sanction.** Only a decision that is actually recorded under `## Decisions` counts — an `## Outstanding Questions` entry, however obviously right the new behaviour seems, sanctions nothing.

## Step 7 — Sanction check (mechanical re-verification)

```bash
specclaw-replay sanction-check .specclaw .specclaw/replay/run-<run_id>
```

Deterministic. For every DIVERGES fixture where the agent claimed a sanctioning CQ, mechanically confirms that `decisions.md` actually contains a `### CQ-0NN —` (or `SQ-`/`UQ-`) heading for that exact ID — headings only ever appear under `## Decisions` in this document's real structure, never under `## Outstanding Questions`, so this single grep is sufficient proof the citation is real and decided, not proposed. Also greps that decision's own block text for the affected DR rule / seam name the divergence touches; if it's not mentioned, downgrades to a `WARN` in the report rather than silently trusting or silently rejecting. Any fixture the agent could not cite a CQ for is `UNSANCTIONED` outright. Writes `sanction-verified.json`.

## Step 8 — Render the report

```bash
specclaw-replay render .specclaw <change-name-or---all> .specclaw/replay/run-<run_id> [--discard]
```

Pass `--discard` only if that flag was on the original invocation — it tells `render` to write a plain "evidence discarded" notice instead of a path to a folder that (per Step 9) won't exist. Deterministic. Renders `$CLAUDE_PLUGIN_ROOT/templates/replay-report.md` from `selection.json` + `mapping.json` + `compare.json` + `sanction-verified.json`: header (date, legacy SHA, fixture counts by verdict), the **evidence-pointer block** (evidence path or discard notice, a brief run-metadata summary, and the one-sentence client explanation of what the package contains), the full per-fixture table (verdict + sanction citation where applicable), the NOT REPLAYABLE list with remediation, every DR rule from `domain-model.md` left uncovered by any REPLAYABLE fixture in this run, and the overall verdict:

- **PASS** — every REPLAYABLE fixture is MATCH, or DIVERGES-but-SANCTIONED.
- **FAIL** — any ERROR, or any DIVERGES that is not SANCTIONED.
- **INCOMPLETE** — the selected set was non-empty but every fixture in it came back NOT REPLAYABLE (nothing was actually exercised).

Writes the report to `.specclaw/changes/<change>/replay-report.md` (named change) or `.specclaw/replay/report-<run_id>.md` (`--all`), and exits `0`/`1`/`2` for PASS/FAIL/INCOMPLETE respectively — this computation is untouched by evidence retention; the same inputs produce the same verdict and exit code as before.

## Step 9 — Retain evidence (or discard, if asked)

```bash
specclaw-replay finalize .specclaw <change-name-or---all> .specclaw/replay/run-<run_id> [--keep|--discard]
```

Pass whichever of `--keep`/`--discard` was on the original invocation (neither, for the default). Unless `--discard`, this curates the run directory into `.specclaw/changes/<change>/replay-evidence/run-<run_id>/` (or `.specclaw/replay/evidence/run-<run_id>/` for `--all`) — see **Evidence Retention** above for the exact structure — regenerates `evidence-summary.md` for a named change, warns if this repo's `.gitignore` would swallow the evidence path, then removes the now-redundant working run directory. `--keep` is accepted and does exactly the same thing as passing nothing. With `--discard`, it just deletes the run directory — no evidence folder, `evidence-summary.md` untouched. The report file itself (written in Step 8, already containing the correct evidence-pointer text either way) is never touched by this step.

## Step 10 — Present a summary

Relay `render`'s one-line summary and the overall verdict to the user, plus the report's path and (unless `--discard`) the evidence folder path from `finalize`'s own summary line. **If `finalize` warned about `.gitignore` swallowing the evidence path, surface that warning directly** — don't let "proof" silently end up untracked without the user knowing. If FAIL, name the unsanctioned divergences and ERRORs directly rather than telling the user to open the file.

## What this command does not do

`/specclaw:replay` never modifies application source, `.specclaw/baseline/fixtures/`, or `manifest.json` — it is read-only against all three. It never lets an agent assert MATCH/DIVERGES/ERROR (Steps 5 and 7 are bash, not agent judgment) and never accepts a divergence as sanctioned on the agent's word alone (Step 7 re-verifies mechanically). It never silently skips a fixture — every non-compared fixture is NOT REPLAYABLE with a stated reason in the report. It does not modify `/specclaw:verify` or any other command; it is a new sibling that runs after verify, before `/specclaw:pr`. It never modifies or deletes a previously-written evidence run folder — only `--prune-evidence`, run explicitly, ever removes one, and even then only the oldest beyond the requested count. It never prunes evidence automatically as a side effect of a normal run. It never changes how fixtures are selected, how the replay-mapper/replay-auditor agents classify or write tests, how `compare`/`sanction-check` compute their verdicts, or the resulting exit codes — evidence retention is purely what happens to the artifacts *after* that verdict is already final.

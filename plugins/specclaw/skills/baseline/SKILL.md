---
description: Design, generate, and record the golden-master harness that proves a rebuild behaves identically to the legacy app it replaces. Default mode ranks seams (pure function / stateful service / data boundary / UI-excluded), audits every seam for non-determinism (clocks, identity values, unstable ordering), and derives scenarios from domain-model.md's numbered business rules — writing .specclaw/baseline/seams.md and scenarios.md. Ends by asking the human to confirm the recommended seam before any harness code is generated. `--harness` generates a runnable, stack-specific capture project (currently .NET) under .specclaw/baseline/harness/. `--record` scans .specclaw/baseline/fixtures/ for a human-produced capture, validates it against scenarios.md, and writes manifest.json. Read-only with respect to source code — writes only inside .specclaw/, and never runs the legacy app or captures a fixture itself. Requires domain-model.md (run /specclaw:domain first). Use after the analysis commands, alongside /specclaw:clarify, before trusting a rebuild-backlog.md item as behaviorally verified.
---

# specclaw baseline

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized; auto-inits using the current directory's basename as the project name).

Design, generate, and record the golden-master harness for proving behavioral equivalence between the legacy app and its rebuild. Read-only side-command — no `specclaw-validate-change` call, no `<change>` involved, matching the `analyze`/`architecture`/`domain`/`rebuild-plan`/`clarify` pattern.

This command does **not** run the legacy app and does **not** capture fixtures itself, in any mode. Designing the harness (Mode A), generating the runnable capture code (Mode B, `--harness`), and validating a capture (Mode C, `--record`) are all separate from actually *running* a capture — that step is always a human, running `dotnet test` (or the generated harness's equivalent) themselves. That boundary is deliberate: capture needs a real build, possibly a real database, and human judgment about which scenarios matter.

## Mode A — design (default: no flag)

1. **Collect:**
   ```bash
   specclaw-baseline collect .specclaw
   ```
   Requires `.specclaw/analysis/domain-model.md` to exist — scenarios are derived from its numbered business rules. **If it exits non-zero, surface its stderr message to the user verbatim and stop** — it names `/specclaw:domain` as the command to run first. Don't retry, don't design scenarios from nothing. Also reports which supplementary documents (`codebase-report.md`, `architecture.md`, `functional-spec.md`, `rebuild-backlog.md`) are present, for the agent's own stack detection and backlog-item linkage.

2. **Archive the prior design, if any**, before writing a new one:
   ```bash
   mkdir -p .specclaw/baseline/archive
   mv .specclaw/baseline/seams.md .specclaw/baseline/archive/$(date +%Y-%m-%d-%H%M%S)-seams.md
   mv .specclaw/baseline/scenarios.md .specclaw/baseline/archive/$(date +%Y-%m-%d-%H%M%S)-scenarios.md
   ```
   Skip each `mv` independently if that specific file doesn't exist yet. This is `/specclaw:baseline`'s own archive directory (`.specclaw/baseline/archive/`) — a separate document family from `.specclaw/analysis/archive/`, but the same convention: archive-then-replace, never silently overwrite.

3. **Spawn the design agent:** `Agent` tool, `subagent_type: "baseline-designer"`, on the model from `config.yaml` `models.review` (default: `anthropic/claude-sonnet-4-5`) — same routing as the sibling read-only analysis agents, since this is still read-only design work, not spec/design authoring for a change. Pass as context:
   - The collected JSON (stdout of Step 1).
   - The resolved path of `.specclaw/analysis/domain-model.md`, plus the resolved paths of whichever supplementary documents are present, for the agent to `Read` directly.
   - **Tell the agent explicitly it is running in design mode.**

4. The agent writes `.specclaw/baseline/seams.md` and `.specclaw/baseline/scenarios.md` itself, per its own Output section — this skill does not write either file.

5. **Present a short summary** to the user: the seam ranking (which class was recommended and why), the capture blockers (non-determinism) found and their proposed mitigations, and the scenario count against `domain-model.md`'s numbered business rules (from the Rule Coverage Check).

6. **Ask the human to confirm the recommended seam** before generating a harness — do not proceed to `--harness` in the same turn without an explicit go-ahead. If any capture blocker was recommended for "record timestamp + injectable clock" (the highest-fidelity mitigation), remind the user this implies a design constraint / ADR in the new repo.

7. **Note the /specclaw:clarify cross-reference:** every non-determinism finding and every "No Legacy Behaviour Exists" entry is shaped like a `TARGET-GAP` or `SCOPE` question for `/specclaw:clarify`. If `.specclaw/analysis/clarifications.md` already exists, mention the linkage to the user; `/specclaw:baseline` never writes into that file itself.

## Mode B — generate harness (`--harness`)

Only run after the human has confirmed Mode A's recommended seam (Step 6 above) — do not chain straight from Mode A into `--harness` in the same turn unless the user has explicitly already confirmed it in this conversation.

1. **Collect:**
   ```bash
   specclaw-baseline harness-collect .specclaw
   ```
   Requires `.specclaw/baseline/seams.md` and `scenarios.md` to already exist (Mode A must have run). **If it exits non-zero, surface its stderr message verbatim and stop** — it means Mode A hasn't run yet. On success, this archives any prior `.specclaw/baseline/harness/` directory wholesale, creates fresh empty `harness/` and `fixtures/` directories, and emits the full, deterministic list of `GM-NNN` scenario IDs the agent must implement one-for-one.

2. **Spawn the harness agent:** `Agent` tool, `subagent_type: "baseline-designer"`, same model routing as Mode A. Pass as context:
   - The collected JSON (stdout of Step 1 — includes the `scenario_ids` checklist).
   - The resolved paths of `seams.md`, `scenarios.md`, and (if present) `codebase-report.md` for stack detection.
   - The resolved path of the repo's existing test project, if `codebase-report.md`'s `test_locations` names one, so the agent imitates its arrange pattern rather than inventing a new one.
   - **Tell the agent explicitly it is running in harness mode.**

3. The agent writes the harness project under `.specclaw/baseline/harness/` itself (or, if the detected stack isn't .NET, just a README explaining the gap) — this skill does not write any harness file itself.

4. **Present a short summary:** which stack was detected, how many `[Fact]`s were generated against how many scenario IDs (they must match), and the exact build/run commands from the generated README.

## Mode C — record capture (`--record`)

Fully deterministic — no agent involved. Run this after a human has actually executed the harness (`dotnet test` or equivalent) and fixture files exist under `.specclaw/baseline/fixtures/`, though it's also safe to run before any capture exists (it will correctly report every scenario as missing rather than failing).

1. **Run:**
   ```bash
   specclaw-baseline record .specclaw
   ```
   Requires `.specclaw/baseline/scenarios.md` to exist. **If it exits non-zero, surface its stderr message verbatim and stop.** For every `GM-NNN` scenario, checks for a `.specclaw/baseline/fixtures/<id>.json` file; if present, hashes it (sha256) and extracts its capture metadata (`captured_at`, `anchor_date`, `legacy_commit_sha`, `runtime_version`, `normalized_fields`) alongside `scenarios.md`'s own seam/rule/backlog-item fields for that ID. Archives any prior `manifest.json` before writing the new one.

2. **Present a short summary:** how many of the total scenarios have a captured fixture and how many are still missing (naming them), plus the manifest's location.

## What this command does not do

`/specclaw:baseline` never fabricates a scenario for a state the legacy app cannot actually reach — those are listed under "No Legacy Behaviour Exists" instead, not dressed up as capturable golden masters. It never claims a seam is deterministic without an explicit audit, and it never silently drops a documented business rule from the Rule Coverage Check. It never runs the legacy app, never runs the generated harness, and never writes a fixture file itself in any mode — those are always a human's action, and `--record` treats "no fixtures yet" as a normal, reportable state rather than an error.

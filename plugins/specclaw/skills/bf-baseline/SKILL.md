---
description: Design, generate, and record the golden-master harness that proves a rebuild behaves identically to the legacy app it replaces. Default mode ranks seams (pure function / stateful service / HTTP-API / data boundary / UI-excluded), declares each seam's capture layer, audits every seam for non-determinism (clocks, identity values, unstable ordering), and derives scenarios from domain-model.md's numbered business rules — writing .specclaw/baseline/seams.md and scenarios.md. Ends by asking the human to confirm the recommended seam before any harness code is generated. `--harness` identifies the legacy repo's own stack, generates a runnable capture project for it under .specclaw/baseline/harness/, and authors the project's own semantic error vocabulary in .specclaw/baseline/error-map.md — no fixed stack list, no per-stack template, and no error codes shipped in the plugin. `--record` scans .specclaw/baseline/fixtures/ for a human-produced capture, validates it hard against scenarios.md, the canonical path language, the error-outcome contract, and error-map.md, then writes manifest.json — refusing to write one at all if any fixture fails validation. Read-only with respect to source code — writes only inside .specclaw/, and never runs the legacy app or captures a fixture itself. Requires domain-model.md (run /specclaw:bf-domain first). Use after the analysis commands, alongside /specclaw:bf-clarify, before trusting a rebuild-backlog.md item as behaviorally verified.
---

# specclaw bf-baseline

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized; auto-inits using the current directory's basename as the project name).

Design, generate, and record the golden-master harness for proving behavioral equivalence between the legacy app and its rebuild. Read-only side-command — no `specclaw-validate-change` call, no `<change>` involved, matching the `analyze`/`architecture`/`domain`/`rebuild-plan`/`clarify` pattern.

This command does **not** run the legacy app and does **not** capture fixtures itself, in any mode. Designing the harness (Mode A), generating the runnable capture code (Mode B, `--harness`), and validating a capture (Mode C, `--record`) are all separate from actually *running* a capture — that step is always a human, running the generated harness's own build/test command (whatever the identified stack's conventional one is) themselves. That boundary is deliberate: capture needs a real build, possibly a real database, and human judgment about which scenarios matter.

## Mode A — design (default: no flag)

1. **Collect:**
   ```bash
   specclaw-bf-baseline collect .specclaw
   ```
   Requires `.specclaw/analysis/domain-model.md` to exist — scenarios are derived from its numbered business rules. **If it exits non-zero, surface its stderr message to the user verbatim and stop** — it names `/specclaw:bf-domain` as the command to run first. Don't retry, don't design scenarios from nothing. Also reports which supplementary documents (`codebase-report.md`, `architecture.md`, `functional-spec.md`, `rebuild-backlog.md`) are present, for the agent's own stack detection and backlog-item linkage.

2. **Archive the prior design, if any**, before writing a new one:
   ```bash
   mkdir -p .specclaw/baseline/archive
   mv .specclaw/baseline/seams.md .specclaw/baseline/archive/$(date +%Y-%m-%d-%H%M%S)-seams.md
   mv .specclaw/baseline/scenarios.md .specclaw/baseline/archive/$(date +%Y-%m-%d-%H%M%S)-scenarios.md
   ```
   Skip each `mv` independently if that specific file doesn't exist yet. This is `/specclaw:bf-baseline`'s own archive directory (`.specclaw/baseline/archive/`) — a separate document family from `.specclaw/analysis/archive/`, but the same convention: archive-then-replace, never silently overwrite.

3. **Spawn the design agent:** `Agent` tool, `subagent_type: "bf-baseline-designer"`, on the model from `config.yaml` `models.review` (default: `anthropic/claude-sonnet-4-5`) — same routing as the sibling read-only analysis agents, since this is still read-only design work, not spec/design authoring for a change. Pass as context:
   - The collected JSON (stdout of Step 1) — now including `clarifications_md`/`pending_questions_md` presence + resolved paths.
   - The resolved path of `.specclaw/analysis/domain-model.md`, plus the resolved paths of whichever supplementary documents are present, for the agent to `Read` directly.
   - **Tell the agent explicitly it is running in design mode.**

4. The agent writes `.specclaw/baseline/seams.md` and `.specclaw/baseline/scenarios.md` itself, per its own Output section — this skill does not write either file.

5. **Present a short summary** to the user: the seam ranking (which class was recommended and why, and which `seam_layer` each ranked seam declared), the capture blockers (non-determinism) found and their proposed mitigations, and the scenario count against `domain-model.md`'s numbered business rules (from the Rule Coverage Check). Mention that each scenario's declared layer is what `/specclaw:bf-replay` will later enforce the replay test against — a fixture captured at `service` and replayed through `http` is refused as a seam mismatch, not accepted as a weaker check.

6. **Ask the human to confirm the recommended seam** before generating a harness — do not proceed to `--harness` in the same turn without an explicit go-ahead. If any capture blocker was recommended for "record timestamp + injectable clock" (the highest-fidelity mitigation), remind the user this implies a design constraint / ADR in the new repo.

7. **Note the /specclaw:bf-clarify cross-reference:** every non-determinism finding and every "No Legacy Behaviour Exists" entry is shaped like a `TARGET-GAP` or `SCOPE` question for `/specclaw:bf-clarify`. If `.specclaw/analysis/clarifications.md` already exists, mention the linkage to the user; `/specclaw:bf-baseline` never writes into that file itself.

## Mode B — generate harness (`--harness`)

Only run after the human has confirmed Mode A's recommended seam (Step 6 above) — do not chain straight from Mode A into `--harness` in the same turn unless the user has explicitly already confirmed it in this conversation.

1. **Collect:**
   ```bash
   specclaw-bf-baseline harness-collect .specclaw
   ```
   Requires `.specclaw/baseline/seams.md` and `scenarios.md` to already exist (Mode A must have run). **If it exits non-zero, surface its stderr message verbatim and stop** — it means Mode A hasn't run yet. On success, this archives any prior `.specclaw/baseline/harness/` directory wholesale, creates fresh empty `harness/` and `fixtures/` directories, and emits the full, deterministic list of `GM-NNN` scenario IDs the agent must implement one-for-one.

2. **Spawn the harness agent:** `Agent` tool, `subagent_type: "bf-baseline-designer"`, same model routing as Mode A. Pass as context:
   - The collected JSON (stdout of Step 1 — includes the `scenario_ids` checklist).
   - The resolved paths of `seams.md`, `scenarios.md`, and (if present) `codebase-report.md` for stack detection.
   - The resolved path of the repo's existing test project, if `codebase-report.md`'s `test_locations` names one, so the agent imitates its arrange pattern rather than inventing a new one.
   - **Tell the agent explicitly it is running in harness mode.**

3. The agent writes the harness project under `.specclaw/baseline/harness/` itself, including `harness-manifest.json` (per `templates/CONTRACT.md`'s schema), plus `.specclaw/baseline/error-map.md` — this skill does not write any of those files itself.

   `error-map.md` is **this project's own semantic error vocabulary**: one `### CODE` heading per business condition the legacy app can reject on, each citing the legacy `file:line` that raises it. It exists because a rebuild on a different framework raises differently-named exceptions with differently-worded messages while making exactly the same decision — so the fixture records the raw exception as evidence and the *code* as the thing actually compared. The plugin ships only the empty skeleton; every code in the file is written here, at run time, against this repo. The agent extends the file on a re-run and never renames an existing code, because a code already cited by a captured fixture has to keep meaning what it meant at capture.

4. **Present a short summary:** which stack was detected (and any disagreement it flagged between manifests/extensions/`codebase-report.md`), how many test cases were generated against how many scenario IDs (they must match), how many error codes were added to `error-map.md` and how many conditions were left unmapped behind a `PQ-NNN` (those hold their scenarios at PROVISIONAL until answered), and the exact build/run commands from the generated README.

## Mode C — record capture (`--record`)

Fully deterministic — no agent involved. Run this after a human has actually executed the harness (its own generated build/test command) and fixture files exist under `.specclaw/baseline/fixtures/`, though it's also safe to run before any capture exists (it will correctly report every scenario as missing rather than failing).

1. **Run:**
   ```bash
   specclaw-bf-baseline record .specclaw
   ```
   Requires `.specclaw/baseline/scenarios.md` to exist. **If it exits non-zero, surface its stderr message verbatim and stop.** For every `GM-NNN` scenario, checks for a `.specclaw/baseline/fixtures/<id>.json` file; if present, hashes it (sha256) and extracts its capture metadata (`captured_at`, `anchor_date`, `legacy_commit_sha`, `runtime_version`, `normalized_fields`, and the recorded `outcome`/`error_code`/`threw`) alongside `scenarios.md`'s own seam/`seam_layer`/rule/backlog-item fields for that ID. Also computes each captured fixture's `status` (`VERIFIABLE` | `PROVISIONAL` | `SUPERSEDED`, per `templates/CONTRACT.md`) mechanically: `PROVISIONAL` when the scenario's own text carries the `⚠ PROVISIONAL` marker (an open pending question still blocks the rule it pins); `SUPERSEDED` when a fixture already exists but the current scenario's own text hash no longer matches what the prior manifest recorded for that ID (the scenario's definition changed under the same `GM-NNN` since capture — recapture it); otherwise `VERIFIABLE`. Stamps `manifest_schema` and the recording plugin version into the manifest, then archives any prior `manifest.json` before writing the new one.

   **`--record` is fallible by design.** It collects every problem across every scenario in one pass and, if there are any, writes no manifest **and archives nothing** — a run that produced an invalid state must not also destroy the last valid one. The five checks:

   | Check | Why it is a hard failure, not a warning |
   |---|---|
   | Every scenario declares a valid `seam_layer` (`pure-function`\|`service`\|`http`\|`persistence`) | The manifest cannot carry a layer the scenario never declared, and defaulting one is how a service-layer fixture gets replayed through HTTP. |
   | Every `normalized_fields` path resolves against that fixture's own output | A path matching zero fields normalizes nothing, so the field it names diverges on **every** replay — a silent, permanent source of noise. The error names the dead path and suggests the near-miss paths that do exist, including a camelCase rename of the same field. |
   | Every fixture output carries `outcome`, `error_code`, `threw` | Without them there is no business-level record of what the app decided, only the framework's exception surface — which is exactly what must not be compared as behaviour. |
   | A `REJECTED` fixture with a null `error_code` is marked `⚠ PROVISIONAL` | Null-with-PROVISIONAL means an agent asked; null without it means something guessed or dropped the condition. |
   | Every non-null `error_code` has a `### CODE` heading in `error-map.md` | An unmapped code is a guess wearing a decision's clothes. Verified by literal heading grep, the same discipline `sanction-check` applies to a CQ citation. |

   A fixture set captured before this contract will fail the third check with a message naming the fix: re-run `--harness`, re-capture, then `--record`. That is deliberate — there is no migration that can invent an `error_code` nobody ever recorded, and deriving one from the exception type would reintroduce the precise coupling this contract removes.

2. **Present a short summary:** how many of the total scenarios have a captured fixture and how many are still missing (naming them), the status breakdown (VERIFIABLE/PROVISIONAL/SUPERSEDED — name which fixtures are SUPERSEDED, since those need a human to recapture, not just wait on a decision), plus the manifest's location. If `record` failed instead, relay its problem list verbatim — every entry names both the fixture and the fix.

## What this command does not do

`/specclaw:bf-baseline` never fabricates a scenario for a state the legacy app cannot actually reach — those are listed under "No Legacy Behaviour Exists" instead, not dressed up as capturable golden masters. It never claims a seam is deterministic without an explicit audit, and it never silently drops a documented business rule from the Rule Coverage Check. It never runs the legacy app, never runs the generated harness, and never writes a fixture file itself in any mode — those are always a human's action, and `--record` treats "no fixtures yet" as a normal, reportable state rather than an error.

It also never ships an error code. `error-map.md` lives in **this** repo, is written by the harness agent against **this** codebase, and is the only place a `SCREAMING_SNAKE` code is ever defined; the plugin contains the document's skeleton and nothing else. Nothing in `/specclaw:bf-baseline` maps a framework's exception name to a semantic code, in either direction — that mapping is a human-reviewable decision recorded with a citation, not a string transformation, and an agent that cannot make it confidently raises a pending question instead of inventing one.

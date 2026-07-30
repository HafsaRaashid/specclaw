---
description: Turn the extraction signals scattered through .specclaw/analysis/*.md (Inference:, Mechanical:, Named Gaps, hedging language, cross-doc conflicts, unexercised code paths) into a numbered, human-answerable question set — .specclaw/analysis/clarifications.md — classified as DECISION, DATA, SCOPE, DEFECT, MECHANICAL, TARGET-GAP, or CONFLICT, each with options and a proposed default. Re-running preserves every existing question's ID and any answer already typed in; only genuinely new questions are appended, never renumbered. Run with `--resolve` to promote answered questions into a clean, pinnable .specclaw/analysis/decisions.md decision record, with ADR-promotion candidates flagged. Read-only with respect to source code — writes only inside .specclaw/. Use after /specclaw:analyze, /specclaw:architecture, /specclaw:domain, and/or /specclaw:rebuild-plan, before trusting their inferences as grounding for a rebuild.
---

# specclaw clarify

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized; auto-inits using the current directory's basename as the project name).

Turn the implicit uncertainty in `.specclaw/analysis/*.md` into an explicit, numbered decision record. Read-only side-command — no `specclaw-validate-change` call, no `<change>` involved, matching the `analyze`/`architecture`/`domain`/`rebuild-plan` pattern.

**Two modes**, chosen by whether the user's invocation includes `--resolve`:

## Mode A — extract (default: no flag)

1. **Collect:**
   ```bash
   specclaw-clarify collect .specclaw
   ```
   Reports which of the five known analysis documents (`codebase-report.md`, `architecture.md`, `domain-model.md`, `functional-spec.md`, `rebuild-backlog.md`) are present, and — if `clarifications.md` already exists — the next free `CQ-NNN` ID plus a de-dup hint list of existing questions' IDs/titles/sources. **If it exits non-zero, surface its stderr message to the user verbatim and stop** — it means none of the five documents exist yet; don't retry, don't fabricate a question set from nothing.

2. **Spawn the extraction agent:** `Agent` tool, `subagent_type: "clarify-extractor"`, on the model from `config.yaml` `models.review` (default: `anthropic/claude-sonnet-4-5`) — same routing as the sibling read-only analysis agents (`codebase-analyst`, `architecture-analyst`, `domain-analyst`, `rebuild-planner`), since this is still read-only analysis of already-written documents. Pass as context:
   - The collected JSON (stdout of Step 1).
   - The resolved paths of every present analysis document, for the agent to `Read` directly.
   - **Tell the agent explicitly it is running in extract mode**: draft only new questions, numbering sequentially from the JSON's `next_id`, and write them to a transient draft file at `.specclaw/analysis/.clarify-draft.md` via its own `Write` tool, in the exact per-question block format documented in `templates/clarifications.md`'s HTML comment (and in its own agent instructions). It must not read or attempt to edit the existing `clarifications.md` file itself — `render` (next step) owns merging.

3. **Render:**
   ```bash
   specclaw-clarify render .specclaw .specclaw/analysis/.clarify-draft.md
   ```
   Archives the prior `clarifications.md` (if any — same `.specclaw/analysis/archive/` directory the other analysis commands use), merges its preserved blocks with the agent's new draft, re-sorts (blocking first, then by type in taxonomy order), recomputes the summary header, writes `.specclaw/analysis/clarifications.md`, and deletes the draft file. **If it exits non-zero, surface its stderr message to the user verbatim and stop.**

4. **Present a short summary:** total question count, count by type, count blocking, count unanswered, and — if any — which of the five source documents were missing from this sweep (from Step 1's `docs_missing`).

## Mode B — resolve (`--resolve`)

1. **Collect:**
   ```bash
   specclaw-clarify resolve-collect .specclaw
   ```
   Requires `clarifications.md` to already exist (fails with a message to run Mode A first, otherwise) and at least one answered question. Splits questions into answered/unanswered by whether `**Answer:**` is filled in. **If it exits non-zero, surface its stderr message to the user verbatim and stop.**

2. **Spawn the resolution agent:** `Agent` tool, `subagent_type: "clarify-extractor"`, same model routing as Mode A. Pass as context:
   - The collected JSON (stdout of Step 1 — an ID map only, not question content).
   - The resolved path of `.specclaw/analysis/clarifications.md`, for the agent to `Read` directly.
   - **Tell the agent explicitly it is running in resolve mode**: for every ID in `answered_ids` only, judge whether the decision is significant enough to be promoted to an ADR in the new repo, and write one pipe-delimited line per answered ID (`id|yes-or-no|suggested_adr_title|one_line_rationale`) to a transient file at `.specclaw/analysis/.clarify-adr.txt` via its own `Write` tool. It must not re-derive or restate the decisions themselves — that part is mechanical and owned by `resolve-render`.

3. **Render:**
   ```bash
   specclaw-clarify resolve-render .specclaw .specclaw/analysis/.clarify-adr.txt
   ```
   Archives the prior `decisions.md` (if any), mechanically transcribes every answered question into a decision entry, splices in the agent's ADR-candidate annotations, lists unanswered questions, writes `.specclaw/analysis/decisions.md`, and deletes the transient ADR file. **If it exits non-zero, surface its stderr message to the user verbatim and stop.**

4. **Present a short summary:** how many decisions were recorded, which (if any) are flagged as ADR promotion candidates, and which questions remain unanswered.

5. **Remind the user** to `git add .specclaw/analysis/clarifications.md .specclaw/analysis/decisions.md`, and to consider adding `decisions.md` to `config.yaml`'s `context.pin` (raising `max_lines` accordingly) so downstream `/specclaw:propose`, `/specclaw:plan`, and `/specclaw:build` cite it as grounding — same recipe `docs/rebuild-workflow.md` documents for the other analysis outputs, since `context` discovery enumerates via `git ls-files`.

## What this command does not do

`/specclaw:clarify` never guesses an answer on the human's behalf — every question it drafts carries a **Proposed default**, never a silent assumption, and a question with no discoverable answer stays a flagged `DATA`, `DECISION`, or `TARGET-GAP` question, never an invented fact. It does not call `/specclaw:propose` or any other lifecycle command, and once a human has filled in a question's `**Answer:**`/`**Decided by:**`/`**Date:**` fields, no later run of either mode ever edits them — only `resolve`'s mechanical transcription reads them, and only to copy them forward into `decisions.md`.

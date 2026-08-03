---
description: Turn the extraction signals scattered through .specclaw/analysis/*.md (Inference:, Mechanical:, Named Gaps, hedging language, cross-doc conflicts, unexercised code paths) into a numbered, human-answerable question set — .specclaw/analysis/clarifications.md — classified as DECISION, DATA, SCOPE, DEFECT, MECHANICAL, TARGET-GAP, or CONFLICT, each with options and a proposed default. Also asks the standard bank of shaping questions every rebuild needs (target platform, database, auth, hosting, ...) that no amount of code extraction can surface, plus any per-repo custom questions from .specclaw/analysis/custom-questions.md — merged into the same file, applicability-checked and pre-answered-detected against this repo's own ADRs/decisions. Re-running preserves every existing question's ID (in all three families) and any answer already typed in; only genuinely new questions are appended, never renumbered. Run with `--resolve` to promote answered questions from every family into a clean, pinnable .specclaw/analysis/decisions.md decision record, with ADR-promotion candidates flagged. Run with `--bank-only` to ask just the standard/custom questions without extraction — useful right after /specclaw:analyze, before the shaping questions get answered as ADRs. Read-only with respect to source code — writes only inside .specclaw/. Use after /specclaw:analyze, /specclaw:architecture, /specclaw:domain, and/or /specclaw:rebuild-plan, before trusting their inferences as grounding for a rebuild.
---

# specclaw clarify

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized; auto-inits using the current directory's basename as the project name).

Turn the implicit uncertainty in `.specclaw/analysis/*.md`, plus the shaping questions no amount of code extraction can surface, into one explicit, numbered decision record. Read-only side-command — no `specclaw-validate-change` call, no `<change>` involved, matching the `analyze`/`architecture`/`domain`/`rebuild-plan` pattern.

**Three question families** share one `clarifications.md` and one `--resolve` pipeline — see `templates/clarifications.md`'s HTML comment for the authoritative field-by-field breakdown:

- **`CQ-NNN`** — extracted from `.specclaw/analysis/*.md` by the extraction agent (unchanged from before this upgrade). Allocated per-repo, in extraction order.
- **`SQ-NNN`** — the standard bank (`references/clarify-standard-questions.md`, shipped with the plugin). IDs are **fixed by the bank file itself**, not allocated per-repo — `SQ-001` means "target platform" in every project. `Type`/`Blocking`/`Options`/`Proposed default` are spliced in verbatim from the bank file by `render`, identical everywhere; only `Finding`/`Why it matters`/`Source`/`Answer` are project-specific.
- **`UQ-NNN`** — per-repo custom questions from `.specclaw/analysis/custom-questions.md`, ingested by `render` directly (no agent involved). Allocated per-repo, in file order. A starter example lives at `templates/custom-questions.md` — copy it into the target repo and edit there; `/specclaw:clarify` never creates or writes this file itself, only reads it. **De-duplicated by each question's original heading text**, recorded in its `Source` field — editing an already-ingested heading's wording later does **not** retroactively rewrite the rendered `UQ-NNN`; it reads as a brand-new question with a new ID. Edit the rendered question in `clarifications.md` instead if you want to change it.

**Two modes**, chosen by whether the user's invocation includes `--resolve`. Mode A additionally accepts `--bank-only`.

## Mode A — extract (default: no flag)

Runs both layers every time unless `--bank-only` is passed: extraction (`CQ-NNN`, unchanged) and the bank/custom layer (`SQ-NNN`/`UQ-NNN`, new).

1. **Collect:**
   ```bash
   specclaw-clarify collect .specclaw [--bank-only]
   ```
   Reports which of the five known analysis documents (`codebase-report.md`, `architecture.md`, `domain-model.md`, `functional-spec.md`, `rebuild-backlog.md`) are present, and — if `clarifications.md` already exists — the next free `CQ-NNN` ID plus a de-dup hint list of existing questions' IDs/titles/sources. **If it exits non-zero (and `--bank-only` was not passed), surface its stderr message to the user verbatim and stop** — it means none of the five documents exist yet; don't retry, don't fabricate a question set from nothing. With `--bank-only`, this gate is skipped entirely — the bank/custom layer needs no analysis documents at all, which is exactly why `--bank-only` is the natural thing to run immediately after `/specclaw:analyze`, before `/specclaw:architecture` or `/specclaw:domain` have even run: several bank answers (target platform, database engine, hosting) should become ADRs that then constrain everything the later analysers and `/specclaw:rebuild-plan` produce.

   The same JSON also reports `bank_path` (resolved), `new_sq_ids` (bank ids this project has never seen — the **only** ones the bank agent evaluates; every other bank id was already rendered or marked Not applicable in a prior run and is never re-evaluated), and whether `custom-questions.md`/`.specclaw/adr/`/`decisions.md` are present.

2. **Spawn the extraction agent** (skip this step entirely if `--bank-only`): `Agent` tool, `subagent_type: "clarify-extractor"`, on the model from `config.yaml` `models.review` (default: `anthropic/claude-sonnet-4-5`) — same routing as the sibling read-only analysis agents (`codebase-analyst`, `architecture-analyst`, `domain-analyst`, `rebuild-planner`), since this is still read-only analysis of already-written documents. Pass as context:
   - The collected JSON (stdout of Step 1).
   - The resolved paths of every present analysis document, for the agent to `Read` directly.
   - **Tell the agent explicitly it is running in extract mode**: draft only new questions, numbering sequentially from the JSON's `next_id`, and write them to a transient draft file at `.specclaw/analysis/.clarify-draft.md` via its own `Write` tool, in the exact per-question block format documented in `templates/clarifications.md`'s HTML comment (and in its own agent instructions). It must not read or attempt to edit the existing `clarifications.md` file itself — `render` (next step) owns merging.

3. **Spawn the bank agent** (skip only if Step 1's `new_sq_ids` is empty): same `Agent` tool, `subagent_type: "clarify-extractor"`, same model routing — a separate invocation from Step 2, since its inputs differ (the bank file, ADRs, decisions.md, rather than the extraction signals). Pass as context:
   - The collected JSON (stdout of Step 1) — specifically `bank_path`, `new_sq_ids`, `adr_dir`, `decisions_md`, `docs_present`.
   - The resolved paths of every present analysis document, of every file under `.specclaw/adr/` (if present), and of `decisions.md` (if present), for the agent to `Read` directly.
   - **Tell the agent explicitly it is running in bank mode**: for every id in `new_sq_ids` only, judge applicability against that bank entry's own condition, check for a pre-existing answer (an ADR whose own `Status:` field is literally `accepted` — never a `proposed` ADR's undecided recommendation — or a matching `decisions.md` entry), contextualise the wording with this repo's facts, and write the result to `.specclaw/analysis/.clarify-bank-draft.md` via its own `Write` tool, in the exact format documented in its own agent instructions (`NOT-APPLICABLE: SQ-NNN | reason` lines for inapplicable ids; narrow `### SQ-NNN` blocks — Finding/Why it matters/Source/Answer only, never Type/Blocking/Options/Proposed default — for applicable ones).

4. **Render:**
   ```bash
   specclaw-clarify render .specclaw <cq_draft_or_-> <bank_draft_or_->
   ```
   Pass `-` for whichever draft its producing step was skipped (`--bank-only` → `-` for the CQ draft; `new_sq_ids` empty → `-` for the bank draft). Archives the prior `clarifications.md` (if any — same `.specclaw/analysis/archive/` directory the other analysis commands use), merges preserved blocks from every family with the new drafts, splices in the bank file's own `Type`/`Blocking`/`Options`/`Proposed default` for every new `SQ-NNN`, ingests any new entries from `custom-questions.md` into `UQ-NNN` blocks in-line (tolerant of missing `Type`/`Blocking`/`Options` — defaults rather than errors), re-sorts each family independently (blocking first, then by type in taxonomy order), recomputes the summary header (now counting `CQ`/`SQ`/`UQ` separately), writes `.specclaw/analysis/clarifications.md` in section order **Standard → Custom → Extracted → Not applicable**, and deletes whichever draft file(s) were passed. **If it exits non-zero, surface its stderr message to the user verbatim and stop.**

5. **Present a short summary:** total question count broken down by family (Extracted/Standard/Custom), count by type, count blocking, count unanswered, which standard-bank questions were pre-answered (and from which ADR/decision), which were judged not applicable (and why), and — if any — which of the five source documents were missing from this sweep (from Step 1's `docs_missing`).

## Mode B — resolve (`--resolve`)

1. **Collect:**
   ```bash
   specclaw-clarify resolve-collect .specclaw
   ```
   Requires `clarifications.md` to already exist (fails with a message to run Mode A first, otherwise) and at least one answered question. Splits questions **from all three families** into answered/unanswered by whether `**Answer:**` is filled in. **If it exits non-zero, surface its stderr message to the user verbatim and stop.**

2. **Spawn the resolution agent:** `Agent` tool, `subagent_type: "clarify-extractor"`, same model routing as Mode A. Pass as context:
   - The collected JSON (stdout of Step 1 — an ID map only, not question content).
   - The resolved path of `.specclaw/analysis/clarifications.md`, for the agent to `Read` directly.
   - **Tell the agent explicitly it is running in resolve mode**: for every ID in `answered_ids` only — whichever family it belongs to — judge whether the decision is significant enough to be promoted to an ADR in the new repo, and write one pipe-delimited line per answered ID (`id|yes-or-no|suggested_adr_title|one_line_rationale`) to a transient file at `.specclaw/analysis/.clarify-adr.txt` via its own `Write` tool. It must not re-derive or restate the decisions themselves — that part is mechanical and owned by `resolve-render`.

3. **Render:**
   ```bash
   specclaw-clarify resolve-render .specclaw .specclaw/analysis/.clarify-adr.txt
   ```
   Archives the prior `decisions.md` (if any), mechanically transcribes every answered question from every family into a decision entry tagged with its origin **Family** (`Extracted` | `Standard bank` | `Custom (per-repo)`, derived from the ID prefix), splices in the agent's ADR-candidate annotations, lists unanswered questions, writes `.specclaw/analysis/decisions.md`, and deletes the transient ADR file. **If it exits non-zero, surface its stderr message to the user verbatim and stop.**

4. **Present a short summary:** how many decisions were recorded (broken down by family), which (if any) are flagged as ADR promotion candidates, and which questions remain unanswered.

5. **Remind the user** to `git add .specclaw/analysis/clarifications.md .specclaw/analysis/decisions.md` (and `.specclaw/analysis/custom-questions.md`, if they added one), and to consider adding `decisions.md` to `config.yaml`'s `context.pin` (raising `max_lines` accordingly) so downstream `/specclaw:propose`, `/specclaw:plan`, and `/specclaw:build` cite it as grounding — same recipe `docs/rebuild-workflow.md` documents for the other analysis outputs, since `context` discovery enumerates via `git ls-files`.

## What this command does not do

`/specclaw:clarify` never guesses an answer on the human's behalf — every question it drafts carries a **Proposed default**, never a silent assumption, and a question with no discoverable answer stays a flagged `DATA`, `DECISION`, or `TARGET-GAP` question, never an invented fact. It does not call `/specclaw:propose` or any other lifecycle command, and once a human has filled in a question's `**Answer:**`/`**Decided by:**`/`**Date:**` fields, no later run of either mode ever edits them — only `resolve`'s mechanical transcription reads them, and only to copy them forward into `decisions.md`. It never marks a standard-bank question pre-answered from a `proposed` ADR's undecided recommendation — only an `accepted` ADR (or an existing `decisions.md` entry) counts, and a `proposed` ADR is cited as related context on the still-open question instead. It never re-evaluates a standard-bank question's applicability once rendered or marked Not applicable — that verdict doesn't flip-flop across runs. It never retroactively rewrites an already-ingested custom question if its heading is edited later in `custom-questions.md` — that file is a one-way feed into `clarifications.md`, which becomes the system of record.

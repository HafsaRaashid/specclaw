---
description: Read the four .specclaw/analysis/*.md documents (codebase-report, architecture, domain-model, functional-spec) — plus, when present, decisions.md, clarifications.md, and .specclaw/baseline/manifest.json/scenarios.md — and write or refresh an ordered .specclaw/analysis/rebuild-backlog.md: the application decomposed into individually-proposable features, sequenced by dependency and readiness, each carrying its acceptance basis, a computed Gate (blocked/open-questions/clear against unanswered clarify questions) and Verification state (verifiable/pending-capture/unverifiable/no-baseline-data against baseline fixtures), and a "what a human still needs to supply" callout. First-ever run generates from scratch; every subsequent run requires `--refresh`, which recomputes Gate/Verification for every item, applies new decisions, and never renumbers, deletes, or disturbs a human-added status note. Read-only: no TTY or credential prompts, no lifecycle gate, creates nothing in changes/, calls no lifecycle command. Use after running /specclaw:analyze, /specclaw:architecture, and /specclaw:domain — and, ideally, /specclaw:clarify and /specclaw:baseline — when you want an ordered, decision-aware list of what to /specclaw:propose to rebuild an existing (possibly legacy) app in a new stack.
---

# specclaw rebuild-plan

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized; auto-inits using the current directory's basename as the project name).

Turn the four analysis documents — plus, when present, `decisions.md`, `clarifications.md`, and the baseline outputs (`manifest.json`/`scenarios.md`) — into a living, ID-stable rebuild backlog. Read-only side-command — no `specclaw-validate-change` call, no `<change>` involved, matching the `analyze`/`architecture`/`domain`/`clarify`/`baseline` pattern.

Determine the invocation mode from the user's message: **refresh mode** if it contains `--refresh`, **default mode** otherwise.

## Step 1 — Collect

```bash
specclaw-rebuild-collect collect .specclaw [--refresh]
```

Pass `--refresh` only in refresh mode. This single step:

- Checks that all four `.specclaw/analysis/*.md` documents exist. **If it exits non-zero for this reason, surface its stderr message to the user verbatim and stop** — it names exactly which document(s) are missing and which command produces each. Don't retry, don't attempt a partial backlog from partial input.
- **If `.specclaw/analysis/rebuild-backlog.md` already exists and `--refresh` was not passed, it exits non-zero with a refusal message** — surface that message verbatim and stop. Do not delete or archive the file yourself; tell the user to re-run with `--refresh`, or to archive/delete it manually first if they genuinely want a from-scratch run.
- Otherwise emits one JSON object to stdout: the four documents' paths/line counts; which optional inputs are present (`decisions.md`, `clarifications.md`, `.specclaw/baseline/manifest.json`, `.specclaw/baseline/scenarios.md`) with their resolved paths; every `clarifications.md` question's `id`/`type`/`blocking`/`answered`/`rules`/`items` (ID-level facts only, no prose); which `CQ-###` ids have a recorded decision; the `scenarios.md` roster and `manifest.json` fixtures (`id`/`rules`/`item`); whether a "No Legacy Behaviour Exists" section is present; and — in refresh mode — every existing `BL-###` item's `id`/`title`/`depends_on`/`rules`/`status`/prior Gate/Verification. It also reports the next free `BL-###` id.

## Step 2 — Spawn the planning agent

`Agent` tool, `subagent_type: "rebuild-planner"`, on the model from `config.yaml` `models.review` (default: `anthropic/claude-sonnet-4-5`) — same model family as its sibling analysis agents, since this is still read-only analysis of already-written documents, not spec/design authoring for a change. Pass as context:

- The collected JSON from Step 1.
- The resolved paths of the four analysis documents, plus whichever optional inputs are present (from `optional_inputs` in the JSON), for the agent to `Read` directly.
- **Tell the agent explicitly which mode it is running**: `first-run` (the JSON's `mode` field will read `"first-run"`) or `refresh` (`"refresh"`).
- In refresh mode, also pass the resolved path of the *existing* `.specclaw/analysis/rebuild-backlog.md`, so the agent can read what's already there and avoid re-drafting anything it doesn't need to touch.

The agent writes **a draft file**, `.specclaw/analysis/.rebuild-plan-draft.md` — never the final `rebuild-backlog.md` itself. See `agents/rebuild-planner.md` for exactly what belongs in it.

## Step 3 — Render

```bash
specclaw-rebuild-collect render .specclaw .specclaw/analysis/.rebuild-plan-draft.md
```

Archives the prior `rebuild-backlog.md` (if any — same `.specclaw/analysis/archive/` directory `analyze`/`architecture`/`domain`/`clarify` already use), merges the draft with every preserved existing item, computes Gate and Verification for every active item from scratch (never trusting a stale value), computes dependency-rank-then-readiness ordering, renders struck items as one-line tombstones and deferred items into their own section, computes the refresh change report by diffing against the prior file's own stored Gate/Verification lines, and writes `.specclaw/analysis/rebuild-backlog.md`. Deletes the draft file on success. **If it exits non-zero, surface its stderr message to the user verbatim and stop.**

## Step 4 — Present a summary

- **First run:** backlog item count, a one-line note on the sequencing rationale, any Coverage Check exclusions, and the status header's counts (Gate/Verification) and recommended next item.
- **Refresh:** the rendered Change Report section verbatim — items newly unblocked, newly verifiable, struck/deferred/revised/added, and the recommended next item.

**Remind the user to `git add .specclaw/analysis/*.md`** (including the refreshed `rebuild-backlog.md`) if these files aren't already tracked — grounding the lifecycle in them via `context.pin` only works once `git ls-files` can see them, since `specclaw-discover-context` enumerates candidates that way. See `docs/rebuild-workflow.md` for the full pin/grounding recipe.

## What this command does not do

`/specclaw:rebuild-plan` creates **nothing** under `.specclaw/changes/` and calls **no** lifecycle skill or script — it only reads its input documents and writes one file. The operator still runs `/specclaw:propose "<item>"` themselves for each backlog entry, exactly as they would for any other feature idea. This command does not, and should not, ever be extended to auto-invoke `/specclaw:propose` — that would silently reintroduce the lifecycle coupling this command is deliberately designed to avoid.

The backlog is an acceptance basis plus a computed Gate/Verification state — it does not, and cannot, replace golden-master outputs or human-supplied external-format/DLL/COM semantics for verifying a truly faithful rebuild. A `VERIFIABLE` item has a matching captured fixture; it does not mean the fixture's assertions were exhaustive. See each item's "Verification inputs needed" field, its computed `**Verification:**` line, and `docs/rebuild-workflow.md`'s Fidelity limitation section.

`/specclaw:rebuild-plan` never regenerates an existing backlog from scratch on a bare re-run, never renumbers a `BL-###` id, never deletes a struck or deferred item, and never touches a `**Status notes (human-added):**` block a human wrote into an item — those are the one hard invariant this command protects across every `--refresh`.

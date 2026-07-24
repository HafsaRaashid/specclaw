---
description: Read the four .specclaw/analysis/*.md documents (codebase-report, architecture, domain-model, functional-spec) and write an ordered .specclaw/analysis/rebuild-backlog.md — the application decomposed into individually-proposable features, sequenced by dependency, each carrying its acceptance basis and a "what a human still needs to supply" callout. Read-only: no TTY or credential prompts, no lifecycle gate, creates nothing in changes/, calls no lifecycle command. Use after running /specclaw:analyze, /specclaw:architecture, and /specclaw:domain, when you want an ordered list of what to /specclaw:propose to rebuild an existing (possibly legacy) app in a new stack.
---

# specclaw rebuild-plan

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized; auto-inits using the current directory's basename as the project name).

Turn the four existing analysis documents into an ordered rebuild backlog. Read-only side-command — no `specclaw-validate-change` call, no `<change>` involved, matching the `analyze`/`architecture`/`domain`/`patterns`/`status` pattern.

1. **Resolve and collect:**
   ```bash
   specclaw-rebuild-collect collect .specclaw
   ```
   Checks that all four `.specclaw/analysis/*.md` documents exist. **If it exits non-zero, surface its stderr message to the user verbatim and stop** — it names exactly which document(s) are missing and which command (`/specclaw:analyze`, `/specclaw:architecture`, or `/specclaw:domain`) produces each. Don't retry, don't attempt a partial backlog from partial input.

2. **Archive the prior backlog, if any**, before writing a new one:
   ```bash
   mkdir -p .specclaw/analysis/archive
   mv .specclaw/analysis/rebuild-backlog.md .specclaw/analysis/archive/$(date +%Y-%m-%d-%H%M%S)-rebuild-backlog.md
   ```
   Skip this step if `.specclaw/analysis/rebuild-backlog.md` doesn't exist yet. This is the same shared archive directory `analyze`/`architecture`/`domain` already use.

3. **Spawn the planning agent:** `Agent` tool, `subagent_type: "rebuild-planner"`, on the model from `config.yaml` `models.review` (default: `anthropic/claude-sonnet-4-5`) — same model family as its sibling analysis agents (`codebase-analyst`, `architecture-analyst`, `domain-analyst`), since this is still read-only analysis of already-written documents, not spec/design authoring for a change. Pass as context:
   - The collected JSON (stdout of Step 1 — an existence/line-count map, not document content).
   - The four resolved document paths (`.specclaw/analysis/codebase-report.md`, `architecture.md`, `domain-model.md`, `functional-spec.md`) for the agent to `Read` directly.

4. The agent writes `.specclaw/analysis/rebuild-backlog.md` itself, per its own Output section — this skill does not write the file.

5. **Present a short summary** to the user: backlog item count, a one-line note on the sequencing rationale, and any Coverage Check exclusions the agent flagged. **Remind the user to `git add .specclaw/analysis/*.md`** (including the new `rebuild-backlog.md`) if these files aren't already tracked — grounding the lifecycle in them via `context.pin` only works once `git ls-files` can see them, since `specclaw-discover-context` enumerates candidates that way. See `docs/rebuild-workflow.md` for the full pin/grounding recipe.

## What this command does not do

`/specclaw:rebuild-plan` creates **nothing** under `.specclaw/changes/` and calls **no** lifecycle skill or script — it only reads the four analysis documents and writes one new file. The operator still runs `/specclaw:propose "<item>"` themselves for each backlog entry, exactly as they would for any other feature idea. This command does not, and should not, ever be extended to auto-invoke `/specclaw:propose` — that would silently reintroduce the lifecycle coupling this command is deliberately designed to avoid.

The backlog is an acceptance basis, not proof of behavioral equivalence with the original system — it does not, and cannot, replace golden-master outputs or human-supplied external-format/DLL/COM semantics for verifying a truly faithful rebuild. See each item's "Verification inputs needed" field and `docs/rebuild-workflow.md`'s Fidelity limitation section.

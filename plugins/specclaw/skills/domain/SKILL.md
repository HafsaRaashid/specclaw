---
description: Produce a domain and functional-spec view of an existing/legacy codebase — business entities, relationships, rules, and enumerations (domain-model.md) plus capabilities, workflows, UI inventory, and named gaps (functional-spec.md) — grounded in parsed forms (.dfm/.xaml), type/const declarations, and validation-routine candidates. Works on any language or stack — Delphi/Object Pascal and .NET get first-class UI/form parsing, other stacks still get entities/rules/enumerations. Read-only: no TTY or credential prompts, no lifecycle gate. Use when you need to understand what a codebase's business domain actually is and what a user can do with it — onboarding, planning a refactor, or before proposing a change in an unfamiliar repo.
---

# specclaw domain

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized; auto-inits using the current directory's basename as the project name).

Analyze an existing codebase's business domain and user-facing functionality, writing `.specclaw/analysis/domain-model.md` and `.specclaw/analysis/functional-spec.md`. Read-only side-command — no `specclaw-validate-change` call, no `<change>` involved, matching the `analyze`/`architecture`/`patterns`/`status` pattern.

1. **Resolve and collect:**
   ```bash
   specclaw-domain-collect collect .specclaw [path]
   ```
   `[path]` defaults to the repository root when omitted. The script delegates to `specclaw-analyze-codebase collect` for path validation, manifests, `dependency_graph`, and `discovered_docs`, then adds domain-specific facts (`forms`, `xaml_forms`, `other_ui_files`, `handler_implementations`, `main_form_hint`, `type_declarations`, `const_declarations`, `validation_routine_candidates`). **If it exits non-zero, surface its stderr message to the user verbatim and stop** — don't retry, don't guess a different path. This validation already lives inside the delegated call to `specclaw-analyze-codebase collect`; do not reimplement it here.

2. **Archive both prior documents, if they exist**, before writing new ones:
   ```bash
   mkdir -p .specclaw/analysis/archive
   mv .specclaw/analysis/domain-model.md .specclaw/analysis/archive/$(date +%Y-%m-%d-%H%M%S)-domain-model.md
   mv .specclaw/analysis/functional-spec.md .specclaw/analysis/archive/$(date +%Y-%m-%d-%H%M%S)-functional-spec.md
   ```
   Skip each `mv` independently if that specific file doesn't exist yet — one may exist without the other on an unusual prior run. This is the same shared archive directory `analyze`/`architecture` already use — all document types land in `.specclaw/analysis/archive/`, distinguished by filename.

3. **Spawn the analysis agent:** `Agent` tool, `subagent_type: "domain-analyst"`, on the model from `config.yaml` `models.review` (default: `anthropic/claude-sonnet-4-5`). Pass as context:
   - The collected JSON (stdout of Step 1).
   - The resolved target path.

4. The agent writes `.specclaw/analysis/domain-model.md` and `.specclaw/analysis/functional-spec.md` itself, per its own Output section — this skill does not write either file.

5. **Present a short summary** to the user: the path analyzed, entity/rule/capability counts, and any Named Gaps the agent flagged.

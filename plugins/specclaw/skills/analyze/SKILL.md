---
description: Analyze an existing (possibly legacy) codebase and write a grounded `.specclaw/analysis/codebase-report.md` covering tech stack, dependencies, architecture, domain, and risks. Works on any language or stack — Node, .NET, Java, Go, Rust, Python, Delphi/Object Pascal, or none of the above — not just Node/.NET. Read-only: no TTY or credential prompts, no lifecycle gate. Use when onboarding to an unfamiliar or legacy repo, or before proposing a change in one.
---

# specclaw analyze

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized; auto-inits using the current directory's basename as the project name).

Analyze an existing codebase and write `.specclaw/analysis/codebase-report.md`. Read-only side-command — no `specclaw-validate-change` call, no `<change>` involved, matching the `patterns`/`status` pattern.

1. **Resolve and collect:**
   ```bash
   specclaw-analyze-codebase collect .specclaw [path]
   ```
   `[path]` defaults to the repository root when omitted. The script itself validates that `[path]` exists, resolves inside the repository, and is not `.specclaw` itself or nested inside it. **If it exits non-zero, surface its stderr message to the user verbatim and stop** — don't retry, don't guess a different path.

2. **Migrate a pre-upgrade report, if present**, before archiving: if `.specclaw/codebase-report.md` (the old path) exists and `.specclaw/analysis/codebase-report.md` (the new path) does not yet exist, move it into the new archive location so it is never orphaned:
   ```bash
   mkdir -p .specclaw/analysis/archive
   mv .specclaw/codebase-report.md .specclaw/analysis/archive/$(date +%Y-%m-%d-%H%M%S)-codebase-report.md
   ```
   Skip this step once the old path is gone — on every run after the first post-upgrade run for a given project, this is a no-op.

3. **Archive the prior report, if any**, before writing a new one:
   ```bash
   mkdir -p .specclaw/analysis/archive
   mv .specclaw/analysis/codebase-report.md .specclaw/analysis/archive/$(date +%Y-%m-%d-%H%M%S)-codebase-report.md
   ```
   Skip this step if `.specclaw/analysis/codebase-report.md` doesn't exist yet.

4. **Spawn the analysis agent:** `Agent` tool, `subagent_type: "codebase-analyst"`, on the model from `config.yaml` `models.review` (default: `anthropic/claude-sonnet-4-5`). Pass as context:
   - The collected JSON (stdout of Step 1).
   - The resolved target path.

5. The agent writes `.specclaw/analysis/codebase-report.md` itself, per its own Output section — this skill does not write the file.

6. **Present a short summary** to the user: the path analyzed, which report sections were written, and any low-confidence flags (`Inference (low confidence): ...`) the report surfaced.

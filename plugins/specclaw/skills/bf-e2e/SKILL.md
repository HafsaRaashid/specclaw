---
description: Automatically detects the target application's platform (Web/Desktop/Mobile/Hybrid/Embedded) and stack, dynamically selects the most effective E2E testing framework for it with a stated justification, and generates a Page Object Model plus a runnable E2E test script that asserts structural equality against SpecClaw Golden Master fixtures (.specclaw/baseline/fixtures/GM-*.json). No fixed platform/language/framework list — works on whatever the target codebase actually is. Read-only with respect to application source — writes only generated test/page-object files. Use after /specclaw:bf-baseline has captured golden-master fixtures, when you need runnable E2E coverage proving the (re)built app matches the legacy behaviour.
---

# specclaw bf-e2e

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized).

Generate E2E test coverage for a target application, driven by a universal E2E automation architect agent. Read-only side-command — no `specclaw-validate-change` call, no `<change>` involved, matching the `analyze`/`bf-architecture`/`bf-baseline` pattern.

1. **Resolve the target path.** If the user's message names a path, use it (validate it exists and is inside the repo). Otherwise default to the repository root.

2. **Check for golden-master fixtures:**
   ```bash
   ls .specclaw/baseline/fixtures/GM-*.json 2>/dev/null
   ```
   This is a soft input, not a hard requirement — if empty, proceed anyway (the agent generates tests from the described flow instead and flags the gap; see its Task 4). If present, resolve the full list of fixture filenames to pass along.

3. **Check for prior context** (soft — pass paths if present, don't fail if absent):
   ```bash
   [ -f .specclaw/analysis/codebase-report.md ] && echo present
   [ -f .specclaw/baseline/scenarios.md ] && echo present
   ```

4. **Spawn the automation agent:** `Agent` tool, `subagent_type: "bf-e2e-architect"`, on the model from `config.yaml` `models.coding` (default: `anthropic/claude-sonnet-5`) — this agent writes real, runnable test code, the same routing as build's coding agents, not the read-only analysis agents. Pass as context:
   - The resolved target path.
   - The resolved `.specclaw/baseline/fixtures/` path and the list of `GM-*.json` filenames found in Step 2 (empty list is valid input).
   - The resolved paths of `codebase-report.md` and `scenarios.md`, if present (Step 3).
   - Any flow/feature description the user included in their invocation of this skill.

5. The agent detects platform/stack, selects the E2E framework, and writes the page object(s) and test script(s) itself, per its own Output section — this skill does not write any file itself.

6. **Relay the agent's full response to the user as-is** — it already carries the required Detection Summary → Setup/Execution Commands → Page Object File(s) → SpecClaw Test Script structure. Do not summarize it away; the human needs the actual generated code and commands, not a paraphrase.

## What this command does not do

`/specclaw:bf-e2e` never assumes a platform, language, or E2E framework in advance — every detection and every tool selection is derived from evidence the agent gathers from the target repo itself, in that run. It never modifies existing application source files, and it never fabricates an expected value for a fixture assertion — a flow that cannot be driven through the available UI/API surface is reported as a gap, not silently skipped.

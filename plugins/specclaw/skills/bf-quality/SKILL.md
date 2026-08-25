---
description: Measure the code quality of an existing/legacy codebase and write a machine-readable .specclaw/analysis/quality.json plus a client-curatable quality-report.md — per-module rollups of cyclomatic complexity, function length, duplication and file length, each classified against configurable thresholds, with every metric that could not be computed recorded as NOT-MEASURED and a machine-readable reason (tool_missing / language_unsupported / parse_error) rather than estimated. Hotspots are registered as permanent QI-### ids that survive re-runs and flip to resolved instead of being deleted. Bash computes every status, severity and rollup; the agent only narrates them. Fully optional and advisory: it blocks nothing, changes no other command's behaviour, and exits 0 even on HIGH findings. `--target <path>` measures a rebuilt codebase instead; `--compare` diffs legacy against target and flags dimensions measured on only one side as NOT-COMPARABLE rather than claiming an improvement; `--compare --gate` adds a bash-computed PASS/FAIL verdict and the matching exit code — the one enforcing mode. Works on any language or stack; language handling is a data table, not a per-stack branch. Requires jq; scc/lizard/jscpd are all optional and each one's absence degrades its own metrics to NOT-MEASURED without failing the run. Use when you need a defensible, repeatable quality baseline for a legacy system — sizing a rebuild, reporting to a client, or proving the rebuild is actually better than what it replaced.
---

# specclaw bf-quality

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized; auto-inits using the current directory's basename as the project name).

Measure code quality and write `.specclaw/analysis/quality.json` + `.specclaw/analysis/quality-report.md`. Read-only side-command — no `specclaw-validate-change` call, no `<change>` involved, matching the `analyze`/`architecture`/`domain`/`clarify` pattern.

## What this command is, and what it is not

This is the **only** place quality is judged. `/specclaw:bf-analyze`, `/specclaw:bf-domain` and `/specclaw:bf-architecture` answer *what is this system*; this answers *what shape is the code in*. Those are different questions and the second one is a judgement, so it lives in exactly one command — a reader never has to wonder which document a complexity number came from. Nothing here changes what any other command does.

It is also not `agents/code-reviewer.md`. That reads one change's diff, forms a professional opinion across ten dimensions, and gates a PR. This reads a whole tree, runs measuring tools, and compares numbers to thresholds. The two deliberately disagree on some conventions — the reviewer flags functions over ~30 lines as a matter of taste, this command's default WARN band is 60 — because one is advice to an author and the other is a metric on a legacy corpus nobody is about to hand-tidy.

**Fully optional.** No other command requires anything this one produces. The single exception is `/specclaw:bf-rebuild-plan`, which annotates its per-module rollup with quality status *if* `quality.json` happens to exist and behaves byte-for-byte identically when it does not.

## Tool prerequisites

`jq` is required. The three metric tools are all optional and are probed at every run:

| Tool | Provides | Install |
|------|----------|---------|
| [`scc`](https://github.com/boyter/scc) | LOC, per-file line counts, per-language file counts | `go install github.com/boyter/scc/v3@latest`, or a release binary |
| [`lizard`](https://github.com/terryyin/lizard) | per-function cyclomatic complexity, function length, parameter count | `pip install lizard` |
| [`jscpd`](https://github.com/kucherenko/jscpd) | duplication percentage | `npm install -g jscpd` |

A missing tool never fails the run. Its metrics come back `NOT-MEASURED` with reason `tool_missing`, and the report says so on its face. **Do not install a tool mid-run to "fill in" a gap, and do not estimate a missing value** — a partial measurement that says which parts are missing is worth more than a complete-looking one that isn't.

Note that no tool covers every language. `lizard` does not parse Pascal, for instance, so a Pascal codebase reports size and duplication but no complexity, with reason `language_unsupported`. That is a permanent property of the toolchain, not a run-time failure.

## Determine the mode

Read the user's message:

| Mode | Trigger | Effect |
|------|---------|--------|
| Legacy report | *(default)* | measure the repo (or a given path), write `quality.json` + `quality-report.md`, register/update `QI-###`. Advisory, exit 0. |
| Target report | `--target <path>` | measure the rebuilt tree, write `quality-target.json` + `quality-target-report.md`. Registers no `QI-###`. |
| Compare | `--compare` | requires both snapshots, writes `quality-delta.json` + `quality-delta.md`. Advisory. |
| Gated compare | `--compare --gate` | as compare, plus a bash-computed verdict line and exit code. **The only enforcing mode.** |

A bare path with no flag is the legacy scope for that path.

## Step 1 — Collect

**Legacy or target report:**

```bash
specclaw-bf-quality-collect collect .specclaw [path]            # legacy
specclaw-bf-quality-collect collect .specclaw <path> --target   # target
```

`[path]` defaults to the repository root. The script probes the three tools, enumerates files (`git ls-files` inside a work tree, a pruning `find` otherwise, then the same uniform exclusion of `.specclaw/`, `node_modules/`, `vendor/`, `dist/`, `build/` every other collector applies), runs whichever tools are present, parses **only their machine-readable output**, joins each measured file to its `MOD-###`, applies the thresholds, computes every per-function, per-file and per-module status and rollup, registers or updates the `QI-###` registry, snapshots any prior artifact into `.specclaw/analysis/archive/`, and emits the finished JSON on stdout with a human-readable summary on stderr.

**If it exits non-zero, surface its stderr message to the user verbatim and stop** — don't retry, don't guess a different path, don't try to work around a missing tool. A non-zero exit here means infrastructure (no `jq`, a path outside the repo, no `.specclaw/`), never a quality finding.

**Compare:**

```bash
specclaw-bf-quality-collect compare .specclaw [--gate]
```

Requires both `quality.json` and `quality-target.json`; it fails fast naming whichever is missing and the command that produces it. Pass `--gate` only if the user asked for it.

## Step 2 — Spawn the narration agent

`Agent` tool, `subagent_type: "bf-quality-analyst"`, on the model from `config.yaml` `models.review` (default: `anthropic/claude-sonnet-4-5`) — same tier as its sibling analysis agents, since this is read-only narration of an already-computed artifact. Pass as context:

- The resolved path of the JSON artifact it is to narrate (`quality.json`, `quality-target.json` or `quality-delta.json`) — it reads that file directly.
- Which report file to write (`quality-report.md`, `quality-target-report.md` or `quality-delta.md`) and the matching template path under `$CLAUDE_PLUGIN_ROOT/templates/`.
- The resolved measured path, and the mode.

**Tell the agent explicitly that every status, severity, rollup and verdict in the JSON is already final.** Its job is to say what the numbers mean, in prose a non-engineer can act on — not to check them. See `agents/bf-quality-analyst.md` for the constraints it operates under.

The agent writes the report itself. This skill writes no document.

## Step 3 — Report to the user

State plainly, in this order:

1. **The measurement coverage first, before any finding.** How many files were measured, and which metrics were not measured for which languages and why. A reader who takes a rollup at face value without knowing that complexity was unmeasurable for a third of the tree has been misled, and putting coverage after the findings is how that happens.
2. Per-module rollup statuses, and the count of modules at `HIGH`.
3. New / open / resolved `QI-###` counts.
4. **How many files landed under `MOD-UNASSIGNED`, and why.** Nothing in `.specclaw/` maps a source file to a module — `module-map.md` maps modules to entities, rules, services and screens. The join therefore uses only the file paths each module actually cites in its own `**Evidence:**` bullets, and Evidence is a sample of a boundary rather than an inventory of one. A large unassigned bucket is the expected result on a map nobody has enriched, and it means the per-module numbers describe the cited slice rather than the whole module. Say that rather than letting the rollup read as complete. The fix is to cite more paths in `module-map.md`; guessing from directory layout is exactly the silent assignment that document raises a pending question for.
5. If `module-map.md` is `PROPOSED` rather than `CONFIRMED`, or absent, say so — the modules these numbers are grouped by are a proposal.
6. In gated compare, the verdict line verbatim.

Then say, in one sentence, that the default mode is advisory and blocked nothing.

## Configuration

Thresholds live in `.specclaw/config.yaml` under `quality:` and nowhere else. Defaults:

```yaml
quality:
  complexity_warn: 10          # cyclomatic complexity per function
  complexity_high: 20
  function_length_warn: 60     # lines per function
  function_length_high: 120
  duplication_warn: 5          # percent, per module
  duplication_high: 15
  file_length_warn: 500        # lines per file
  file_length_high: 1000
  register_severity: HIGH      # which band earns a permanent QI-### id
```

`register_severity` defaults to `HIGH` deliberately. `QI-###` ids are permanent and entries are never deleted, so a registry admitting every `WARN` on a large legacy tree would accumulate thousands of rows that outlive the code they describe. `WARN` findings are still counted in every module rollup — they are simply not individually immortalised. Set it to `WARN` if you want them tracked by id, and expect the registry to grow accordingly.

## QI-### permanence

Hotspots are registered in `.specclaw/analysis/quality-issues.md`, which joins `ST-###` and `IS-###` under `templates/CONTRACT.md` (c): ids are assigned once, sequentially, and never renumbered, reused or deleted. It carries their carve-out too — the registry is **append/update-in-place and is never archived**, because a registry that gets archived and regenerated is precisely the silent re-pointing (c) exists to prevent.

A hotspot's identity is the tuple `metric|file|function|module`, never its value. Re-running on unchanged code therefore produces byte-identical id assignments. A hotspot that no longer exceeds its threshold has its `Status` flipped to `resolved` and keeps its id and `First seen` date forever — it is never removed, because "this used to be a hotspot" is itself the finding. A renamed file yields a new `QI-###` plus a resolved old one; inferring the rename would carry an id onto code nobody measured.

`quality.json`'s `quality_issues[]` is a regenerated **projection** of that registry, not the registry itself. One direction per fact.

## Evidence retention

`quality.json` is the current snapshot. A re-run archives the prior one to `.specclaw/analysis/archive/<timestamp>-quality.json` — the same shared archive directory `analyze`/`architecture`/`domain`/`clarify` use — and stamps it `superseded: true` so a reader who finds it cannot mistake it for current. Its measurements are never altered.

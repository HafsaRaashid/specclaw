---
name: extract-golden-master
description: Autonomous, language-agnostic legacy baseline extraction for SpecClaw migration/modernization work — works on any source language (Delphi, VB6, COBOL, C++, C#, Java, Python, or anything else) by discovering its syntax and type system dynamically rather than assuming a fixed set of languages. Performs deep control-flow-graph static analysis, builds an exhaustive boundary/edge-case input matrix, and computes exact ground-truth legacy outputs — all without interactive prompts. Trigger whenever the user asks to extract a golden master, baseline legacy behavior, generate a boundary/edge-case matrix, or capture output before modernizing a module, or whenever an active .specclaw/changes/<name>/ change references a source target and no golden master yet exists for it.
---

# Extract Golden Master

## Purpose
Produce a zero-ambiguity, machine-checkable record of exactly what a
target module does today — inputs, branches, boundary conditions, and
verbatim outputs/exceptions — so a later modernized implementation can
be graded against it. This skill never asks the user anything, and it
never assumes the target is written in any particular language: the
`golden-master-extractor` subagent identifies the language and its
semantics from the repo itself, at run time.

Read-only side-command — no `specclaw-validate-change` call required,
matching the `analyze`/`architecture`/`domain` pattern.

## Step 0 — Setup
**First, run** `specclaw-ensure-init .specclaw` — idempotently creates
`.specclaw/` if it doesn't exist (silent if already initialized).

**Then archive the prior baseline, if any**, before writing a new one —
a golden master is a comparison baseline; silently overwriting it
destroys the thing later diffs are graded against:
```bash
mkdir -p .specclaw/analysis/archive
[ -f .specclaw/matrix-inputs.json ] && mv .specclaw/matrix-inputs.json \
  .specclaw/analysis/archive/$(date +%Y-%m-%d-%H%M%S)-matrix-inputs.json
[ -f .specclaw/golden-master-legacy.json ] && mv .specclaw/golden-master-legacy.json \
  .specclaw/analysis/archive/$(date +%Y-%m-%d-%H%M%S)-golden-master-legacy.json
```
Skip either move if that file doesn't exist yet.

## Step 1 — Gather target resolution context

This skill never prompts for a file path, module name, language, or
confirmation. Instead, gather whatever signal is available and hand it
to the subagent — the subagent does the actual language/module
discovery, not this skill:

- Check whether any active change exists under `.specclaw/changes/<name>/`
  (a directory containing a `proposal.md` or `spec.md`). If one does,
  read it and extract any referenced source paths or module names — this
  is the strongest signal and needs no language detection at all.
- If no active change exists, or it names no source target, note that
  explicitly — the subagent will fall back to discovering candidate
  modules across the whole repo itself.

## Step 2 — Spawn the extraction agent

`Agent` tool, `subagent_type: "golden-master-extractor"`, on the model
from `config.yaml` `models.review` (default: `anthropic/claude-sonnet-4-5`).
Pass as context:
- The target resolution context gathered in Step 1 (active-change
  source references, or a note that none exist).
- The project root path.
- The `.specclaw` root path to write both output files under.

The agent performs its own CFG analysis, boundary-matrix generation, and
ground-truth computation, and writes both output files itself, per its
own Output section — this skill does not write either file.

## Step 3 — Present a summary

Relay the agent's final one-line summary to the user: modules processed,
total cases, total unresolved, total low-confidence cases, and the two
file paths written (`.specclaw/matrix-inputs.json`,
`.specclaw/golden-master-legacy.json`).

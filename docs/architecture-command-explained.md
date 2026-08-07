# The `architecture-command` Change, Explained

What `/specclaw:architecture` actually is, grounded in the change trail at
`.specclaw/changes/architecture-command/` (proposal → spec → design → tasks
→ verify-report) and cross-checked against the files that actually shipped
in `plugins/specclaw/`. Built and verified in-session (6/6 tasks, 16/16
acceptance criteria, verdict PASS); version bumped `0.5.4` → `0.5.5`.
**Not yet committed** — everything described here sits uncommitted in the
working tree on `specclaw/analyze-command`, per an explicit no-git-operations
instruction for this session (see `.specclaw/changes/architecture-command/
status.md`'s Build row for the full note).

This is change 1 of a 3-change roadmap recorded in this change's own
`proposal.md`: `architecture-command` (this one) → `domain-command`
(`domain-model.md` + `functional-spec.md`) → `discover-command` (an umbrella
that emits `rebuild-inputs.md`). See §6 for how this change sets up the
other two.

---

## 1. What Was Added

Fourteen file changes — 6 new, 8 modified — matching design.md's File
Changes Map:

| File | Type | What it is / does |
|---|---|---|
| `plugins/specclaw/skills/architecture/SKILL.md` | **Skill** (new) | Registers `/specclaw:architecture [path]`. Orchestration prose only — mirrors `skills/analyze/SKILL.md`'s shape exactly. |
| `plugins/specclaw/bin/specclaw-analyze-codebase` | **Bash script** (modified) | Gained a new `dependency_graph` field on its existing `collect` subcommand — three new extractors (Delphi `uses`, Node relative `import`/`require`, .NET `ProjectReference`) plus their file resolvers. Every pre-existing field's construction is untouched — purely additive. |
| `plugins/specclaw/templates/architecture.md` | **Template** (new) | `{{placeholder}}` scaffold: header + four body sections, System Context (L1) through Code (L4), each pairing a fenced ` ```mermaid ` block with a prose placeholder. |
| `plugins/specclaw/agents/architecture-analyst.md` | **Agent** (new) | A subagent persona (`tools: [Read, Write, Bash]`, `model: sonnet`). Takes the collected JSON (including `dependency_graph`), reads real files itself, and writes the final `.specclaw/analysis/architecture.md`. The piece that does the actual thinking. |
| `plugins/specclaw/skills/analyze/SKILL.md` | **Skill** (modified) | Output path relocated to `.specclaw/analysis/codebase-report.md`; gained a one-time migration step for pre-upgrade reports sitting at the old path. No change to what it collects. |
| `plugins/specclaw/agents/codebase-analyst.md` | **Agent** (modified) | Same relocation — only the file path it writes to changed. Its six-dimension rubric, Evidence Discipline, and report shape are byte-identical to before. |
| `plugins/specclaw/tests/run-parser-tests.sh` | **Test** (modified) | Gained "Case 10" (8 sub-assertions, 10a–10h) exercising `dependency_graph`. |
| `plugins/specclaw/tests/fixtures/analyze/` | **Test fixture** (extended) | 6 new files added to the existing fixture (not a parallel one): `UnitA.pas`/`UnitB.pas` (Delphi `uses`), `a.js`/`b.js` (Node relative `require`), `App.csproj`/`Other/Other.csproj` (.NET `ProjectReference`). |
| `plugins/specclaw/.claude-plugin/plugin.json` | **Manifest** (modified) | Version bump only: `0.5.4` → `0.5.5`. |
| `.claude-plugin/marketplace.json` | **Manifest** (modified) | Same version bump, kept in sync. |
| `README.md` | **Docs** (modified) | New `/specclaw:architecture [path]` row, placed next to `/specclaw:analyze`; the existing `/specclaw:analyze` row's described output path corrected to `.specclaw/analysis/codebase-report.md`. |

**The skill/agent distinction, same pattern as `analyze-command`:** one skill
(`skills/architecture/SKILL.md`) orchestrates; one agent
(`agents/architecture-analyst.md`) does the reading and writing; the bash
script is deterministic fact-collection with no judgment calls; the template
is a static shape neither the skill nor the script executes.

**What's different this time:** unlike `analyze-command`, which shipped
entirely new files, this change's largest single piece of work is an
*extension* to an already-shipped script (`bin/specclaw-analyze-codebase`)
plus two *mechanical relocations* of an already-shipped skill/agent pair. No
new bin script was written — the hard requirement to reuse rather than
re-derive facts meant growing the existing collector instead.

---

## 2. `/specclaw:analyze` vs `/specclaw:architecture` — what's actually different

They share almost their entire pipeline. Both run the exact same collection
script (`specclaw-analyze-codebase collect`), both follow the same
archive-on-rerun convention into the same shared directory
(`.specclaw/analysis/archive/`), both are read-only side-commands with no
lifecycle gate. The difference is entirely in **what question each one
answers** and **which one piece of agent/template/output they own**:

| | `/specclaw:analyze` | `/specclaw:architecture` |
|---|---|---|
| **Question it answers** | "What is this codebase, technically?" | "How are this codebase's pieces connected, at every zoom level?" |
| **Output file** | `.specclaw/analysis/codebase-report.md` | `.specclaw/analysis/architecture.md` |
| **Shape of the output** | Prose, 6 fixed sections (Tech Stack, Dependencies, Structure/Architecture, Domain, Risks, Suggested First Changes) | 4 C4 levels (System Context → Containers → Components → Code), each a **Mermaid diagram** plus prose — zoomable, not flat prose |
| **Agent** | `codebase-analyst` (6-dimension rubric) | `architecture-analyst` (4-level rubric) |
| **The one fact only this command needs** | Nothing new — it was the first command, so everything it uses (manifests, LOC, top-level dirs, discovered docs) was collected for it originally | `dependency_graph` — a file/project-level edge list (`uses` clauses, relative imports, `ProjectReference`) that didn't exist before this change. Needed to draw the L2/L3 diagrams' edges; `analyze`'s report never draws an edge between two files, so it never needed this. |
| **Domain content** | Yes — has its own "Domain" section (inferences about the business problem the code solves) | No — architecture is purely structural; domain/business content is explicitly out of scope here and deferred to the next change in the roadmap (`domain-command`) |
| **Renders as a diagram?** | No — pure prose | Yes — every level is a Mermaid `flowchart`/`graph` block with `subgraph` boundaries (deliberately *not* Mermaid's native `C4Context`/`C4Container` types — see §5) |

**The one-sentence version:** `analyze` tells you what the codebase *is*
(stack, deps, domain, risk) in prose; `architecture` shows you how it's
*shaped* (system → containers → components → code) as diagrams, using one
new fact (the dependency graph) that `analyze` never needed. Both commands
now share a home (`.specclaw/analysis/`) because they're the first two
documents in what's meant to become a five-document suite — see §6.

They are **not** alternatives to each other. The manager's brief that
motivated this whole roadmap was explicit that prose-only architecture
description wasn't enough for an AI model to rebuild an application from —
`architecture.md` is the fix for that specific gap, sitting alongside
`codebase-report.md` rather than replacing any part of it.

---

## 3. The Commands

**What the user types:** `/specclaw:architecture` or `/specclaw:architecture
<path>`.

**What it reads:**
- `.specclaw/config.yaml` — for `models.review` (same default
  `/specclaw:analyze`/`/specclaw:verify` use, `anthropic/claude-sonnet-4-5`).
- The scoped file tree — via `specclaw-analyze-codebase collect`, the exact
  same call `/specclaw:analyze` makes, now also returning `dependency_graph`.
- Whatever additional files the `architecture-analyst` agent decides to
  `Read` during its own investigation — same "the collected JSON is a map,
  not the full picture" discipline `codebase-analyst` already follows.

**What it writes:**
- `.specclaw/analysis/architecture.md` — the current report, always at this
  stable path.
- `.specclaw/analysis/archive/<YYYY-MM-DD-HHMMSS>-architecture.md` — the
  *previous* report, moved here (not deleted) before a new one is written,
  if one existed. **Same archive directory** `/specclaw:analyze` now uses
  for `codebase-report.md` — the two document types share one archive,
  distinguished only by filename.

**What it never touches:** no `changes/<name>/` directory, no `STATUS.md`,
no `specclaw-validate-change` call, no source code. Read-only over the
analyzed codebase, exactly like `/specclaw:analyze`.

---

## 4. The Flow

One run of `/specclaw:architecture [path]`, step by step:

1. **`skills/architecture/SKILL.md` fires.** Step 0: `specclaw-ensure-init
   .specclaw`.
2. **The skill shells out to the (now-extended) bash script:**
   `specclaw-analyze-codebase collect .specclaw [path]`.
   - Path validation (existence, inside-repo, not `.specclaw` itself/nested)
     happens *inside* `collect` — the skill does not reimplement it. A
     non-zero exit means the skill surfaces the stderr message verbatim and
     stops.
   - `collect` now emits an **eighth** top-level field, `dependency_graph`,
     alongside the original seven (`path`, `project_root`, `top_level_dirs`,
     `manifests`, `loc_by_extension`, `test_locations`, `discovered_docs`).
     Populated by three best-effort extractors, each resolving references
     only against the already-scoped file list — an unresolved reference
     (an RTL unit, a bare npm import, a `using` namespace with no cheap
     file mapping) produces no edge, never a guess:
     - Delphi `.pas` `uses` clauses → `"kind": "uses"`
     - Node/JS/TS relative `require`/`import` (leading `./`/`../` only) →
       `"kind": "import"`
     - .NET `.csproj` `<ProjectReference>` (project-to-project, distinct
       from the `<PackageReference>` entries already in `manifests`) →
       `"kind": "project_reference"`
     - Go/Rust/Python/Java/Maven/Make → no contribution. Stated as an
       honest gap, not guessed.
3. **The skill archives the prior report, if one exists** — a plain `mv`
   into `.specclaw/analysis/archive/`, same shared directory
   `/specclaw:analyze` uses.
4. **The skill spawns the `architecture-analyst` agent**, passing the
   collected JSON (including `dependency_graph`) and the resolved target
   path directly as context.
5. **The agent does the actual analysis** across four C4 levels:
   - **L1 System Context** — the system as one box, plus external actors,
     inferred from manifests/docs/entry points.
   - **L2 Containers** — deployable/runnable units inside the system,
     inferred from top-level structure and manifests.
   - **L3 Components** — clusters of files by responsibility inside each
     container; **edges between components come from `dependency_graph`** —
     this is the one level that could not exist before this change.
   - **L4 Code** — functions/classes inside *one* component, produced only
     when the agent judges it warranted (non-obvious structure, a suspected
     god-object, or the component worth pointing a rebuild effort at
     first). Every other component gets an explicit "L4 not warranted for
     this component" — never silent omission.
   Every diagram uses Mermaid `flowchart`/`graph` with `subgraph`
   boundaries, never the native `C4Context`/`C4Container`/`C4Component`
   types (see §5). Every node, edge, and prose claim traces to a collected
   fact or a file the agent opened itself.
6. **The agent writes `.specclaw/analysis/architecture.md`** itself, once,
   at the end.
7. **The skill presents a short summary** — path analyzed, which C4 levels
   were written, any component flagged "L4 not warranted."

```
/specclaw:architecture [path]
  │
  ├─ 1. specclaw-ensure-init .specclaw
  ├─ 2. specclaw-analyze-codebase collect .specclaw [path]   (bash — now 8 fields)
  │        → (unchanged) file enum / manifests / LOC / test-locations / discovered_docs
  │        → (NEW) dependency_graph: uses (Delphi) + import (Node) + project_reference (.NET)
  │        → one JSON object to stdout (die-before-work on bad [path])
  ├─ 3. mv architecture.md → analysis/archive/<timestamp>-...   (if it existed)
  ├─ 4. Agent(subagent_type: "architecture-analyst", <JSON incl. dependency_graph>)
  │        → reads templates/architecture.md for shape
  │        → Read tool: opens files for L1–L4 evidence
  │        → writes .specclaw/analysis/architecture.md   (4 Mermaid diagrams + prose)
  └─ 5. summary to user
```

---

## 5. Decisions Locked In

From the approved proposal's Open Questions and design.md's Key Decisions,
confirmed against the shipped code:

- **Mermaid `flowchart`/`graph` + `subgraph`, never native `C4Context`/
  `C4Container`/`C4Component`.** Confirmed in `agents/architecture-analyst.md`'s
  Mermaid Convention section: "**Never** use Mermaid's native `C4Context`,
  `C4Container`, or `C4Component` diagram types" — reasoning given is
  inconsistent GitHub/editor renderer support for the native types versus
  universal `flowchart` support.
- **`.NET`'s cheap dependency-graph signal is `<ProjectReference>`, not
  `using` directives** — a refinement made *during* planning, not in the
  original proposal. `using` directives reference namespaces, not files;
  there's no cheap namespace-to-file mapping. `<ProjectReference>` in the
  same `.csproj` files is a genuine, cheap, file-adjacent signal — confirmed
  shipped as a distinct extractor (`extract_dotnet_project_refs`) from the
  pre-existing `extract_dotnet_deps` (`<PackageReference>` only), so a
  `ProjectReference` path can never leak into a manifest's own
  `dependencies` list (verified directly by the build-time test suite,
  case 10f).
- **Go/Rust/Python/Java/Maven/Make get zero `dependency_graph` contribution
  in v1.** No cheap, reliable file-level signal exists for these the way it
  does for Delphi/Node/.NET — confirmed by inspection: no extraction branch
  exists for any of them in the shipped script.
- **L4 is agent judgment, stated explicitly either way.** Confirmed:
  `agents/architecture-analyst.md`'s L4 Judgment Rule requires the exact
  line "L4 not warranted for this component" rather than silent omission.
- **Relocate `/specclaw:analyze`'s output path as part of this change,
  including a one-time migration — not a silent new default.** Confirmed:
  `skills/analyze/SKILL.md` gained a dedicated migration step (its Step 2,
  before the normal archive step) that moves a pre-upgrade
  `.specclaw/codebase-report.md` into the new archive location if the new
  path doesn't yet exist — so a report from before this change is never
  silently orphaned.
- **Shared archive directory, not per-document-type.** Confirmed:
  `architecture.md` archives into the same `.specclaw/analysis/archive/`
  `codebase-report.md` now uses, distinguished only by filename.

---

## 6. Known Limitations, and What Comes Next

Carried forward from `verify-report.md`'s "Issues Found" (verdict was still
**PASS**, 16/16 ACs — these are non-blocking notes, not failures):

1. **No live end-to-end run artifact exists.** Same situation
   `analyze-command` was in at its own verify stage: there is no
   `.specclaw/analysis/architecture.md` anywhere in this repo yet. AC9,
   AC10, and AC13 (the actual run, its second-run archive, and the old-path
   migration) were graded on wiring/instruction correctness, not an
   observed output file.
2. **A pre-existing, unrelated bug surfaced again during verification** —
   the same `specclaw-verify collect` `Files:`-parsing bug
   `analyze-command`'s own verify pass first flagged. It caused this
   change's evidence payload to show only 1 of ~14 actually-changed files;
   worked around by having the verify agent read every file directly from
   disk. Still not fixed — out of scope for this change, same as last time.
3. **Several spec.md edge cases lack dedicated test coverage:** a
   genuinely multi-line Delphi `uses` clause, a case-differing unit
   reference, a true circular edge, a scope with zero eligible files of any
   kind, and a true multi-ecosystem monorepo scoped to one subproject. Code
   inspection shows no defect in any of these paths, but none has a
   fixture-backed assertion.
4. **The FR9.3 migration step structurally cannot be exercised by the
   parser-test harness** — it's a Bash instruction inside a Markdown skill
   file, not inside the bash *script* `run-parser-tests.sh` tests. Design.md
   named this as its own top risk before the change was even built.

**What comes next, per this change's own `proposal.md`:** `domain-command`
— `/specclaw:domain` → `domain-model.md` (business entities/rules, each
anchored to a routine) + `functional-spec.md` (user-facing capabilities,
workflows, UI inventory). Bundled into one command because both need the
same new evidence (a UI-control/menu-handler-to-routine catalog) neither
`analyze` nor `architecture` collect today. After that, `discover-command`
— an umbrella that runs all three and writes `rebuild-inputs.md`, the
honest gap list of what static analysis alone can never produce.

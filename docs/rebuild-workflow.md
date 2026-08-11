# Rebuild Workflow: connecting analysis to the delivery lifecycle

A recipe for rebuilding an existing (possibly legacy) application as a
faithful re-implementation in a new stack, using SpecClaw's analysis
commands (`bf-analyze`, `bf-architecture`, `bf-domain`) together with the ordinary
`propose → plan → build → verify → pr` lifecycle. Nothing in this recipe
modifies `propose`, `plan`, `build`, `verify`, `pr`, or their bin
scripts/agents — it is entirely configuration plus one new read-only
command, `/specclaw:bf-rebuild-plan`.

## The gotcha, up front

**`git add` the analysis documents before anything else in this recipe
works.** `specclaw-discover-context` — the mechanism `plan`/`build`/`verify`
use to pull grounding documents into an agent's context — enumerates
candidate files via `git ls-files`, not a plain filesystem walk. A file
`bf-analyze`/`bf-architecture`/`bf-domain` wrote to `.specclaw/analysis/` but that was
never staged is invisible to discovery, **even if you've pinned it** (see
Step 3). Staging is enough — you don't need to commit:

```bash
git add .specclaw/analysis/*.md
```

Re-run this after every `bf-analyze`/`bf-architecture`/`bf-domain`/`bf-rebuild-plan`
run that produces a new or updated document.

## Step 1 — Produce the analysis documents

```
/specclaw:bf-analyze
/specclaw:bf-architecture
/specclaw:bf-domain
```

These write `.specclaw/analysis/codebase-report.md`, `architecture.md`,
`domain-model.md`, and `functional-spec.md`. Read-only, no lifecycle gate —
run them in any order, any number of times (each re-run archives the prior
version into `.specclaw/analysis/archive/`).

## Step 2 — Stage them

```bash
git add .specclaw/analysis/*.md
```

## Step 3 — Pin them for the lifecycle

Add the four paths to `context.pin` in `.specclaw/config.yaml` (a
commented-out example ships in the config template — uncomment and adjust):

```yaml
context:
  pin:
    - .specclaw/analysis/codebase-report.md
    - .specclaw/analysis/architecture.md
    - .specclaw/analysis/domain-model.md
    - .specclaw/analysis/functional-spec.md
```

`specclaw-discover-context` checks `context.pin` **before** its default
directory exclusions — including the one that normally skips `.specclaw/`
entirely — so pinned analysis documents bypass that exclusion and are
force-ranked highest priority. Once pinned (and staged, per the gotcha
above), `/specclaw:plan`, `/specclaw:build`, and `/specclaw:verify` all pick
them up automatically, with no change to any of those three skills.

**Size the shared budget.** All four documents are pinned at top priority
and are emitted into the digest first, ahead of README/CLAUDE.md/other
`docs/*` discovery, within `context.max_lines` (default `3000`). For a real
legacy codebase they can easily be large enough to consume the whole
budget on their own, silently crowding out everything else discovery would
normally surface. Size `max_lines` to the pinned total plus headroom:

```bash
wc -l .specclaw/analysis/*.md | tail -1   # pinned total
```

Set `context.max_lines` to that total plus roughly `3000` for other repo
docs (the original default), e.g. if the four documents total 4,200 lines,
set `max_lines: 7200`. `specclaw-discover-context` never drops a file
silently regardless of the number you pick — every truncated or dropped
document is named in a footer comment in its output — so if you see
docs missing after this, that footer tells you exactly which and why.

## Step 4 — Generate the rebuild backlog

```
/specclaw:bf-rebuild-plan
```

Reads the four analysis documents and writes
`.specclaw/analysis/rebuild-backlog.md`: an ordered list of individually
proposable features, each naming the `functional-spec.md` capability it
covers, the `domain-model.md` rules/entities that form its acceptance
basis, its dependency on earlier items, and a "Verification inputs needed"
field (see Fidelity limitation, below). It also includes a coverage check
confirming every functional-spec capability is accounted for.

If any of the four analysis documents is missing, `bf-rebuild-plan` stops and
names exactly which one(s) plus the command that produces each — it never
attempts a partial backlog.

**Optional but recommended: run `/specclaw:bf-clarify` and `/specclaw:bf-baseline`
first.** Neither is required — `bf-rebuild-plan` degrades gracefully without
them, naming what's missing in its status header — but when
`.specclaw/analysis/clarifications.md`/`decisions.md` and
`.specclaw/baseline/manifest.json`/`scenarios.md` are present, every backlog
item also gets a computed **Gate** (blocked by an unanswered clarify
question, at risk from a non-blocking one, or clear) and **Verification**
state (a captured golden-master fixture exists, one is designed but not yet
captured, the behavior is provably unreachable in the legacy app, or no
baseline work has touched these rules at all) — turning the backlog from a
static acceptance-basis list into a live readiness signal.

`bf-rebuild-plan` creates **nothing** under `.specclaw/changes/` and calls
**no** lifecycle command. Stage its output too:

```bash
git add .specclaw/analysis/rebuild-backlog.md
```

**The backlog is living state after the first run.** A second bare
`/specclaw:bf-rebuild-plan` refuses to regenerate it (to avoid destroying
in-flight Gate/Verification status, struck/deferred items, or a status note
a human typed into an item). Run `/specclaw:bf-rebuild-plan --refresh` instead
— it recomputes Gate/Verification for every item, applies any newly
recorded decisions (striking, deferring, or reshaping items; appending
genuinely new ones), and ends with a change report naming what became
unblocked or verifiable, what was struck/deferred/revised/added, and the
single recommended next item to propose. `BL-###` item ids are permanent
across every refresh, never renumbered.

## Step 4b — Optional: UI fidelity capture

**Skip this entire step unless the rebuilt interface has to resemble the
legacy one.** `/specclaw:bf-clarify`'s standard bank asks the question either
way — `SQ-013`, "UI fidelity policy for this rebuild?", with exactly three
answers:

| Answer | Means |
|---|---|
| `FAITHFUL` | Reproduce the legacy layout structure and colour theme exactly, within the target platform's own rendering norms. |
| `THEME-ONLY` | Keep the colour palette / branding tokens; the layout is reinterpreted for the target platform. |
| `REINTERPRET` | New design; the legacy UI is reference material only. |

Answer `REINTERPRET` and you are done — nothing else in the pipeline changes,
no UI requirement is attached to any backlog item, and no warning is emitted.
The proposed default is `REINTERPRET` precisely *because* it is the
least-work reading: it has to be chosen deliberately rather than assumed
silently, which is what would otherwise let a rebuild quietly discard an
interface its users know by heart.

Answer `FAITHFUL` or `THEME-ONLY` and the workstream activates:

```
/specclaw:bf-ui                       # in the legacy repo, after bf-domain
  → .specclaw/ui/ui-inventory.md          one section per screen, permanent SCR-###
  → .specclaw/ui/design-tokens.json       colour/typography/spacing, permanent TK-
  → .specclaw/ui/screenshot-checklist.md  a human work order

  ... a human runs the legacy app and captures the PNGs into
      .specclaw/ui/screens/, per the checklist's exact filenames ...

/specclaw:bf-ui --record              # hashes them into ui-manifest.json
/specclaw:bf-rebuild-plan --refresh   # attaches SCR/TK grounding to items
```

Then, once a change is built in the new repo:

```
/specclaw:bf-ui --checklist <change-name>
  → .specclaw/changes/<change>/ui-review.md
```

A named human fills in that file's rows and commits it with the PR, next to
the replay evidence package. Together they are the change's complete fidelity
record: mechanical proof for behaviour, signed human review for appearance.

**No specclaw command ever runs the legacy app, takes a screenshot, or judges
whether two screens look the same** — the same boundary `/specclaw:bf-baseline`
draws around fixture capture, for the same reason. And UI is never a
golden-master seam: `/specclaw:bf-replay` compares no screenshot and its
verdict says nothing about appearance (it gains one informational footer line
saying so). Do not read `.specclaw/ui/` as a promise of pixel-identity; read
it as the reference a human checks against, on the record.

If the policy is decided but the `.specclaw/ui/` artifacts don't exist,
`/specclaw:bf-rebuild-plan` says so loudly — one warning naming every missing
artifact, with every screen-bearing item held at `OPEN QUESTIONS`. It will not
quietly proceed as though the UI requirement had been dropped.

## Step 4c — Migrate and accept one module at a time

`/specclaw:bf-domain` also writes `.specclaw/analysis/module-map.md`: the
`MOD-###` migration units the system's entities, rules, services and screens
group into, each with its owned vs referenced-but-not-owned entities and its
dependencies on other modules. The hierarchy is
`MOD-### → BL-0## → DR-### → GM-###`. Modules are a **selection dimension** over
the one shared corpus — there is still one manifest, one backlog, one
`fixtures/` directory, and nothing is split per module.

**Confirm the map before you sequence a migration on it.** It is agent-proposed:
its `**Status:**` line reads `PROPOSED` until a human edits it to
`CONFIRMED by <name>, <date>`. Nothing is blocked by an unconfirmed map — every
command runs and says on its own face that the grouping is unconfirmed — but the
boundaries become the shape of the whole rebuild, so they are worth an hour of
review. An ambiguous boundary is never assigned silently: it becomes a typed
pending question for `/specclaw:bf-clarify` and the item is placed
provisionally.

Then work one module at a time:

```
/specclaw:bf-rebuild-plan --refresh --module MOD-002   # plan just this module
/specclaw:bf-baseline --module MOD-002                 # design its scenarios
/specclaw:bf-baseline --harness --module MOD-002       # extend the harness
#   ... a human runs the harness and captures fixtures ...
/specclaw:bf-baseline --record                         # whole-corpus, as always
/specclaw:bf-replay --module MOD-002                   # accept the module (in the NEW repo)
```

Each `--module` step leaves every other module's items, scenarios, generated
tests, coverage lines, and human-added notes untouched. `--record` stays
whole-corpus: the manifest is one document, and a module tag is a field on a
fixture, not a separate file.

**Watch the shared flows.** A scenario whose rules span two modules is tagged
with both, is selected by both modules' replay runs, and counts toward both in
the report's module rollup — which always states how many of a module's fixtures
are shared and with which others. That is deliberate: a shared fixture is the
flow that breaks when one module is rebuilt in isolation, so a module PASS that
quietly excluded it would be a false verdict. Read the rollup, not just the
overall verdict, before calling a module accepted.

`.specclaw/analysis/module-status.md` (regenerated by every
`/specclaw:bf-rebuild-plan` run) is the one-screen view of where each module
stands: items planned, scenarios captured, latest module-scoped replay verdict,
open questions. It is a status view — no number in it says a module is *done*,
because specclaw records no built state for a backlog item.

## Step 5 — Propose each backlog item yourself

`/specclaw:bf-rebuild-plan` does not, and will not, auto-invoke
`/specclaw:propose` — that would reintroduce the exact lifecycle coupling
this recipe deliberately avoids. Work through `rebuild-backlog.md` in the
order it gives you:

```
/specclaw:propose "<backlog item title>"
```

Because the analysis documents are already pinned (Step 3), the resulting
`/specclaw:plan` for each item is grounded in the same functional-spec
capability and domain-model rules the backlog item cited — no need to
re-paste analysis content into the conversation.

## Step 6 — What to copy into the new repo (the Phase B copy set)

Steps 1–4b all run in the **legacy** repo (Phase A). `/specclaw:bf-replay` and
`/specclaw:bf-ui --checklist` run in the **new** repo (Phase B), and they need
the Phase A artifacts to be present there — they resolve a change to its
backlog item, its fixtures, and its screens by reading these files:

```
.specclaw/analysis/module-map.md              # MOD modules: names, deps, rule ownership
.specclaw/analysis/rebuild-backlog.md        # change → BL item → DR rules / SCR screens
.specclaw/analysis/domain-model.md           # DR rules, for coverage reporting
.specclaw/analysis/decisions.md              # sanctioning CQs; the SQ-013 UI policy
.specclaw/baseline/scenarios.md              # GM scenario definitions + seam layers
.specclaw/baseline/seams.md                  # seam recommendations cited in remediations
.specclaw/baseline/error-map.md              # the project's semantic error vocabulary
.specclaw/baseline/manifest.json             # fixture roster + content hashes  ┐ always
.specclaw/baseline/fixtures/                 # the captured fixtures           ┘ together
.specclaw/ui/ui-inventory.md                 # SCR entries (FAITHFUL/THEME-ONLY only)
.specclaw/ui/design-tokens.json              # TK groups          (same)
.specclaw/ui/screenshot-checklist.md         # states + setup notes (same)
.specclaw/ui/screens/                        # captured PNGs      ┐ always
.specclaw/ui/ui-manifest.json                # their hashes       ┘ together
```

**`module-map.md` travels too, but is not load-bearing for a verdict.** `/specclaw:bf-replay --module` selects fixtures from `manifest.json`'s own `module_ids`, never from the map — so a replay run works without it. What the map adds in the new repo is readability: the report's module rollup names each module, and `module-status.md` can be regenerated there. Copy it; if it is absent, rollups still compute and simply read as bare `MOD-###` ids.

**`error-map.md` is not optional.** It is the legacy app's own error vocabulary
— one `SCREAMING_SNAKE` code per business condition it can reject on, each
citing the legacy line that raises it. `/specclaw:bf-replay` maps the rebuild's
errors into *that* vocabulary rather than comparing raw exception type names,
which is what stops a framework change from reading as twenty behaviour
changes. Without this file in the new repo, no error can be mapped at all and
every rejection scenario lands as an unmapped code holding the run at
`PASS-PENDING-DECISIONS`. Nothing in the specclaw plugin contains a code; this
file is the only place they exist.

**The paired lines are paired for one reason: a hash without the file it
hashes, or a file without its recorded hash, proves nothing.**
`/specclaw:bf-replay resolve` already enforces this for fixtures — it refuses
to run if a selected fixture's recomputed sha256 doesn't match
`manifest.json`, because comparing against a half-copied or edited baseline is
worse than not comparing at all. `screens/` and `ui-manifest.json` follow the
same rule: copy them together, or the sha256 a reviewer is asked to confirm
in `ui-review.md` refers to nothing.

Re-copy after any Phase A re-run that changes them. The `.specclaw/ui/` lines
are needed only when the UI fidelity policy is `FAITHFUL` or `THEME-ONLY`;
under `REINTERPRET` the copy set is just the first eight lines, exactly as it
was before the UI workstream existed.

## Fidelity limitation

This recipe makes the functional spec's capabilities and the domain
model's rules the **acceptance basis** for each rebuilt feature — that is
what pinning plus the backlog's per-item references gives you. It does
**not** prove that the new implementation behaves identically to the
legacy system. True "same app" verification additionally requires:

- **Golden-master outputs** — recorded input/output pairs from the running
  legacy system, captured by a human, to diff the new implementation
  against. No amount of static analysis produces these.
- **External-format and DLL/COM semantics** — where the legacy app depends
  on a proprietary file format, an opaque DLL, or a COM component whose
  runtime behavior isn't recoverable from source alone, a human with
  domain knowledge of that dependency must supply it.

`rebuild-backlog.md`'s "Verification inputs needed" field exists to name
these gaps per item, not to imply they're already covered. Treat a backlog
item's acceptance criteria as necessary, not sufficient, for a truly
faithful rebuild.

## Staleness limitation

`bf-rebuild-plan` does not check whether the analysis documents are stale
relative to the current source — it trusts each document's own "Date
analyzed" field and never diffs it against git history. If the codebase has
changed meaningfully since that date, re-run `/specclaw:bf-analyze`,
`/specclaw:bf-architecture`, and `/specclaw:bf-domain` before `/specclaw:bf-rebuild-
plan` so the backlog reflects the current code, not a stale snapshot.

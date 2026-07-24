# Rebuild Workflow: connecting analysis to the delivery lifecycle

A recipe for rebuilding an existing (possibly legacy) application as a
faithful re-implementation in a new stack, using SpecClaw's analysis
commands (`analyze`, `architecture`, `domain`) together with the ordinary
`propose → plan → build → verify → pr` lifecycle. Nothing in this recipe
modifies `propose`, `plan`, `build`, `verify`, `pr`, or their bin
scripts/agents — it is entirely configuration plus one new read-only
command, `/specclaw:rebuild-plan`.

## The gotcha, up front

**`git add` the analysis documents before anything else in this recipe
works.** `specclaw-discover-context` — the mechanism `plan`/`build`/`verify`
use to pull grounding documents into an agent's context — enumerates
candidate files via `git ls-files`, not a plain filesystem walk. A file
`analyze`/`architecture`/`domain` wrote to `.specclaw/analysis/` but that was
never staged is invisible to discovery, **even if you've pinned it** (see
Step 3). Staging is enough — you don't need to commit:

```bash
git add .specclaw/analysis/*.md
```

Re-run this after every `analyze`/`architecture`/`domain`/`rebuild-plan`
run that produces a new or updated document.

## Step 1 — Produce the analysis documents

```
/specclaw:analyze
/specclaw:architecture
/specclaw:domain
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
/specclaw:rebuild-plan
```

Reads the four analysis documents and writes
`.specclaw/analysis/rebuild-backlog.md`: an ordered list of individually
proposable features, each naming the `functional-spec.md` capability it
covers, the `domain-model.md` rules/entities that form its acceptance
basis, its dependency on earlier items, and a "Verification inputs needed"
field (see Fidelity limitation, below). It also includes a coverage check
confirming every functional-spec capability is accounted for.

If any of the four analysis documents is missing, `rebuild-plan` stops and
names exactly which one(s) plus the command that produces each — it never
attempts a partial backlog.

`rebuild-plan` creates **nothing** under `.specclaw/changes/` and calls
**no** lifecycle command. Stage its output too:

```bash
git add .specclaw/analysis/rebuild-backlog.md
```

## Step 5 — Propose each backlog item yourself

`/specclaw:rebuild-plan` does not, and will not, auto-invoke
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

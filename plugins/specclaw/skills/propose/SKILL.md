---
description: Draft a new change proposal. INVOKE IMMEDIATELY whenever the user mentions a proposal, feature idea, change request, new initiative, or anything they want to add/build/implement — do NOT gather details conversationally first. The skill itself will ask for any missing information after invocation. Creates .specclaw/changes/<name>/proposal.md with problem statement, solution, scope, impact, and open questions. The first step in the propose → plan → build → verify → pr lifecycle.
---

# specclaw propose

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized; auto-inits using the current directory's basename as the project name).

Create a new proposal for a change.

**If the user hasn't yet provided enough detail to draft the proposal (e.g. they just said "i have a proposal" with no specifics), ask once for the essentials inside this skill — what's the idea, what problem does it solve — then proceed to the steps below. Do not wait for a separate turn to invoke this skill.**

1. Slugify the user's idea into a `<change-name>` (lowercase, hyphens, no spaces).

1b. **Target-foundation gate** (brownfield rebuilds only — inert everywhere else). **Run this before creating anything:**

```bash
specclaw-bf-bootstrap foundation-check .specclaw
```

**If `applicable` is `false`, skip straight to step 2** — there is no rebuild backlog, so this project is not a brownfield rebuild target and nothing here applies. Say nothing about it.

**If `applicable` is `true` and `foundation_ready` is `false`, stop.** Do not create the change directory, do not draft a proposal, do not run the dependency check. Relay the `reason`, then the `remedy` verbatim:

> Target rebuild foundation has not been created. Run `/specclaw:bf-bootstrap` first.

**Why this gate is absolute.** Without it, the first backlog item proposed inherits responsibility for inventing the application skeleton — and it inherits it *invisibly*, because nothing in the spec, the tasks or the verify report says "this item is also creating the app". That is how a screen-bearing item once shipped as a backend-only slice: the repo had no frontend, so the frontend was never anybody's task. A backlog item adds a capability to an application that already exists. If it does not exist yet, the answer is to create it deliberately, once, not to smuggle it into whichever item happened to be proposed first.

The one legitimate false positive is proposing an ordinary change **inside the legacy repo**, which also carries a `rebuild-backlog.md`. That is recorded once, explicitly, with `/specclaw:bf-bootstrap --not-applicable "<why>"` — never inferred, because there is no honest signal that distinguishes the two repos.

When `foundation_ready` is `true`, continue silently. Mention the foundation only if the user asks.

2. Create `.specclaw/changes/<change-name>/`.

2a. **Item-split resume check** (brownfield rebuilds only). Step 2b's `bypass-check` output carries a `splits` array — every non-`COMPLETE` `IS-###` split on this backlog item. **If it is empty (the normal case), skip to 2b.**

Otherwise this item has already been partly built, and this proposal is a **resume, not a fresh start**. Before anything else, present:

- **What was already implemented** — the entry's `implemented_now`, and the rules it covers (`rules_implemented`).
- **The evidence that implemented it** — `change`, `evidence` (PR/merge), `replay_evidence` (the run id). Cite these, don't paraphrase them; they are what makes "already built" checkable rather than asserted.
- **What remains deferred** — `deferred`, plus `rules_deferred` and `layers_deferred`.
- **Which blockers are now satisfied** — `blocked_until_built` vs `blocked_until_unbuilt`.

Then, by the split's `status`:

| `status` | What to do |
|---|---|
| `READY-TO-RESUME` | Every blocker is built. **Propose only the deferred scope**, citing the `IS-###`. |
| `ACTIVE` with `resume_ready: true` | Every blocker now carries a `BUILT:` note but no `--refresh` has run since. Say so, and offer to run `/specclaw:bf-rebuild-plan --refresh` (which flips the state mechanically) before resuming. |
| `ACTIVE` with `resume_ready: false` | Blockers named in `blocked_until_unbuilt` are still unbuilt. Say which, and that the deferred scope genuinely cannot resume yet. Offer: propose some *other* remaining scope if any exists, wait, or — if the user says those blockers **are** built — write the `BUILT:` note into their status notes so the question isn't asked again. |

**Never re-propose completed scope.** The proposal's scope section covers the remainder only, and `proposal.md` carries `## Resumes Split` citing the `IS-###`. Rebuilding the finished slice from scratch is the failure this record exists to prevent — the whole point of `IS-###` is that choosing item-split must never make implementation history disappear.

2b. **Dependency check** (brownfield rebuilds only — inert everywhere else):

```bash
specclaw-bf-rebuild-collect bypass-check .specclaw <BL-###|--title "<the item title>">
```

Pass the `BL-###` if the user named one; otherwise pass the title. **If the JSON says `"applicable": false`, skip straight to step 3** — there is no backlog, or this change isn't a backlog item, and nothing below applies. Relay the `reason` only when it reports an *ambiguous* title (the user has to name the id); the other reasons are just "this isn't a brownfield backlog item" and need no comment.

Otherwise, act on each dependency's `action`:

| `action` | What it means | What to do |
|---|---|---|
| `ok-built` | The dependency carries a declared `BUILT:` note | Nothing. Mention it in passing. |
| `covered-by-active-stub` | An `ST-###` already fakes it *for this item* | Nothing new to choose. Name the `ST-###` in the proposal's bypass section. |
| `same-module-prerequisite` | Unmet, and in **this item's own module** | **Refuse.** Not bypassable — see below. |
| `stub-exists-not-consumed` | A stub fakes this dependency, but for other items | Offer to add this item to that entry (`stub-update --consumed-by-add`) rather than mint a second stub for the same thing. Still the human's call. |
| `needs-bypass` | Unmet, cross-module, no stub | **Elicit** — see below. |
| `dependency-struck` | The dependency was struck from the backlog | Not a dependency any more. Say so; the backlog's `Depends on:` is stale. |
| `dependency-unknown` | The id isn't in the backlog at all | Report it as a backlog integrity problem. Do **not** treat it as either met or unmet. |
| `deferred-by-split` | A non-`COMPLETE` `IS-###` already defers the scope needing it | **Nothing to choose.** Name the `IS-###`. **Do not offer the strategies again** — the human already decided this, and accepting a second answer would produce two records of one deferral. |

**If any `same-module-prerequisite` exists, stop.** Name the prerequisite and say plainly that a same-module dependency is the item's own groundwork, not a cross-boundary wait — stubbing it would mean stubbing part of the very thing being built. The options are to build the prerequisite first, or to propose a smaller slice of this item that doesn't need it. Do not offer the four strategies for it, and do not create a registry entry.

**If any `needs-bypass` exists, stop and ask.** Present *each* unmet dependency separately with these six options, and **ground every strategy sketch in what that dependency actually is** — read its backlog entry and its module's row in `module-map.md` first. Generic sketches ("stub the interface") are useless to someone deciding; a sketch for an auth module reads like *"dev-only auth stub issuing a fixed seeded user + role"*, for a ledger module like *"seeded ledger rows so posting has something to read"*.

1. **`stub-interface`** — <sketch grounded in this dependency>
2. **`mock-data`** — <sketch>
3. **`feature-flag`** — <sketch>
4. **`item-split`** — **propose a specific vertical slice**, not a layer cut. Name exactly what ships now and exactly what waits: *"the grid renders, calls a real endpoint, runs a real query against real persisted data — and only the auth integration waits for BL-001/BL-003."* Say when this looks like the best fit: nothing is faked, so nothing is tainted and nothing needs retiring.
   - **Prefer a thin end-to-end capability over a horizontal stack cut, and say so in the offer.** A vertical slice delivers something a user can open. A horizontal cut — every layer below the UI ships and the UI waits, or the reverse — produces an item that looks nearly finished and delivers nothing anyone can use, with its acceptance basis unmet and no fixture able to notice. The dependency that is actually missing is usually one seam, not one layer.
5. **The dependency is actually built** — specclaw records no built state, so it genuinely cannot tell. If the user says it is, offer to write `BUILT: <their evidence>` into that item's `**Status notes (human-added):**` block in `rebuild-backlog.md`, so the question isn't asked again.
6. **Abort and follow the recommended order** — build the dependency first. Always a legitimate answer, and often the right one.

**Never pick for the user, never default, and never proceed on silence.** A bypass is an explicit human choice (`templates/CONTRACT.md` (m.2)); this is the ask-don't-guess rule applied to dependencies. If the user answers only some of the dependencies, ask about the rest — don't infer the same strategy carries across.

For each chosen **stub** bypass (options 1–3), append the registry entry:

```bash
specclaw-bf-rebuild-collect stub-append .specclaw \
  --substitutes "BL-014 (MOD-005)" --strategy stub-interface \
  --consumed-by "<this item's BL-###>" --chosen-by "<user's name>, <YYYY-MM-DD>" \
  --summary "<the one-line sketch they chose>" [--mock-seed <path>]
```

It prints the new `ST-###`. `Fakes` and `Implementation` stay `not yet implemented` — those are the build step's to fill in with a real `file:line`, and writing them now would be inventing a citation. Ask the user for their name if you don't have it; the entry is refused without one.

### If the user chooses `item-split`

**A split is not a stub and does not go in `module-stubs.md`.** `stub-append --strategy item-split` is refused by name. Read `$CLAUDE_PLUGIN_ROOT/references/split-discipline.md`, then:

**First, state the split back and get it confirmed — itemised, not summarised.** Two lists, from the item's own acceptance basis (`bypass-check` reports it as `item.acceptance_basis_rules`):

- **Implemented now:** the scope, and the `DR-###` rules it covers.
- **Deferred:** the scope, and the `DR-###` rules it covers.

Every rule in the item's acceptance basis must appear in exactly one list. `split-append` refuses a partition with a rule in both halves, a rule in neither, or a rule the item doesn't cite — and the refusal is not a formality: a rule in neither half is scope nobody owns, so nothing can later tell whether it shipped.

**If the split removes an entire major layer, say so as a consequence and require explicit confirmation before recording it.** For a screen-bearing item losing its UI (`bypass-check` reports `item.screen_bearing`), the sentence to put in front of the user names what goes unmet:

> This split defers the entire UI layer. BL-010 renders SCR-004, so it would ship with nothing a user can see, and its UI acceptance basis (SCR-004, TK-001) would go unmet. Confirm explicitly if that is what you want.

`split-append` **refuses** that split without `--layer-removal-confirmed-by "<name>, <date>"`, so this is enforced, not merely advised. Do not supply that flag on your own initiative or reuse the chooser's name to satisfy it — it is a second, separate attestation, and the whole reason the field exists is that somebody was asked.

Then record it:

```bash
specclaw-bf-rebuild-collect split-append .specclaw \
  --item BL-010 --module MOD-002 \
  --reason "BL-001/BL-003 authentication and route guards are not built" \
  --unmet-deps "BL-001, BL-003" \
  --implemented-now "patient listing · search/filter · active-prescription query · paging · backend API · React Patient Grid" \
  --deferred "BL-001 authentication integration · BL-003 route-guard integration" \
  --rules-implemented "DR-014, DR-015" --rules-deferred "DR-002" \
  --layers-implemented "ui, api, domain, persistence" --layers-deferred "auth-integration" \
  --blocked-until "BL-001, BL-003" \
  --chosen-by "<user's name>, <YYYY-MM-DD>" --change "<change-name>" \
  --summary "<one line: which item was split, and what waits>"
```

It prints the new `IS-###`. `Evidence` and `Replay evidence` stay `not yet merged`/`not yet replayed` — the build and replay steps fill those in, and writing them now would be inventing a citation.

**What to tell the user after recording it**, in one breath: the item will render `⚠ PARTIALLY BUILT` in `rebuild-backlog.md`, an `/specclaw:bf-replay --item BL-###` run will report **PARTIAL** and cannot be the item's final acceptance, and the split returns automatically — `--refresh` flips it to `READY-TO-RESUME` as soon as every blocked-until item carries a declared `BUILT:` note. Nothing is tainted: a split fakes nothing.

3. Generate `proposal.md` from `$CLAUDE_PLUGIN_ROOT/templates/proposal.md`. Fill in: problem statement, proposed solution, scope (in / out), impact (files, complexity, risk), open questions.
   - **`## Dependency Bypass`:** one bullet per **stubbed** dependency, citing the `ST-###` from step 2b, the strategy, the chooser and date, and the concrete sketch. **Omit the whole section** when there was no stub bypass — which is the normal case.
   - **`## Item Split`:** present only when this proposal recorded an `IS-###` in step 2b. Cite the id, what ships now, what is deferred, the rules each half covers, what unblocks the remainder, and the chooser — plus the layer-removal confirmer when there was one. The scope section's **out** list must name the deferred scope explicitly; a split whose deferral appears nowhere in the scope section is a split the spec will quietly widen.
   - **`## Resumes Split`:** present only when step 2a found a non-`COMPLETE` split. Cite the `IS-###`, what the earlier slice built, its change/PR/replay evidence, and state that this proposal covers the remainder only.
   - Also generate `.specclaw/changes/<change-name>/status.md` from `$CLAUDE_PLUGIN_ROOT/templates/status.md`. Fill in: `{{title}}` and `{{change_name}}`, `{{date}}` / `{{updated}}` with today's date, and the phase rows — set Proposal status to `🟡 Draft` and the remaining phases (Spec, Design, Tasks, Build, Verify) to pending. Leave task/agent/issue sections empty for now.
4. Present the proposal to the user for review.
5. Update `.specclaw/STATUS.md` via `specclaw-update-status .specclaw`.
6. **GitHub sync** (if `github.sync: true` in `config.yaml`): run `specclaw-gh-sync create .specclaw <change-name>` to create a GitHub Issue for the proposal. Validation (proposal.md must exist) is enforced by `specclaw-validate-change`.
7. **Azure Boards sync** (if `azdo.boards.sync: true` in `config.yaml`): run `specclaw-azdo-issue create .specclaw <change-name>` to create a Work Item. Idempotent — safe to re-run.

Do not proceed to `/specclaw:plan` until the user has approved the proposal.

## What the dependency check never does

It never decides that a bypass is warranted, never picks a strategy, and never writes a registry entry the user didn't choose. `bypass-check` classifies; the human decides; bash records. An agent that picks a "sensible default" here has quietly converted a tracked, dated, attributable decision into an untracked one — which is the single failure mode this whole mechanism exists to prevent.

It also never infers that a dependency is built from prose. Only a declared `BUILT:` line in the item's own status notes counts. "Done last week", "shipped in #42", a ✅ — none of these are read, deliberately: a false positive here silently skips the elicitation that would have caught the unmet dependency.

**And a split never widens on its own.** The split the user selected is the split that happens. If drafting the proposal suggests the chosen partition is wrong — a rule sits awkwardly, a layer turns out to be needed — **stop and hand it back**. Moving one more rule into the deferred half without asking is precisely how a screen-bearing item once lost its entire frontend, and it is the reason `split-append` refuses a partition that does not account for the item's acceptance basis exactly.

## What the foundation gate never does

It never creates a foundation, never infers that one exists from the presence of source files, and never decides that a project doesn't need one. It reads a manifest that `/specclaw:bf-bootstrap` wrote, or it reads a `--not-applicable` declaration a named human made. Absent both, it stops and names the command — the same UX pattern as every other precondition gate in the pipeline.

It fails **closed**: a manifest that can't be parsed, carries an unknown schema, or claims readiness while recording a failed smoke check reports not-ready with the reason. Passing a gate on a file nobody could read would defeat the point of having it.

Nothing above applies to a project with no `rebuild-backlog.md`. Both `foundation-check` and `bypass-check` return `applicable: false` and propose behaves exactly as it always has.

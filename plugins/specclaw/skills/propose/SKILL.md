---
description: Draft a new change proposal. INVOKE IMMEDIATELY whenever the user mentions a proposal, feature idea, change request, new initiative, or anything they want to add/build/implement — do NOT gather details conversationally first. The skill itself will ask for any missing information after invocation. Creates .specclaw/changes/<name>/proposal.md with problem statement, solution, scope, impact, and open questions. The first step in the propose → plan → build → verify → pr lifecycle.
---

# specclaw propose

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized; auto-inits using the current directory's basename as the project name).

Create a new proposal for a change.

**If the user hasn't yet provided enough detail to draft the proposal (e.g. they just said "i have a proposal" with no specifics), ask once for the essentials inside this skill — what's the idea, what problem does it solve — then proceed to the steps below. Do not wait for a separate turn to invoke this skill.**

1. Slugify the user's idea into a `<change-name>` (lowercase, hyphens, no spaces).
2. Create `.specclaw/changes/<change-name>/`.

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

**If any `same-module-prerequisite` exists, stop.** Name the prerequisite and say plainly that a same-module dependency is the item's own groundwork, not a cross-boundary wait — stubbing it would mean stubbing part of the very thing being built. The options are to build the prerequisite first, or to propose a smaller slice of this item that doesn't need it. Do not offer the four strategies for it, and do not create a registry entry.

**If any `needs-bypass` exists, stop and ask.** Present *each* unmet dependency separately with these six options, and **ground every strategy sketch in what that dependency actually is** — read its backlog entry and its module's row in `module-map.md` first. Generic sketches ("stub the interface") are useless to someone deciding; a sketch for an auth module reads like *"dev-only auth stub issuing a fixed seeded user + role"*, for a ledger module like *"seeded ledger rows so posting has something to read"*.

1. **`stub-interface`** — <sketch grounded in this dependency>
2. **`mock-data`** — <sketch>
3. **`feature-flag`** — <sketch>
4. **`item-split`** — <what specifically would ship now vs. wait>. Say when this looks like the best fit: nothing is faked, so nothing is tainted and nothing needs retiring.
5. **The dependency is actually built** — specclaw records no built state, so it genuinely cannot tell. If the user says it is, offer to write `BUILT: <their evidence>` into that item's `**Status notes (human-added):**` block in `rebuild-backlog.md`, so the question isn't asked again.
6. **Abort and follow the recommended order** — build the dependency first. Always a legitimate answer, and often the right one.

**Never pick for the user, never default, and never proceed on silence.** A bypass is an explicit human choice (`templates/CONTRACT.md` (m.2)); this is the ask-don't-guess rule applied to dependencies. If the user answers only some of the dependencies, ask about the rest — don't infer the same strategy carries across.

For each chosen bypass, append the registry entry:

```bash
specclaw-bf-rebuild-collect stub-append .specclaw \
  --substitutes "BL-014 (MOD-005)" --strategy stub-interface \
  --consumed-by "<this item's BL-###>" --chosen-by "<user's name>, <YYYY-MM-DD>" \
  --summary "<the one-line sketch they chose>" [--mock-seed <path>]
```

It prints the new `ST-###`. `Fakes` and `Implementation` stay `not yet implemented` — those are the build step's to fill in with a real `file:line`, and writing them now would be inventing a citation. Ask the user for their name if you don't have it; the entry is refused without one.

3. Generate `proposal.md` from `$CLAUDE_PLUGIN_ROOT/templates/proposal.md`. Fill in: problem statement, proposed solution, scope (in / out), impact (files, complexity, risk), open questions.
   - **`## Dependency Bypass`:** one bullet per bypassed dependency, citing the `ST-###` from step 2b, the strategy, the chooser and date, and the concrete sketch. **Omit the whole section** when there was no bypass — which is the normal case.
   - Also generate `.specclaw/changes/<change-name>/status.md` from `$CLAUDE_PLUGIN_ROOT/templates/status.md`. Fill in: `{{title}}` and `{{change_name}}`, `{{date}}` / `{{updated}}` with today's date, and the phase rows — set Proposal status to `🟡 Draft` and the remaining phases (Spec, Design, Tasks, Build, Verify) to pending. Leave task/agent/issue sections empty for now.
4. Present the proposal to the user for review.
5. Update `.specclaw/STATUS.md` via `specclaw-update-status .specclaw`.
6. **GitHub sync** (if `github.sync: true` in `config.yaml`): run `specclaw-gh-sync create .specclaw <change-name>` to create a GitHub Issue for the proposal. Validation (proposal.md must exist) is enforced by `specclaw-validate-change`.
7. **Azure Boards sync** (if `azdo.boards.sync: true` in `config.yaml`): run `specclaw-azdo-issue create .specclaw <change-name>` to create a Work Item. Idempotent — safe to re-run.

Do not proceed to `/specclaw:plan` until the user has approved the proposal.

## What the dependency check never does

It never decides that a bypass is warranted, never picks a strategy, and never writes a registry entry the user didn't choose. `bypass-check` classifies; the human decides; bash records. An agent that picks a "sensible default" here has quietly converted a tracked, dated, attributable decision into an untracked one — which is the single failure mode this whole mechanism exists to prevent.

It also never infers that a dependency is built from prose. Only a declared `BUILT:` line in the item's own status notes counts. "Done last week", "shipped in #42", a ✅ — none of these are read, deliberately: a false positive here silently skips the elicitation that would have caught the unmet dependency.

Nothing above applies to a project with no `rebuild-backlog.md`. `bypass-check` returns `applicable: false` and propose behaves exactly as it always has.

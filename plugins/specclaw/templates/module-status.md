# Module Status: {{title}}

**Generated:** {{date}}
**Module map:** {{map_status}}

<!--
  A STATUS VIEW, NOT EVIDENCE — and the one document in .specclaw/ that is
  deliberately exempt from archive-then-replace.

  Every other generated document here is archived before being replaced,
  because each one is a finding someone may later need to cite: an analysis
  snapshot, a designed scenario, a recorded manifest, a replay verdict. This
  file is none of those. It contains no finding of its own — every number in
  it is recomputed, in full, from artifacts that ARE archived:

    module-map.md      the module roster, dependencies, and confirmation state
    rebuild-backlog.md each item's declared module and Gate state
    scenarios.md       which scenarios declare which module
    manifest.json      which of those scenarios have a captured fixture
    run-metadata.json  the verdict of each retained replay run
    pending-questions.md / clarifications.md  open questions naming a module

  So there is nothing here to preserve: an older copy would be a stale
  rendering of documents whose own history is already kept. Regenerating it
  wholesale every run is the correct behaviour, and archiving it would
  accumulate misleading near-duplicates of a view anyone can reproduce in a
  second. Nothing computes from this file, and no command reads it.

  It is READ-ONLY with respect to every input: it writes exactly one file
  and modifies nothing else.

  ── Column definitions, stated because "how many items" has more than one
  ── honest answer ───────────────────────────────────────────────────────

  Backlog items (planned/total)
      planned = ACTIVE items declaring this module.
      total   = planned + that module's struck tombstones + its deferred
                items. So 8/11 means eight to build, three accounted for
                and deliberately not being built.
      Items with no usable **Module:** field are counted under Unassigned
      at the foot of the table, never distributed into a module by guesswork.

  Scenarios (captured/designed)
      designed = GM-### scenarios declaring this module, tombstones excluded
                 (a WITHDRAWN id is a claim on the id, not a scenario).
      captured = those with a fixture recorded in manifest.json.
      A scenario whose rules span modules is counted under EVERY module it
      declares — the same cross-module rule /specclaw:bf-replay applies — so
      these columns intentionally do not sum to the corpus total.

  Latest replay verdict
      The newest MODULE-SCOPED run (/specclaw:bf-replay --module MOD-###)
      that retained evidence, read from that run's own run-metadata.json.

      DELIBERATE LIMITATION: a change-scoped or --all run also exercises a
      module's fixtures, and its report carries a per-module rollup — but it
      records no per-module verdict in its metadata, so it cannot appear
      here. This column reads "no module-scoped run" in that case rather
      than borrowing a corpus verdict and presenting it as the module's own.
      Read that run's report's own Module Rollup section for it.

      A run invoked with --discard retained no evidence and is therefore
      invisible here, by design.

  Stub-tainted items
      How many of this module's items have a LATEST replay verdict that was
      earned while a dependency-bypass stub (templates/CONTRACT.md (m)) stood
      in for a module that is not built yet.

      LATEST is load-bearing. For each item, the newest retained run that
      COVERED it wins — so an item tainted in March and re-run clean in April
      counts as clean. Reading only "which runs were tainted" would keep
      reporting March forever.

      Unlike the verdict column, this counts runs at EVERY scope. A
      change-scoped run records no per-module verdict, but it does record
      exactly which items it exercised and which of those rested on a stub,
      and that is a per-item fact no scope distorts.

      An item consuming an ACTIVE stub that no run has ever exercised is NOT
      counted here — it has no verdict at all, tainted or otherwise. Those
      are named under the stub table instead, because "not yet checked" and
      "checked against a placeholder" are different states and collapsing
      them would overstate what has been verified.

      When this column is non-zero the verdict column reads PASS* rather
      than PASS. The two travel together so neither can be read alone.

  Open questions
      OPEN entries in pending-questions.md plus unanswered entries in
      clarifications.md whose text names this MOD-###. These are soft
      blocks: they never stop a command, they mark what is provisional.

  ── What this view does NOT claim ───────────────────────────────────────

  Nothing here says a module is "done". specclaw records no built state for
  a backlog item beyond a status note a human typed, so every number is a
  statement about planning, capture, and comparison coverage — not about
  completion. A module whose every fixture PASSed is a module whose recorded
  behaviour matched; it is not a module signed off.

  And a module showing PASS* has not even matched cleanly on its own terms:
  some of what it was compared against was a deliberate placeholder for a
  module nobody has built yet.
-->

## Modules

{{module_table}}

{{unassigned_note}}

## Stubs In Effect By Module

<!--
  Every ACTIVE dependency-bypass stub, keyed by the module it FAKES — so
  "who is waiting on the real MOD-005?" is one lookup rather than a scan of
  every item's dependency list.

  Read the Consumed by column as the answer: those are the items already
  built against a placeholder for that module, whose verdicts carry an
  asterisk until it lands and they are re-replayed.

  ACTIVE only. A RETIRING entry is mid-verification and taints nothing; a
  RETIRED one is history. Both stay in module-stubs.md forever — the record
  that an item was built out of order outlives the stub — but neither is
  something anyone is still waiting on, which is what this table is for.

  The module an entry fakes is the MOD-### its Substitutes field names, or
  the module owning the BL item it names. Never inferred from anything else.
-->

{{stubs_by_module}}

## Notes

{{notes}}

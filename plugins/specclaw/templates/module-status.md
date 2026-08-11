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
-->

## Modules

{{module_table}}

{{unassigned_note}}

## Notes

{{notes}}

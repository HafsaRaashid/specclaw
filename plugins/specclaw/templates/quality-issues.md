# Quality Issues: {{title}}

**Path measured:** {{path}}
**Last updated:** {{date}}

<!--
  THE QI-### REGISTRY. One ### QI-### entry per code-quality hotspot that
  reached the registering severity band, ever.

  ── ONE WRITER, AND IT IS NOT A HUMAN ────────────────────────────────────

  Unlike module-stubs.md and item-splits.md — which record human decisions and
  are therefore strictly append-only, edited field by field, never rewritten —
  this registry has exactly one writer: the quality collector. It rewrites the
  document in full on every run, because every entry's Status, Value and Last
  checked are recomputed from a fresh measurement and a stale Status here would
  be indistinguishable from a hotspot nobody has got round to.

  That wholesale rewrite is SAFE ONLY BECAUSE OF THE INVARIANT BELOW, and the
  invariant is the whole reason this file exists rather than the numbers just
  living in quality.json. Do not hand-edit entries: the next run overwrites
  them. Anything a human needs to say about a hotspot belongs in the change
  that fixes it.

  ── THE INVARIANT: NO ID IS EVER LOST ────────────────────────────────────

  Every run reads this file BEFORE writing anything, and the document it writes
  contains an entry for every key it read, plus one for every newly-found
  hotspot. A key that is still a hotspot keeps its id and its First seen date;
  a key that no longer exceeds its threshold is written back with Status
  `resolved`. Nothing is dropped, so the id space only ever grows.

  QI-### joins MOD/GM/DR/CQ/SQ/UQ/BL/ST/IS under templates/CONTRACT.md (c):
  ids are assigned once, sequentially, and are never renumbered, reused or
  reformatted across any regeneration.

  ── NEVER ARCHIVED ───────────────────────────────────────────────────────

  This document carries the ST-###/IS-### carve-out from (c)'s archive rule,
  and for the same reason: a registry that gets archived and regenerated is
  precisely the silent re-pointing (c) exists to prevent. quality.json IS
  archived on every run; this file is not, and that asymmetry is deliberate —
  which is also why the registry lives here rather than inside the snapshot
  that gets rotated. quality.json's quality_issues[] is a regenerated
  PROJECTION of this file, never the source of it. One direction per fact.

  ── IDENTITY IS THE KEY FIELD, NEVER THE VALUE ───────────────────────────

  Key is the tuple  metric|file|function|module  — empty for the levels a
  metric does not have (a file-length hotspot has no function; a duplication
  hotspot has neither file nor function). It is what makes a hotspot the same
  hotspot across runs. The measured Value is explicitly NOT part of identity:
  values move on every commit, and keying on one would mint a fresh id every
  run and make two reports months apart incomparable — which is the only thing
  a permanent id is for.

  A RENAMED FILE therefore yields a new QI-### plus a resolved old one. That is
  the intended behaviour and not a defect: inferring the rename would carry an
  id, and its whole history, onto code nobody measured.

  ── STATUS ───────────────────────────────────────────────────────────────

    open      the hotspot exceeded its threshold in the most recent run
    resolved  it did not

  `resolved` is not deletion and is not absolution. The entry stays here
  forever, because "this used to be a hotspot" is itself a finding — it is how
  anyone can later tell a module that was cleaned up from one that was never
  bad. A resolved entry that exceeds its threshold again flips back to `open`
  under its ORIGINAL id, with its original First seen date intact.

  ── WHICH SEVERITIES GET REGISTERED ──────────────────────────────────────

  Controlled by config.yaml's `quality.register_severity`, default HIGH. Ids
  are permanent and entries are never deleted, so a registry admitting every
  WARN on a large legacy tree would accumulate thousands of rows that outlive
  the code they describe. WARN findings are still counted in every module
  rollup — they are simply not individually immortalised.

  ── PER-ENTRY STRUCTURE ──────────────────────────────────────────────────

  ### QI-###

  - **Key:** <metric|file|function|module — the identity tuple>
  - **Module:** <MOD-###, or MOD-UNASSIGNED when no module cites this file>
  - **File:** <repo-relative path, or — for a module-level metric>
  - **Function:** <function name, or — for a file- or module-level metric>
  - **Metric:** <complexity | function_length | file_length | duplication>
  - **Value:** <the measured value at the last check, or — when resolved>
  - **Severity:** <WARN | HIGH at the last check, or — when resolved>
  - **Status:** <open | resolved>
  - **First seen:** <ISO-8601 of the run that first registered it — never
    updated afterwards, on any subsequent run, for any reason>
  - **Last checked:** <ISO-8601 of the most recent run>

  ── NOTHING IS BLOCKED BY ANYTHING IN HERE ───────────────────────────────

  No command reads this file, and no command's behaviour changes because of an
  entry in it. It is a record, not a gate.
-->

{{quality_issues}}

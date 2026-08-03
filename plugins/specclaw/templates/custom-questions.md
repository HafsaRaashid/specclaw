# Custom Questions

<!--
  Per-repo custom questions for /specclaw:clarify. This file is never
  created or written by /specclaw:clarify itself — copy this starter into
  .specclaw/analysis/custom-questions.md in YOUR target repo and edit it
  there; clarify only ever *reads* it.

  One heading per question. Everything below a heading up to the next
  heading is that question's body — sloppy authoring is fine, clarify
  defaults what's missing rather than erroring:
    - No "Type:" line        -> defaults to DECISION
    - No "Blocking:" line     -> defaults to no
    - No "Options:" list      -> rendered as "(not specified by the
                                  author — describe options when answering)"
    - No "Proposed default:"  -> rendered as "unknown — not specified by
                                  the author"

  Each heading is ingested as a new UQ-NNN the first time clarify sees it,
  numbered in file order. Once ingested, the heading's exact text is what
  clarify matches on for de-duplication — editing an already-ingested
  question's wording or body in THIS file does NOT retroactively rewrite
  the already-rendered UQ-NNN in clarifications.md (that file is the
  system of record from then on); it reads as a brand new question and
  gets a new ID instead. To change an already-ingested question, edit it
  directly in clarifications.md.
-->

## Should offline mode be supported?

Type: SCOPE
Blocking: no
Options:
- Yes — add offline-first sync.
- No — always-online is fine for this rebuild.
Proposed default: No — no legacy behaviour requires offline support.

## Do we need a mobile app eventually?

Options:
- Yes — plan the architecture to support one later.
- No — web-responsive is enough.

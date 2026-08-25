# Code Quality Report: {{title}}

**Path measured:** {{path}}
**Date measured:** {{date}}
**Scope:** {{scope}}

<!--
  WRITTEN BY THE QUALITY NARRATION AGENT, FROM ONE JSON ARTIFACT AND NOTHING
  ELSE. Every status, severity and rollup below was computed in bash before this
  document existed. Nothing here re-derives, adjusts or second-guesses one.

  ── CLIENT-SAFE BODY ────────────────────────────────────────────────────────

  Everything above "## Internal provenance" must survive being pasted into a
  client deck. So the body names no internal command, agent, script, or the
  framework itself.

  This is the ONE document in .specclaw/analysis/ that hides its producing
  command. Every other one names it freely. That is deliberate and is not a
  defect to be fixed: a quality report is the artifact most likely to be
  forwarded outside the team, and a reader who cannot tell an internal pipeline
  name from a finding will treat both as noise.

  Two things it does NOT mean:

    - Measuring-tool names belong in the body. "Complexity was measured with
      lizard" is a methodology statement a client is entitled to, and removing
      it makes every number unauditable. It is the internal pipeline that stays
      out, not the instrument.

    - It is not a licence to be vague. "This module's largest function has a
      cyclomatic complexity of 34 against a threshold of 20" is client-safe.
      "Quality concerns were identified" is just useless.

  ── COVERAGE COMES FIRST, AND IT IS NOT A CAVEAT ────────────────────────────

  The Measurement Coverage section sits ABOVE the findings, deliberately. A
  reader who takes a module rollup at face value without knowing that complexity
  was unmeasurable for a third of the tree has been misled, and putting coverage
  at the bottom under "limitations" is exactly how that happens.

  NOT-MEASURED is a result, never a gap to be filled. No value in this document
  is ever estimated, extrapolated or inferred. The three reasons and what each
  one actually means to a reader:

    language_unsupported  no available tool parses this language for this
                          metric. Permanent; installing something does not fix
                          it.
    tool_missing          the tool that measures this was not installed when
                          the measurement ran. Fixable, and worth saying so.
    parse_error           the tool ran and could not read these files. State
                          the count; do not speculate.

  ── MODULE NUMBERS DESCRIBE THE CITED SLICE ─────────────────────────────────

  Nothing in this project maps a source file to a module. The module map maps
  modules to entities, rules, services and screens; the file-to-module join
  therefore uses only the file paths each module cites in its own Evidence
  bullets, and Evidence is a sample of a boundary rather than an inventory of
  one.

  So a large MOD-UNASSIGNED bucket is the EXPECTED result on a map nobody has
  enriched, and it means each module's numbers cover its cited files rather than
  the whole module. Say so where the rollup is reported. Never redistribute
  unassigned files by guesswork — the remedy is more citations in the map.
-->

## Summary

{{summary}}

<!--
  Two or three sentences a delivery lead can act on: how much was measured, how
  many modules sit at HIGH, and the single thing most worth attention. No
  hedging, no throat-clearing.
-->

## Measurement Coverage

{{coverage}}

<!--
  Per language: file count, which metrics were computed, and every metric that
  was not — with its reason translated into plain language and its file count.
  Close with one concrete sentence naming the consequence, e.g. "cyclomatic
  complexity was not measurable for the 58 Pascal source files; those files
  report size and duplication only".

  Then the module-grouping caveat: how many files landed under MOD-UNASSIGNED,
  how many were cited by more than one module and therefore left unassigned, and
  whether the module grouping itself is confirmed or still a proposal.
-->

## Module Rollup

{{module_rollup}}

<!--
  One row per module: files, LOC, and the status of each measured dimension
  (complexity, function length, duplication, file length) plus the overall
  rollup. A dimension nobody could measure reads NOT-MEASURED — never PASS.
  Those are different claims, and collapsing them turns "we did not look" into
  "we looked and it was fine".

  Where a module's rollup rests on fewer dimensions than another's, say so on
  that row.
-->

## Thresholds Applied

{{thresholds}}

<!--
  The exact threshold values this run classified against, so any number above
  can be checked against the policy that produced it. A status without its
  threshold is an opinion.
-->

## Hotspots

{{hotspots}}

<!--
  Top N by severity then value (default 15), each with its permanent QI-### id,
  module, file, function, metric, measured value, and the threshold it crossed.

  QI ids are permanent and are never renumbered or reused, so the same hotspot
  carries the same id across every report — which is what makes two reports
  months apart comparable at all.

  If any entry is `resolved`, list those separately and say what it means: the
  hotspot no longer exceeds its threshold, and the id is kept rather than
  deleted so the history stays readable. A resolved entry is never presented as
  a current problem, and never dropped silently.

  An empty hotspot list is stated plainly — together with the coverage, because
  "nothing reached the threshold" reads very differently when half the tree was
  NOT-MEASURED.
-->

## Methodology

{{methodology}}

<!--
  Which tool produced which metric, how files were selected (and what was
  excluded: vendored, generated and dependency directories), and how a status
  band is assigned. Enough that a sceptical reader can reproduce the numbers.

  Also state plainly what this report does NOT claim: it measures structural
  properties of source code. It says nothing about whether the software is
  correct, whether it does what its users need, or whether it is fit to ship.
  A codebase can sit entirely at PASS and still be the wrong system.
-->

---

## Internal provenance

<!--
  DELETE THIS SECTION BEFORE THE REPORT LEAVES THE TEAM. It is the only place
  internal command, script and framework names appear, which is what makes the
  rest of the document safe to forward as-is.
-->

{{provenance}}

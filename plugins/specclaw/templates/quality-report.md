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

  ── SCOPE AND COVERAGE COME FIRST, AND NEITHER IS A CAVEAT ──────────────────

  The Scan Scope and Measurement Coverage sections sit ABOVE the findings,
  deliberately, and in that order. A reader who takes a module rollup at face
  value without knowing that complexity was unmeasurable for a third of the
  tree — or that a third of the tree was never in scope — has been misled, and
  putting either at the bottom under "limitations" is exactly how that happens.

  They answer two different questions and both have to be asked. Scope says
  which FILES were looked at; coverage says which METRICS could be computed for
  them. A file left out of the scan and a metric no tool could compute are both
  reported, never inferred, and never quietly netted off against each other.

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

## Scan scope

{{scan_scope}}

<!--
  WHAT WAS MEASURED, AND WHAT WAS DELIBERATELY NOT. Short — a paragraph and a
  small table — and it comes FIRST, ahead of coverage, because it answers the
  earlier question. Coverage says which metrics could be computed for the files
  that were looked at; this says which files were looked at.

  Read it from the artifact's `exclusions` block and from nowhere else:

    exclusions.categories       each category and whether it was applied
    exclusions.extra_excludes   this project's own additions
    exclusions.include_overrides  files deliberately measured despite matching
    exclusions.census.by_category  how many files each category accounted for
    files.enumerated / files.measured / files.excluded

  AN EXCLUDED FILE IS A DECISION, NOT AN ABSENCE. State the counts plainly and
  positively: "the scan measured 412 of the 1,806 files in the tree; 1,394 were
  outside its scope, of which 1,201 were dependency and build output, 158 were
  test code and 35 were generated". Never write it as a caveat, an apology, or a
  limitation, and never leave it implied — a reader who assumes every file was
  measured has been misled just as badly as one who assumes every metric was.

  Say in one sentence why production code is what gets measured: a hotspot in a
  generated migration or a vendored dependency is a finding about a code
  generator or a third party, not about this codebase, and leaving it in
  distorts every module rollup it lands in.

  A `disposition` of `measured_separately` is NOT an exclusion. Those files were
  measured, into their own bucket, and are reported apart from the production
  modules rather than left out. Say which bucket and where its numbers are.

  If `include_overrides` is non-empty, name what was forced back in and note
  that it was a deliberate choice.

  The census counts FILES, not lines. Do not convert one into the other, do not
  estimate the volume of code skipped, and do not describe the excluded share as
  a percentage of the codebase's size — the artifact does not carry that figure
  and inventing it is exactly the kind of number that gets quoted back.
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

## Top Duplication Hotspots

{{duplication_hotspots}}

<!--
  WHERE the duplication is. The Module Rollup above says how MUCH — a
  percentage per module — and a percentage is not something anyone can act on.
  This section names the pairs.

  Read it from `duplication_clones` and nowhere else. Every entry is already
  scoped, ordered and thresholded; render, do not re-rank.

  One line per clone, top `capture.clone_report_top_m` by duplicated lines:

    `src/Billing/InvoiceCalc.cs:44-59` ↔ `src/Quotes/QuoteCalc.cs:58-73`
    — 16 duplicated lines — MOD-004

  Append, only when the artifact carries them:
    - ` — FunctionName()` after a side whose `function` is non-null
    - ` — cross-module` when `cross_module` is true, and name BOTH module ids
      (`MOD-001 ↔ MOD-004`) rather than one — a clone spanning two modules is a
      coupling finding, and showing one id hides half of it
    - ` — QI-###` when `qi_id` is non-null

  NEVER SHOW THE DUPLICATED CODE. The artifact deliberately does not carry it,
  so there is nothing to paste even by accident — but do not go and read the
  files to quote it either. Line ranges point at the code for anyone who wants
  it; a report that embeds source is one that cannot be forwarded.

  A `function` of `null` means no function could be attached MECHANICALLY —
  either the language has no function-level measurement here, or the clone
  straddles two functions, or nothing met the containment rule. Render the
  file:range alone. Never substitute the nearest function name, never infer one
  from the file name, and do not remark on the absence line by line.

  TRUNCATION IS STATED, not implied. When `census.clones_captured` is less than
  `census.clones_in_scope`, close with one line naming both numbers and the
  total duplicated lines — e.g. "showing the 10 largest of 137 clone pairs
  found in scope, covering 4,210 duplicated lines in total". When
  `census.clones_outside_scope` is non-zero, say that too: those pairs had at
  least one side outside the measured scope and were not examined.

  ZERO CLONES IS A RESULT. Say plainly that no duplicate blocks were found at
  or above the detection threshold, and say it next to the coverage — "no
  clones found" means much less when duplication was NOT-MEASURED for most of
  the tree. Do not omit the section.
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

  `excluded-by-scope` IS NOT `resolved`, and the two never share a list. It
  means the file that hotspot names is no longer inside the scan scope — the
  measurement stopped, nothing was fixed. Give it its own short list, name the
  category that excluded each one, and say the difference in a sentence. A
  reader who reads "excluded-by-scope" as "dealt with" has been told the
  opposite of the truth, and it is the flattering direction, which is why it
  needs saying rather than implying.

  An empty hotspot list is stated plainly — together with the coverage, because
  "nothing reached the threshold" reads very differently when half the tree was
  NOT-MEASURED.
-->

## Methodology

{{methodology}}

<!--
  Which tool produced which metric, how files were selected, and how a status
  band is assigned. Enough that a sceptical reader can reproduce the numbers.

  On selection, state the two facts that make the numbers reproducible: the
  exclusion set was applied ONCE, at file selection, and every tool measured the
  identical resulting file list — so the complexity scan and the duplication
  percentage share a denominator rather than each having their own. The full
  scope is in the Scan Scope section above; do not restate the category tables
  here, just say the mechanism.

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

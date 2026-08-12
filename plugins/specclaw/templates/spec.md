# Spec: {{title}}

**Change:** {{change_name}}
**Created:** {{date}}
**Status:** 🟡 Draft

## Overview

{{overview}}

## Requirements

### Functional Requirements

{{functional_requirements}}

### Non-Functional Requirements

{{non_functional_requirements}}

## Acceptance Criteria

Each criterion must pass for the change to be considered complete.

<!--
  WHEN THIS CHANGE BYPASSES A DEPENDENCY (see ## Bypassed Dependencies below),
  every criterion carries one of two labels, and no criterion may go unlabelled:

    - [real]           verified against real behaviour.
    - [stub: ST-###]   verified only against what that stub fakes.

  A [stub: ST-###] criterion is a weaker claim than it looks, and the label is
  what stops it reading as a strong one. "Approval succeeds for an admin user"
  verified against a stub that always returns an admin proves the approval
  path runs — not that the real auth module will ever produce that user.

  Labels are omitted entirely on a change with no bypass. They are not
  decoration: /specclaw:build reads them to know which criteria its stub work
  has to satisfy, and a reviewer reads them to know which parts of a green
  build are actually load-bearing.
-->

{{acceptance_criteria}}

## Edge Cases

{{edge_cases}}

## Dependencies

{{dependencies}}

## Bypassed Dependencies

<!--
  PRESENT ONLY when proposal.md carries a ## Dependency Bypass section. Omit
  the whole thing otherwise.

  Carried forward from the proposal by /specclaw:plan — the spec is where a
  bypass stops being a scheduling decision and becomes a set of build
  obligations. One subsection per ST-###:

    ### ST-001 — <what it fakes, for whom>

    - **Substitutes:** BL-014 (MOD-005 — Auth)
    - **Strategy:** stub-interface
    - **Stands in with:** <the concrete sketch the human chose>
    - **Scoping mechanism:** <the repo's own dev/test isolation mechanism this
      stub will use — named concretely, because the acceptance criterion below
      has to be checkable against it>
    - **Criteria verified against this stub:** AC-3, AC-4
    - **Retires when:** BL-014 is built and its consumers re-replay clean.

  TWO CRITERIA ARE MANDATORY per stub, and both belong in ## Acceptance
  Criteria above so they are actually gated:

    1. The dev/test-scoping assertion, naming the mechanism — e.g. "a
       production-profile boot resolves the real IAuthProvider or fails to
       start; the ST-001 stub is not registered outside Development."
       "The stub is dev-only" is NOT acceptable: it restates the rule instead
       of giving a reviewer something to check.
    2. The registry-completion obligation: ST-001's Fakes and Implementation
       fields carry the real file:line once the stub exists.

  See references/stub-discipline.md for the hard rule these enforce.
-->

{{bypassed_dependencies}}

## Notes

{{notes}}

# Golden-Master Contract

This is the **only** stack-related artifact in the specclaw plugin. `bf-baseline`
and `bf-replay`'s bash collectors are 100% stack-blind — they never detect a
framework, never glob for a project file, never invoke a toolchain by name.
All stack intelligence lives in the `bf-baseline-designer` and `bf-replay-mapper`
agents, which identify the legacy/rebuild stack themselves, per run, by reading
the repo. Every generated artifact — harness code, replay tests, manifests —
must conform to the field names and schemas below regardless of which
language or framework produced it. Never rename, reshape, or reformat any of
these; a rename breaks a downstream reader silently (the field just reads
back empty), not with an error.

**This document is a vocabulary, never a dictionary.** It fixes the *shape* of
what every stack must emit. It never lists a framework's exception types, a
project's error codes, or a mapping between them — those are per-project facts
that live in the target repo (`.specclaw/baseline/error-map.md`, section (h)),
authored at run time by the agents that actually read that repo. If you are
ever tempted to add a stack name or an error name to this file, that is the
signal you are writing the wrong artifact.

## (a) Fixtures

`.specclaw/baseline/fixtures/<GM-ID>.json` — exactly these top-level fields,
verbatim names, no others required, none omitted:

```json
{
  "scenario_id": "GM-019",
  "captured_at": "2026-08-07T10:15:00Z",
  "anchor_date": "2026-08-07",
  "legacy_commit_sha": "a1b2c3d",
  "runtime_version": "8.0.4",
  "normalized_fields": [],
  "input": { "...": "..." },
  "output": { "...": "..." }
}
```

- `captured_at` — ISO-8601 instant the fixture was actually captured.
- `anchor_date` — the calendar date every scenario's relative dates are computed
  from, so a replay on a different day reproduces the same absolute dates.
- `legacy_commit_sha` — the legacy repo's commit SHA at capture time.
- `runtime_version` — the legacy stack's own runtime/language version string
  (e.g. a .NET SDK version, a Node version, a Python version) — whatever the
  identified stack's own convention for reporting this is.
- `normalized_fields` — flat array of **canonical field paths** (section (g)),
  rooted at this fixture's own `output` object, excluded from replay comparison
  (see (b)). Every entry is resolved against this fixture's real `output` at
  record time: a path that matches **zero** fields is a hard
  `specclaw-bf-baseline record` error naming the dead path and suggesting the
  near-miss paths that do exist. A fixture with a dead normalization path is
  never silently accepted — a path that matches nothing normalizes nothing, so
  the field it was meant to exclude silently diverges on every replay.
- `input` / `output` — whatever shape the scenario's seam actually produces;
  no fixed schema beyond field-for-field mirroring in (b), plus the
  error-outcome fields in (b) whenever the seam can reject or throw.

## (b) Replay results

`actual/<GM-ID>.json` — its `output` field's names and nesting must mirror the
fixture's own `output` shape **field-for-field**. `specclaw-bf-replay compare`
diffs by field name; a renamed or restructured field reads as a spurious
divergence, not a build error.

### (b.1) Error outcomes — the business-class fields

Whenever a seam's captured behaviour is "succeeded, or was rejected," the
fixture-writer / result-writer generated for **any** stack must record these
three fields inside `output`, under these exact JSON key names:

| Field | Type | Meaning |
|---|---|---|
| `outcome` | `"OK"` \| `"REJECTED"` | Did the seam accept the input and complete, or refuse it? |
| `error_code` | string \| `null` | A stable, **project-defined** `SCREAMING_SNAKE` code naming *which* business condition rejected it. `null` when `outcome` is `"OK"`, and — only under (h)'s pending-question rule — when the condition genuinely could not be mapped yet. |
| `threw` | boolean | Did the seam signal the outcome by raising, versus returning a value? A seam that returns a rejection result object records `outcome: "REJECTED"` with `threw: false`. |

These three are **business-class**: they are what the legacy application
actually decided, expressed in language that survives a rebuild onto a
different framework. `error_code`'s vocabulary is per project and lives in the
target repo — see (h). Never invent a code here; never derive one from an
exception's type name.

### (b.2) Raw exception surfaces — the representation-class fields

The raw framework surface is still **recorded**, as evidence, under these four
exact key names — the same four for every stack, regardless of the source
language's own naming idiom (a Python writer, a Go writer, a JS writer all
still emit these literal keys):

`ExceptionType` · `InnerExceptionType` · `ExceptionMessage` · `InnerExceptionMessage`

`ExceptionType`/`InnerExceptionType` are compared by the identifier **after the
last `.`, `::`, or `/`** only — so a legacy `SomeNamespace.Foo.ValidationException`
and a rebuild `other.pkg.ValidationException` (or `pkg::ValidationException`, or
`pkg/ValidationException`) match on `ValidationException` alone.

**These four fields are representation-class: a difference in any of them, and
only in them, never by itself produces a `DIVERGES` verdict.** It is reported,
with both raw values retained (section (j)), because it is useful evidence —
but a rebuilt application legitimately raises differently-named exceptions with
differently-worded messages while making exactly the same business decision.
Comparing them as if they were behaviour is how a clean rebuild produces a
report full of divergences that mean nothing.

### (b.3) Business equality, stated once

Two outputs are **behaviourally equal** when every one of these agrees:

- `outcome`, `error_code`, and `threw`; and
- every other field that is neither representation-class (b.2) nor matched by
  the fixture's own `normalized_fields` (section (g)).

Nothing else. This set is computed by `specclaw-bf-replay compare` from the
declared data above — never enumerated per project, per stack, or by an agent.

## (c') `manifest.json` schema

`.specclaw/baseline/manifest.json` is written by `specclaw-bf-baseline record`
— bash-derived from `scenarios.md` and the fixture files, never agent-authored.

```jsonc
{
  "manifest_schema": 2,
  "plugin_version": "0.9.0",
  "generated": "2026-08-10",
  "generated_at": "2026-08-10T09:12:00Z",
  "project_root": "…",
  "total_scenarios": 31,
  "fixtures": [ /* one entry per captured scenario, fields below */ ],
  "missing_scenarios": ["GM-022"]
}
```

- `manifest_schema` — integer, currently `2`. **`specclaw-bf-replay resolve`
  hard-fails on a manifest that lacks this field or predates the current
  schema**, before it creates anything, and names
  `re-run /specclaw:bf-baseline --record` as the fix. It never assumes a
  missing field means "the old default was fine."
- `plugin_version` — the specclaw version that recorded this manifest, stamped
  at record time. `specclaw-bf-replay` stamps its own running version into
  `run-metadata.json` and the report header, so a mismatch between the two
  (a report rendered by v0.9.0 against a manifest recorded by v0.7.0) is
  visible on the report's face rather than inferred later. A mismatch is a
  WARN, not a failure — a stale *schema* is what fails.

Each `fixtures[]` entry carries:

- `status`: `VERIFIABLE | PROVISIONAL | SUPERSEDED`. `PROVISIONAL` means the
  fixture's underlying scenario traces to a business rule still blocked by an
  open pending question (see `templates/pending-questions.md`) — captured and
  replayable, but not yet a settled proof. `SUPERSEDED` means the scenario's
  own definition changed since this fixture was captured against it — it must
  be recaptured, and until it is, replaying it proves nothing about the
  scenario as currently written. `specclaw-bf-replay` propagates both into its
  verdict computation (section (j)); never a stack-specific concern.
- `seam_layer`: the fixture's capture layer, per (i) — extracted verbatim from
  the scenario's own declaration, never re-derived from prose.
- `outcome` / `error_code` / `threw`: lifted from the fixture's own `output`
  per (b.1), so a reader can see the recorded business decision without
  opening every fixture file.
- `normalized_fields_resolved`: `[{"path": "…", "matches": N}]` — proof that
  every declared normalization path actually resolved against this fixture's
  output. `record` refuses to write a manifest where any `matches` is `0`.
- plus the existing `scenario_id`, `seam`, `business_rules_pinned`,
  `verifies_backlog_item`, `fixture_path`, `content_hash`,
  `scenario_content_hash`, `provisional_ref`, `captured_at`, `anchor_date`,
  `legacy_commit_sha`, `runtime_version`, `normalized_fields`.

## (c) ID permanence

`GM-NNN` (scenarios), `DR-NNN` (business rules), `CQ-NNN`/`SQ-NNN`/`UQ-NNN`
(clarify questions), `BL-NNN` (backlog items) are permanent once assigned —
never renumbered, never reformatted, across any regeneration or archive
cycle.

## (d) `harness-manifest.json` schema

Written by `bf-baseline-designer` in harness mode, under
`.specclaw/baseline/harness/`:

```json
{
  "stack": "string — the identified legacy stack, e.g. \".NET 8\", \"Node 20 / Prisma\", \"Python 3.12 / Django\"",
  "build_command": "string or null — null if the stack has no separate build step",
  "run_command": "string — the command that runs the harness and produces fixtures",
  "fixtures_output_dir": "string — repo-relative path fixtures are written to",
  "runtime_version_source": "string — how runtime_version in each fixture is obtained, e.g. \"Environment.Version\", \"process.version\", \"platform.python_version()\""
}
```

## (e) `run-config.json` schema

Stubbed by `specclaw-bf-replay init-rundir`, completed by `bf-replay-mapper`:

```json
{
  "stack": "string or null — null until the mapper agent completes this file",
  "build_command": "string or null — null if the rebuild stack has no separate build step",
  "test_command": "string or null — null until the mapper agent completes this file",
  "results_dir": "actual",
  "evidence_exclusions": ["array of strings — glob patterns for this stack's own build/dependency output, e.g. [\"bin/\", \"obj/\"] or [\"node_modules/\", \"dist/\"]"]
}
```

`specclaw-bf-replay run-tests` fails loudly if `test_command` is still `null`
("mapper never completed run-config.json") rather than guessing a default.

## (f) `ui-manifest.json` schema

Written by `specclaw-bf-ui record` (Mode B — pure bash, no agent) at
`.specclaw/ui/ui-manifest.json`, from the human-captured PNGs under
`.specclaw/ui/screens/`:

```json
{
  "generated": "2026-08-10",
  "legacy_commit_sha": "a1b2c3d",
  "total_checklist_rows": 7,
  "screenshots": [
    {
      "scr_id": "SCR-001",
      "state": "default",
      "screen": "Main Dashboard",
      "file": ".specclaw/ui/screens/SCR-001.png",
      "sha256": "sha256:<64 hex>",
      "captured_at": "2026-08-10T09:12:00Z",
      "legacy_commit_sha": "a1b2c3d"
    }
  ],
  "missing": [
    { "scr_id": "SCR-002", "state": "validation-error",
      "expected_file": ".specclaw/ui/screens/SCR-002-validation-error.png" }
  ],
  "extra": [
    { "file": ".specclaw/ui/screens/notes.txt",
      "reason": "filename does not match the SCR-###[-state].png convention" }
  ]
}
```

- `scr_id` — the screen's permanent `SCR-NNN` id from `ui-inventory.md`.
- `state` — the state captured, matching its `screenshot-checklist.md` row
  (`default` for the plain view).
- `file` — repo-relative path of the PNG. Filenames follow
  `SCR-###.png` / `SCR-###-<state>.png`, validated mechanically; a file that
  violates it is reported under `extra`, never silently accepted.
- `sha256` — `sha256:<hex>` of the file's bytes, making the captured
  evidence tamper-evident exactly as a fixture's `content_hash` does. Empty
  only when the machine has no `sha256sum`/`shasum`, which `record` warns
  about loudly rather than passing off as sealed evidence.
- `captured_at` — ISO-8601 UTC **filesystem mtime of the PNG at record
  time**. A PNG carries no trustworthy capture timestamp and nothing in
  specclaw parses image internals, so this is a labelled proxy, not a
  claim about when the human took the shot.
- `legacy_commit_sha` — the legacy repo's HEAD **at record time**. Same
  caveat: it dates the recording, not the capture.
- `screen` — the human-readable screen name, carried through from the
  checklist for readability. Convenience plumbing, the same tier as
  `manifest.json`'s `provisional_ref` — a reader may use it, nothing
  computes from it.
- `missing` / `extra` — normal reported states, never errors. A checklist
  row with no file is `missing`; a file matching no row is `extra`.

`SCR-NNN` (screens) and `TK-NNN` (design-token groups) are permanent once
assigned — never renumbered, never reformatted, across any regeneration or
archive cycle — on exactly the same terms as the ID families in (c). A
screen that no longer exists becomes a tombstone in `ui-inventory.md`; its
id is never reused.

Nothing in this section is a golden-master seam. UI stays excluded from the
seam taxonomy (`templates/seams.md`'s "Excluded: UI Automation"), no
`specclaw-bf-replay` verdict reads any field above, and a screenshot is
never compared to anything by any specclaw command. Visual fidelity is
established by a named human signing `ui-review.md` against these recorded,
hashed captures — this manifest exists to make that evidence citable, not
to automate the judgement.

## (g) Canonical field-path language

One syntax, used everywhere a field path is written or computed: a fixture's
`normalized_fields`, `compare.json`'s `field_path`, and every path a report
prints.

```
path     := segment ( "." segment )*
segment  := key index*
index    := "[" ( digits | "*" ) "]"
```

- **Rooted at the `output` object.** `result.credit_note_id` refers to
  `output.result.credit_note_id`. A leading `output.` is *not* canonical; it is
  accepted, stripped, and reported as a canonicalization WARN naming the
  canonical spelling, because it resolves unambiguously.
- **Array indices attach to their key with no separating dot**:
  `cases[0].invoice_id`, never `cases.[0].invoice_id`.
- **`[*]` matches any index**: `cases[*].invoice_id` covers every element.

**Matching semantics, precisely.** A pattern matches a concrete path when,
segment for segment, the pattern is **equal to, or a proper prefix of**, the
concrete path — and each segment matches when its key is string-equal and each
index selector is either numerically equal or `[*]`.

- `result.credit_note_id` matches exactly that scalar.
- `cases[*].invoice_id` matches `cases[0].invoice_id`, `cases[1].invoice_id`, …
- `result.timestamps` (naming an object) matches every path beneath it — prefix
  semantics are how a whole subtree is normalized in one entry.
- A pattern that resolves to **zero** concrete paths is *dead*. Dead paths are a
  hard error at record time (a) and a reported WARN at compare time (j.4).

The resolution primitive is shared, not reimplemented: `specclaw-bf-baseline`
and `specclaw-bf-replay` both call the same jq module
(`$CLAUDE_PLUGIN_ROOT/lib/gm-paths.jq`), so capture-time validation and
compare-time exclusion can never drift into two lookalike implementations that
disagree about what a path means.

## (h) Semantic error identity and the per-project error map

`error_code` (b.1) is the field that makes error comparison survive a rebuild.
Its vocabulary is **per project**, and it lives in the target repo:

```
.specclaw/baseline/error-map.md
```

- **Nothing in this plugin ever contains a code, a framework exception name, or
  a mapping between them.** The plugin ships only the empty document skeleton
  (`templates/error-map.md`).
- `bf-baseline-designer`, in harness mode, **creates or extends** `error-map.md`
  as it encounters legacy error conditions. Each entry cites the **legacy**
  source `file:line` that raises that condition. The document is human-reviewable
  by design: a person can read it and see what each code claims to mean and
  where the claim came from.
- `bf-replay-mapper` maps the rebuild's errors into the **same** vocabulary when
  it writes actual results, citing the **rebuild** source `file:line` for each
  code it uses. It never adds a code that isn't already in `error-map.md`, and
  never renames one.
- **Ask, don't guess.** An error either agent cannot confidently map is *not*
  given a plausible-looking code. The agent raises a typed pending question
  (`templates/pending-questions.md`, triggers T2/T3/T4) and leaves
  `error_code: null` on the affected fixture or actual result. This is the same
  soft-block mechanism every other provisional artifact uses.

**Entry format** — one `###` heading per code, so `record` can verify a code
exists with a literal heading grep, exactly as `sanction-check` verifies a CQ:

```markdown
### <SEMANTIC_CODE>

- **Condition:** <the business condition, in the project's own language>
- **Legacy source:** <path/File.ext:142>
- **Rebuild source:** <path/File.ext:88, or "not yet mapped">
- **Raised as (legacy):** <the raw exception type/message shape, for reference only>
```

**Mechanical checks `specclaw-bf-baseline record` performs** (all from declared
data, none by judgement):

1. Every non-null `error_code` appearing in any fixture has a matching
   `### <CODE>` heading in `error-map.md`. An unmapped code is a hard error.
2. A fixture with `outcome: "REJECTED"` and `error_code: null` is legal **only**
   when its scenario carries the `⚠ PROVISIONAL` marker — i.e. an agent
   genuinely asked instead of guessing. Otherwise it is a hard error naming the
   fixture.

`error-map.md` must travel with the other Phase A artifacts into the rebuild
repo (see `docs/rebuild-workflow.md`'s copy set) — without it the mapper has no
vocabulary to map into.

## (i) Seam layers

Every seam is observed at exactly one layer. The enum is closed:

| `seam_layer` | Observed at |
|---|---|
| `pure-function` | A function/method with no persistence and no clock — called directly. |
| `service` | A service/application-layer entry point, called in-process, with its own arrange step. |
| `http` | The application's HTTP/API surface — request in, response out. |
| `persistence` | The data/ORM boundary — cascade, delete-rule, and constraint behaviour. |

The layer is **declared once and copied thereafter**, never re-derived:

- `seams.md` — each ranked seam declares its layer.
- `scenarios.md` — each `### GM-NNN` block carries `- **Seam layer:** <enum>`.
- `manifest.json` — `record` extracts it verbatim from the scenario block.
  A missing or non-enum value is a hard record error; there is no default.
- `mapping.json` — each entry carries **both**:
  - `legacy_seam_layer` — copied from `selection.json` (which carries the
    manifest's value unchanged). Not re-derived, not re-judged.
  - `replay_seam_layer` — the layer the generated replay test *actually*
    targets.

**The same-layer rule.** A replay test must exercise the rebuild at the layer
the fixture was captured at. A fixture captured at `service` replayed through
`http` is not a weaker proof — it is a different measurement, and its
divergences are noise about transport, serialization, and middleware rather
than about the business rule the fixture pins.

If the equivalent layer genuinely does not exist in the rebuild, that is
`NOT REPLAYABLE` with `category: "seam-mismatch"` and a remediation naming what
would have to exist. **"Test it through HTTP instead, because that's what's
reachable" is never a valid resolution.**

This is enforced mechanically, on the same trust model as `sanction-check`
re-verifying the auditor: `specclaw-bf-replay compare` re-checks every mapping
entry against `selection.json` before diffing anything, and forces the row to
`NOT REPLAYABLE / seam-mismatch` — whatever the agent claimed — when
`replay_seam_layer` is absent, or differs from the authoritative legacy layer,
or when the entry's own `legacy_seam_layer` does not match `selection.json`.

## (j) Divergence classes and the overall verdict

### (j.1) Per-diff `field_class`

Computed by `specclaw-bf-replay compare`, in this order, first match wins:

| Order | `field_class` | When |
|---|---|---|
| 1 | *(excluded)* | The path is matched by a `normalized_fields` pattern (g) — not emitted at all. |
| 2 | `representation` | The path's last segment is one of (b.2)'s four names. |
| 3 | `unmapped-error-code` | The path's last segment is `error_code`, and either side is `null` while that side's `outcome` is `"REJECTED"` — i.e. (h)'s ask-don't-guess case, not a behavioural difference. |
| 4 | `behavioural` | Everything else. |

### (j.2) Per-row `divergence_class`

The highest-precedence class present among the row's diffs:

`behavioural` > `unmapped-error-code` > `representation`

No diffs at all → `MATCH`. The per-fixture verdict enum is unchanged
(`MATCH` / `DIVERGES` / `ERROR` / `NOT REPLAYABLE`); `divergence_class` rides
alongside it. Everything downstream — whether the auditor is spawned at all,
what `sanction-check` demands a CQ for, what FAILs the run — keys off
`divergence_class == "behavioural"`, so representation noise never reaches an
agent and never demands a product decision.

### (j.3) Overall verdict

Evaluated strictly in this order, by bash, from the counts above:

| # | Condition | Verdict | Exit |
|---|---|---|---|
| 1 | selected > 0 and every selected fixture is NOT REPLAYABLE (seam-mismatch rows included) | `INCOMPLETE` | 2 |
| 2 | any `ERROR`, **or** any unsanctioned `behavioural` divergence | `FAIL` | 1 |
| 3 | any exercised `PROVISIONAL` fixture, **or** any exercised `SUPERSEDED` fixture, **or** any `unmapped-error-code` row | `PASS-PENDING-DECISIONS` | 1 |
| 4 | otherwise | `PASS` | 0 |

Rule 2 preceding rule 3 is the guarantee: **an unsanctioned behavioural
divergence is always FAIL.** No provisional, superseded, or unmapped state ever
converts it into `PASS-PENDING-DECISIONS`. A *sanctioned* behavioural divergence
and a representation-only difference both reach `PASS`.

### (j.4) `compare.json` schema

```jsonc
{
  "compare_schema": 2,
  "plugin_version": "0.9.0",
  "results": [{
    "scenario_id": "GM-019",
    "verdict": "DIVERGES",
    "fixture_status": "VERIFIABLE",
    "divergence_class": "behavioural",
    "diffs": [
      {"field_path": "threw", "expected": true, "actual": false,
       "field_class": "behavioural"}
    ],
    "normalization_warnings": [
      {"path": "cases[*].id", "matched": 0,
       "suggestions": ["cases[0].case_id"], "against": "actual"}
    ],
    "legacy_seam_layer": "service",
    "replay_seam_layer": "http"
  }],
  "summary": { "match": 12, "behavioural_sanctioned": 2,
               "behavioural_unsanctioned": 3, "representation": 18,
               "unmapped_error_code": 1, "seam_mismatch": 2,
               "error": 0, "not_replayable": 5 }
}
```

`legacy_seam_layer`/`replay_seam_layer` appear on rows forced to
`seam-mismatch`. `normalization_warnings` never changes a verdict — it reports
a normalization path that resolved against the fixture but resolves against
nothing in the actual output, which is precisely the signal that the rebuild
reshaped the field the path was meant to exclude.

## (k) Identity and idempotency capture

A generated identifier — an auto-increment key, a UUID, a sequence-derived
document number — proves nothing when compared across two independently seeded
databases. Comparing one is guaranteed noise; the *rule* it was standing in for
goes unverified.

For any scenario whose business rule is about identity or idempotency, capture
the **assertion**, not the value:

```jsonc
"output": {
  "outcome": "OK", "error_code": null, "threw": false,
  "first_call_created": true,
  "second_call_same_entity": true,
  "second_call_created_duplicate": false
}
```

These are booleans the seam itself can answer, they mean the same thing in both
applications, and they fail loudly when the rule is actually broken. Where a raw
generated ID is recorded at all — as evidence, or because it is genuinely part
of the output shape — it belongs in `normalized_fields` via a canonical path (g),
which is what makes it excluded rather than merely hoped-over.

This is guidance for scenario design and harness/test generation. The comparator
needs no special case for it: once (g) makes normalization paths actually
resolve, an ID listed there is genuinely skipped.

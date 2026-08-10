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
- `normalized_fields` — flat array of output field paths excluded from replay
  comparison (see (b)).
- `input` / `output` — whatever shape the scenario's seam actually produces;
  no fixed schema beyond field-for-field mirroring in (b).

## (b) Replay results

`actual/<GM-ID>.json` — its `output` field's names and nesting must mirror the
fixture's own `output` shape **field-for-field**. `specclaw-bf-replay compare`
diffs by field name; a renamed or restructured field reads as a spurious
divergence, not a build error.

**Canonical error/exception fields.** Whenever a seam's captured behaviour is
"threw or didn't," any fixture-writer / result-writer generated for **any**
stack must record that under these exact JSON key names — `ExceptionType` and
`InnerExceptionType` — regardless of the source language's own naming idiom
(a Python writer, a Go writer, a JS writer all still emit these two literal
keys). This is a deliberate exception to "mirror the fixture's shape
verbatim": it's the one canonical vocabulary every stack's capture code must
converge on, so `compare` can normalize them by short type name without
guessing at a stack's naming convention. `compare` treats these two fields
specially: it compares them by the identifier **after the last `.`, `::`, or
`/`** only — so a legacy `SomeNamespace.Foo.ValidationException` and a rebuild
`other.pkg.ValidationException` (or `pkg::ValidationException`, or
`pkg/ValidationException`) match on `ValidationException` alone. Every other
field is compared for exact equality, except any path listed in the fixture's
own `normalized_fields`.

## (c') Manifest entry status

Each entry in `.specclaw/baseline/manifest.json`'s `fixtures[]` array (bash-derived from
scenarios.md and the fixture files, per (a) above — never agent-authored, so
this is the one manifest-level field this contract documents) also carries
a `status` field: `VERIFIABLE | PROVISIONAL | SUPERSEDED`. `PROVISIONAL`
means the fixture's underlying scenario traces to a business rule still
blocked by an open pending question (see `templates/pending-questions.md`)
— captured and replayable, but not yet a settled proof. `SUPERSEDED` means
the scenario's own definition changed since this fixture was captured
against it. `specclaw-bf-replay` propagates both into its verdict and
overall-PASS computation; never a stack-specific concern.

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

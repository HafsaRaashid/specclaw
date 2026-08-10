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

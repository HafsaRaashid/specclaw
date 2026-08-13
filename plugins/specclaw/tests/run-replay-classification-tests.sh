#!/usr/bin/env bash
# run-replay-classification-tests.sh — regression suite for the mechanical
# parts of the golden-master pipeline that decide a verdict:
#
#   - the canonical field-path language and its matching semantics
#     (templates/CONTRACT.md (g), lib/gm-paths.jq)
#   - record-time validation: dead normalization paths, the error-outcome
#     contract, error-map cross-check, seam_layer enum
#   - the version/status compatibility guard in `resolve`
#   - seam-layer re-verification in `compare`
#   - three-way divergence classification and the verdict order (j.3)
#
# Every one of these is bash/jq computing a fact from declared data — exactly
# the code where a silent regression turns "we checked and it was fine" into
# something nobody notices. Bash + coreutils + jq (the suites themselves use
# jq here because the artifacts under test are nested JSON).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BASELINE_BIN="$PLUGIN_ROOT/bin/specclaw-bf-baseline"
REPLAY_BIN="$PLUGIN_ROOT/bin/specclaw-bf-replay"
GM_LIB="$PLUGIN_ROOT/lib/gm-paths.jq"

PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ $# -gt 1 ] && echo "         $2"; }

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then ok "$desc"
  else bad "$desc" "expected [${expected}] got [${actual}]"; fi
}

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  case "$haystack" in
    *"$needle"*) ok "$desc" ;;
    *) bad "$desc" "output did not contain [${needle}]" ;;
  esac
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed — replay classification suite requires it."
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

GM="$(cat "$GM_LIB")"

# jq's Windows build emits CRLF; every capture below goes through tr so a
# trailing \r never turns an equal string into a failing assertion.
gmjq() { jq -r "$GM$1" | tr -d '\r'; }

# ─────────────────────────────────────────────────────────────────────────────
echo "== canonical path language (CONTRACT.md (g)) =="

OUT='{"result":{"credit_note_id":"X","amount":5},"cases":[{"invoice_id":1},{"invoice_id":2}],"outcome":"OK","error_code":null,"threw":false}'

assert_eq "array indices render with no dot before the bracket" \
  "cases[0].invoice_id" \
  "$(jq -n --argjson o "$OUT" "$GM"'[gm_concrete_paths($o)[] | gm_render_path(.)] | map(select(startswith("cases")))[0]' | tr -d '\r"')"

assert_eq "a null-valued field is visible to the path walk" \
  "true" \
  "$(jq -n --argjson o "$OUT" "$GM"'[gm_concrete_paths($o)[] | gm_render_path(.)] | index("error_code") != null' | tr -d '\r')"

assert_eq "a false-valued field is visible to the path walk" \
  "true" \
  "$(jq -n --argjson o "$OUT" "$GM"'[gm_concrete_paths($o)[] | gm_render_path(.)] | index("threw") != null' | tr -d '\r')"

assert_eq "[*] matches every array index" "2" \
  "$(jq -n --argjson o "$OUT" "$GM"'gm_resolve("cases[*].invoice_id"; $o) | length' | tr -d '\r')"

assert_eq "a literal index matches only that element" "1" \
  "$(jq -n --argjson o "$OUT" "$GM"'gm_resolve("cases[1].invoice_id"; $o) | length' | tr -d '\r')"

assert_eq "a pattern naming a container normalizes its whole subtree" "2" \
  "$(jq -n --argjson o "$OUT" "$GM"'gm_resolve("result"; $o) | length' | tr -d '\r')"

assert_eq "a leading output. prefix is stripped, not rejected" "1" \
  "$(jq -n --argjson o "$OUT" "$GM"'gm_resolve("output.result.amount"; $o) | length' | tr -d '\r')"

assert_eq "an unrooted leaf name matches nothing" "0" \
  "$(jq -n --argjson o "$OUT" "$GM"'gm_resolve("credit_note_id"; $o) | length' | tr -d '\r')"

assert_eq "a dead path suggests the real path with the same leaf" \
  "result.credit_note_id" \
  "$(jq -rn --argjson o "$OUT" "$GM"'gm_near_misses("credit_note_id"; $o)[0]' | tr -d '\r')"

assert_eq "a dead path suggests a camelCase rename of the same field" \
  "result.creditNoteId" \
  "$(jq -rn --argjson o '{"result":{"creditNoteId":"X"}}' "$GM"'gm_near_misses("result.credit_note_id"; $o)[0]' | tr -d '\r')"

# ─────────────────────────────────────────────────────────────────────────────
echo "== divergence classification (CONTRACT.md (j.1), (j.2)) =="

cls() { jq -n --argjson e "$1" --argjson a "$2" --argjson n "${3:-[]}" \
        "$GM"'gm_divergence_class(gm_diffs($e; $a; $n)) // "MATCH"' | tr -d '\r"'; }

assert_eq "identical outputs are a MATCH" "MATCH" \
  "$(cls '{"outcome":"OK","error_code":null,"threw":false,"n":1}' '{"outcome":"OK","error_code":null,"threw":false,"n":1}')"

assert_eq "a namespace-only exception rename is not a diff at all" "MATCH" \
  "$(cls '{"outcome":"REJECTED","error_code":"E","threw":true,"ExceptionType":"a.b.LockedException"}' \
         '{"outcome":"REJECTED","error_code":"E","threw":true,"ExceptionType":"x::y::LockedException"}')"

assert_eq "a differing exception message alone is representation-class" "representation" \
  "$(cls '{"outcome":"REJECTED","error_code":"E","threw":true,"ExceptionMessage":"Invoice 4471 is locked"}' \
         '{"outcome":"REJECTED","error_code":"E","threw":true,"ExceptionMessage":"invoice locked"}')"

assert_eq "a differing exception type name alone is representation-class" "representation" \
  "$(cls '{"outcome":"REJECTED","error_code":"E","threw":true,"ExceptionType":"a.LockedException"}' \
         '{"outcome":"REJECTED","error_code":"E","threw":true,"ExceptionType":"b.LockedError"}')"

assert_eq "a flipped threw is behavioural" "behavioural" \
  "$(cls '{"outcome":"REJECTED","error_code":"E","threw":true}' '{"outcome":"REJECTED","error_code":"E","threw":false}')"

assert_eq "a differing error_code (both mapped) is behavioural" "behavioural" \
  "$(cls '{"outcome":"REJECTED","error_code":"A","threw":true}' '{"outcome":"REJECTED","error_code":"B","threw":true}')"

assert_eq "a null error_code against a REJECTED outcome is unmapped-error-code" "unmapped-error-code" \
  "$(cls '{"outcome":"REJECTED","error_code":null,"threw":true}' '{"outcome":"REJECTED","error_code":"B","threw":true}')"

assert_eq "behavioural outranks representation on the same row" "behavioural" \
  "$(cls '{"outcome":"OK","error_code":null,"threw":false,"ExceptionMessage":"a"}' \
         '{"outcome":"REJECTED","error_code":null,"threw":false,"ExceptionMessage":"b"}')"

assert_eq "a normalized path is excluded from the diff entirely" "MATCH" \
  "$(cls '{"outcome":"OK","error_code":null,"threw":false,"id":"CN-1"}' \
         '{"outcome":"OK","error_code":null,"threw":false,"id":"CN-2"}' '["id"]')"

# ─────────────────────────────────────────────────────────────────────────────
echo "== record-time validation (CONTRACT.md (a), (b.1), (h), (i)) =="

# A minimal, valid baseline the negative cases below each break in one way.
seed_baseline() {
  local root="$1" layer="${2:-service}" code="${3:-INVOICE_ALREADY_ISSUED}"
  local norm="${4:-[\"result.credit_note_id\"]}" out2="${5:-}"
  rm -rf "$root"; mkdir -p "$root/.specclaw/baseline/fixtures" "$root/.specclaw/analysis"
  cat > "$root/.specclaw/baseline/scenarios.md" <<EOF
### GM-001 — ok

- **Seam:** Svc.Do
- **Seam layer:** ${layer}
- **Business rules pinned:** DR-001
- **Verifies backlog item:** BL-002 — thing

### GM-002 — rejected

- **Seam:** Svc.Do
- **Seam layer:** service
- **Business rules pinned:** DR-002
- **Verifies backlog item:** BL-002 — thing
EOF
  printf '### %s\n\n- **Condition:** x\n- **Legacy source:** a.ext:1\n' "$code" \
    > "$root/.specclaw/baseline/error-map.md"
  cat > "$root/.specclaw/baseline/fixtures/GM-001.json" <<EOF
{"scenario_id":"GM-001","captured_at":"2026-08-07T10:15:00Z","anchor_date":"2026-08-07",
 "legacy_commit_sha":"abc","runtime_version":"1","normalized_fields":${norm},
 "input":{},"output":{"outcome":"OK","error_code":null,"threw":false,
 "result":{"credit_note_id":"CN-1","amount":10}}}
EOF
  if [ -n "$out2" ]; then
    printf '%s' "$out2" > "$root/.specclaw/baseline/fixtures/GM-002.json"
  else
    cat > "$root/.specclaw/baseline/fixtures/GM-002.json" <<EOF
{"scenario_id":"GM-002","captured_at":"2026-08-07T10:16:00Z","anchor_date":"2026-08-07",
 "legacy_commit_sha":"abc","runtime_version":"1","normalized_fields":[],
 "input":{},"output":{"outcome":"REJECTED","error_code":"${code}","threw":true,
 "ExceptionType":"a.b.LockedException","ExceptionMessage":"locked"}}
EOF
  fi
}

R="$WORK/rec"
seed_baseline "$R"
out="$(bash "$BASELINE_BIN" record "$R/.specclaw" 2>&1)"; rc=$?
assert_eq "a valid baseline records cleanly" "0" "$rc"
# Schema 3 is the first to carry per-fixture module_ids. Note MANIFEST_SCHEMA_MIN
# in specclaw-bf-replay deliberately stays at 2: a change-scoped or --all run
# still reads a schema-2 manifest, so adopting modules forces no re-record. Only
# a --module run, which is a join on that field, requires 3.
assert_eq "manifest stamps the schema version" "3" \
  "$(jq -r '.manifest_schema' "$R/.specclaw/baseline/manifest.json" | tr -d '\r')"
assert_eq "manifest stamps the recording plugin version" "true" \
  "$(jq -r '(.plugin_version // "") != ""' "$R/.specclaw/baseline/manifest.json" | tr -d '\r')"
assert_eq "manifest carries the declared seam layer" "service" \
  "$(jq -r '.fixtures[0].seam_layer' "$R/.specclaw/baseline/manifest.json" | tr -d '\r')"
assert_eq "manifest carries threw:false rather than null" "false" \
  "$(jq -r '.fixtures[0].threw' "$R/.specclaw/baseline/manifest.json" | tr -d '\r')"
assert_eq "manifest records the resolution proof for each normalized path" "1" \
  "$(jq -r '.fixtures[0].normalized_fields_resolved[0].matches' "$R/.specclaw/baseline/manifest.json" | tr -d '\r')"

seed_baseline "$R" service INVOICE_ALREADY_ISSUED '["credit_note_id"]'
out="$(bash "$BASELINE_BIN" record "$R/.specclaw" 2>&1)"; rc=$?
assert_eq "a dead normalization path fails the record" "1" "$rc"
assert_contains "the dead-path error names the near miss" "$out" 'did you mean "result.credit_note_id"'

seed_baseline "$R" service INVOICE_ALREADY_ISSUED '[]' \
  '{"scenario_id":"GM-002","normalized_fields":[],"input":{},"output":{"result":{"x":1}}}'
out="$(bash "$BASELINE_BIN" record "$R/.specclaw" 2>&1)"; rc=$?
assert_eq "a fixture with no error-outcome fields fails the record" "1" "$rc"
assert_contains "that error names the re-capture path" "$out" "re-run /specclaw:bf-baseline --harness"

seed_baseline "$R" service INVOICE_ALREADY_ISSUED '[]' \
  '{"scenario_id":"GM-002","normalized_fields":[],"input":{},"output":{"outcome":"REJECTED","error_code":null,"threw":true}}'
out="$(bash "$BASELINE_BIN" record "$R/.specclaw" 2>&1)"; rc=$?
assert_eq "a REJECTED fixture with no code and no PROVISIONAL marker fails" "1" "$rc"
assert_contains "that error points at the error map and the ask path" "$out" "never leave a rejection unexplained"

# Same fixture, but the scenario genuinely carries the PROVISIONAL marker:
# an agent asked instead of guessing, so this is legal.
sed -i 's/\*\*Business rules pinned:\*\* DR-002/**Business rules pinned:** DR-002 ⚠ PROVISIONAL — pending PQ-007 (proposed default: reject)/' \
  "$R/.specclaw/baseline/scenarios.md"
out="$(bash "$BASELINE_BIN" record "$R/.specclaw" 2>&1)"; rc=$?
assert_eq "the same fixture is legal once the scenario is marked PROVISIONAL" "0" "$rc"

seed_baseline "$R" service NOT_IN_THE_MAP
# The map must document a DIFFERENT code — seeded with the same one, this
# would assert nothing.
printf '### SOME_OTHER_CODE\n\n- **Condition:** x\n' > "$R/.specclaw/baseline/error-map.md"
out="$(bash "$BASELINE_BIN" record "$R/.specclaw" 2>&1)"; rc=$?
assert_eq "an error_code absent from error-map.md fails the record" "1" "$rc"
assert_contains "that error names the missing heading" "$out" "has no '### NOT_IN_THE_MAP' heading"

seed_baseline "$R" rest-api
out="$(bash "$BASELINE_BIN" record "$R/.specclaw" 2>&1)"; rc=$?
assert_eq "a seam layer outside the enum fails the record" "1" "$rc"
assert_contains "that error lists the legal layers" "$out" "pure-function service http persistence"

seed_baseline "$R"
sed -i '/- \*\*Seam layer:\*\* service/d' "$R/.specclaw/baseline/scenarios.md"
out="$(bash "$BASELINE_BIN" record "$R/.specclaw" 2>&1)"; rc=$?
assert_eq "a missing seam layer fails the record rather than defaulting" "1" "$rc"

# A failing record must leave the previously-good manifest untouched: the run
# that produced the invalid state must not also destroy the valid one.
seed_baseline "$R"
bash "$BASELINE_BIN" record "$R/.specclaw" >/dev/null 2>&1
before="$(sha256sum "$R/.specclaw/baseline/manifest.json" | awk '{print $1}')"
printf '{"scenario_id":"GM-002","output":{}}' > "$R/.specclaw/baseline/fixtures/GM-002.json"
bash "$BASELINE_BIN" record "$R/.specclaw" >/dev/null 2>&1
after="$(sha256sum "$R/.specclaw/baseline/manifest.json" | awk '{print $1}')"
assert_eq "a failing record leaves the prior manifest byte-identical" "$before" "$after"

# ─────────────────────────────────────────────────────────────────────────────
echo "== resolve: version & status guard (CONTRACT.md (c')) =="

seed_replay() {
  local root="$1"
  seed_baseline "$root"
  mkdir -p "$root/.specclaw/changes/thing"
  # The item carries a real **Acceptance basis** citing the DR-### rules its
  # scenarios pin, because that is what rebuild-backlog.md's own format
  # requires ("the ID itself must be textually present, not just implied by the
  # quoted prose") and what /specclaw:bf-replay's selection join reads. A bare
  # heading with no acceptance basis is not a thinner version of a real item —
  # it is an item rebuild-backlog.md's own Verification engine would report as
  # NO BASELINE DATA, so selecting fixtures for it was only ever an artifact of
  # the old join on verifies_backlog_item.
  cat > "$root/.specclaw/analysis/rebuild-backlog.md" <<'BLEOF'
### BL-002 — thing

- **Module:** MOD-001
- **Acceptance basis (domain-model.md):**
  - DR-001: the thing is issued.
  - DR-002: the thing is not issued twice.
- **Depends on:** None
BLEOF
  printf 'DR-001 DR-002\n' > "$root/.specclaw/analysis/domain-model.md"
  printf 'Rebuild-backlog item 2 — thing.\n' > "$root/.specclaw/changes/thing/proposal.md"
  bash "$BASELINE_BIN" record "$root/.specclaw" >/dev/null 2>&1
}

P="$WORK/rep"
seed_replay "$P"
out="$(bash "$REPLAY_BIN" resolve "$P/.specclaw" thing "$P/.specclaw/replay/run-X/selection.json" 2>&1)"; rc=$?
assert_eq "resolve accepts a current manifest" "0" "$rc"
assert_eq "selection carries the manifest schema through" "3" \
  "$(jq -r '.manifest_schema' "$P/.specclaw/replay/run-X/selection.json" | tr -d '\r')"

seed_replay "$P"
jq 'del(.manifest_schema)' "$P/.specclaw/baseline/manifest.json" > "$P/m" && mv "$P/m" "$P/.specclaw/baseline/manifest.json"
out="$(bash "$REPLAY_BIN" resolve "$P/.specclaw" thing "$P/.specclaw/replay/run-Y/selection.json" 2>&1)"; rc=$?
assert_eq "resolve refuses a manifest with no schema field" "1" "$rc"
assert_contains "the guard names the exact fix" "$out" "re-run /specclaw:bf-baseline --record"
assert_eq "no run directory is created when the guard fires" "no" \
  "$([ -d "$P/.specclaw/replay/run-Y" ] && echo yes || echo no)"

seed_replay "$P"
jq '.fixtures[0] |= del(.status)' "$P/.specclaw/baseline/manifest.json" > "$P/m" && mv "$P/m" "$P/.specclaw/baseline/manifest.json"
out="$(bash "$REPLAY_BIN" resolve "$P/.specclaw" thing "$P/.specclaw/replay/run-Z/selection.json" 2>&1)"; rc=$?
assert_eq "resolve refuses an entry with no status rather than assuming VERIFIABLE" "1" "$rc"

seed_replay "$P"
jq '.fixtures[0] |= del(.seam_layer)' "$P/.specclaw/baseline/manifest.json" > "$P/m" && mv "$P/m" "$P/.specclaw/baseline/manifest.json"
out="$(bash "$REPLAY_BIN" resolve "$P/.specclaw" thing "$P/.specclaw/replay/run-Z2/selection.json" 2>&1)"; rc=$?
assert_eq "resolve refuses an entry with no seam_layer" "1" "$rc"

# ─────────────────────────────────────────────────────────────────────────────
echo "== compare: seam re-verification and verdicts (CONTRACT.md (i), (j.3)) =="

# Builds a run directory whose mapping/actuals are dictated per test, then runs
# compare + sanction-check + render and reports the verdict and exit code.
run_replay() {
  local root="$1" mapping="$2" a1="$3" a2="$4" sanction="${5:-}"
  local rd="$root/.specclaw/replay/run-C"
  rm -rf "$rd"; mkdir -p "$rd/actual"
  cp "$root/.specclaw/replay/run-X/selection.json" "$rd/selection.json"
  printf '{"stack":"t","build_command":null,"test_command":"true","results_dir":"actual","evidence_exclusions":[]}' > "$rd/run-config.json"
  printf '%s' "$mapping" > "$rd/mapping.json"
  printf '%s' "$a1" > "$rd/actual/GM-001.json"
  printf '%s' "$a2" > "$rd/actual/GM-002.json"
  bash "$REPLAY_BIN" compare "$root/.specclaw" "$rd" >/dev/null 2>&1
  [ -n "$sanction" ] && printf '%s' "$sanction" > "$rd/sanction.json"
  bash "$REPLAY_BIN" sanction-check "$root/.specclaw" "$rd" >/dev/null 2>&1
  bash "$REPLAY_BIN" render "$root/.specclaw" thing "$rd" >/dev/null 2>&1
  RENDER_RC=$?
  VERDICT="$(grep -m1 '^\*\*Overall verdict:\*\*' "$root/.specclaw/changes/thing/replay-report.md" | sed 's/.*\*\* //')"
}

seed_replay "$P"
bash "$REPLAY_BIN" resolve "$P/.specclaw" thing "$P/.specclaw/replay/run-X/selection.json" >/dev/null 2>&1

MAP_OK='[{"scenario_id":"GM-001","verdict":"REPLAYABLE","test_file":"a","legacy_seam_layer":"service","replay_seam_layer":"service"},{"scenario_id":"GM-002","verdict":"REPLAYABLE","test_file":"b","legacy_seam_layer":"service","replay_seam_layer":"service"}]'
A1_OK='{"output":{"outcome":"OK","error_code":null,"threw":false,"result":{"credit_note_id":"CN-99","amount":10}}}'
A2_OK='{"output":{"outcome":"REJECTED","error_code":"INVOICE_ALREADY_ISSUED","threw":true,"ExceptionType":"a.b.LockedException","ExceptionMessage":"locked"}}'

run_replay "$P" "$MAP_OK" "$A1_OK" "$A2_OK"
assert_eq "a clean replay is PASS" "PASS" "$VERDICT"
assert_eq "PASS exits 0" "0" "$RENDER_RC"

# Same business decision, different framework surface: must stay PASS.
A2_REPR='{"output":{"outcome":"REJECTED","error_code":"INVOICE_ALREADY_ISSUED","threw":true,"ExceptionType":"core::LockedError","ExceptionMessage":"different words"}}'
run_replay "$P" "$MAP_OK" "$A1_OK" "$A2_REPR"
assert_eq "a representation-only difference does not fail the run" "PASS" "$VERDICT"
assert_eq "representation-only still exits 0" "0" "$RENDER_RC"
assert_eq "the representation row is counted, not hidden" "1" \
  "$(jq -r '.summary.representation' "$P/.specclaw/replay/run-C/compare.json" | tr -d '\r')"

A2_BEHAV='{"output":{"outcome":"OK","error_code":null,"threw":false}}'
run_replay "$P" "$MAP_OK" "$A1_OK" "$A2_BEHAV"
assert_eq "an unsanctioned behavioural divergence is FAIL" "FAIL" "$VERDICT"
assert_eq "FAIL exits 1" "1" "$RENDER_RC"

run_replay "$P" "$MAP_OK" "$A1_OK" "$A2_BEHAV" \
  '[{"scenario_id":"GM-002","sanctioned":true,"cq_id":"CQ-005","rationale":"decided"}]'
assert_eq "a behavioural divergence citing a non-existent CQ stays FAIL" "FAIL" "$VERDICT"

A2_UNMAPPED='{"output":{"outcome":"REJECTED","error_code":null,"threw":true,"ExceptionType":"a.b.LockedException","ExceptionMessage":"locked"}}'
run_replay "$P" "$MAP_OK" "$A1_OK" "$A2_UNMAPPED"
assert_eq "an unmapped error code holds the run at PASS-PENDING-DECISIONS" "PASS-PENDING-DECISIONS" "$VERDICT"
assert_eq "PASS-PENDING-DECISIONS exits 1" "1" "$RENDER_RC"

# The ordering guarantee: a soft-block state alongside an unsanctioned
# behavioural divergence must never downgrade FAIL.
run_replay "$P" "$MAP_OK" '{"output":{"outcome":"REJECTED","error_code":"INVOICE_ALREADY_ISSUED","threw":true}}' "$A2_UNMAPPED"
assert_eq "an unsanctioned behavioural divergence outranks a soft block" "FAIL" "$VERDICT"

MAP_MISMATCH='[{"scenario_id":"GM-001","verdict":"REPLAYABLE","test_file":"a","legacy_seam_layer":"service","replay_seam_layer":"http"},{"scenario_id":"GM-002","verdict":"REPLAYABLE","test_file":"b","legacy_seam_layer":"service","replay_seam_layer":"service"}]'
run_replay "$P" "$MAP_MISMATCH" "$A1_OK" "$A2_OK"
assert_eq "a replay at another layer is forced to NOT REPLAYABLE" "NOT REPLAYABLE" \
  "$(jq -r '.results[] | select(.scenario_id=="GM-001") | .verdict' "$P/.specclaw/replay/run-C/compare.json" | tr -d '\r')"
assert_eq "and categorised seam-mismatch, whatever the agent claimed" "seam-mismatch" \
  "$(jq -r '.results[] | select(.scenario_id=="GM-001") | .category' "$P/.specclaw/replay/run-C/compare.json" | tr -d '\r')"

MAP_NOLAYER='[{"scenario_id":"GM-001","verdict":"REPLAYABLE","test_file":"a","legacy_seam_layer":"service"},{"scenario_id":"GM-002","verdict":"REPLAYABLE","test_file":"b","legacy_seam_layer":"service","replay_seam_layer":"service"}]'
run_replay "$P" "$MAP_NOLAYER" "$A1_OK" "$A2_OK"
assert_eq "a mapping entry declaring no replay layer is a seam mismatch" "seam-mismatch" \
  "$(jq -r '.results[] | select(.scenario_id=="GM-001") | .category' "$P/.specclaw/replay/run-C/compare.json" | tr -d '\r')"

MAP_LIED='[{"scenario_id":"GM-001","verdict":"REPLAYABLE","test_file":"a","legacy_seam_layer":"http","replay_seam_layer":"http"},{"scenario_id":"GM-002","verdict":"REPLAYABLE","test_file":"b","legacy_seam_layer":"service","replay_seam_layer":"service"}]'
run_replay "$P" "$MAP_LIED" "$A1_OK" "$A2_OK"
assert_eq "a mis-copied legacy layer is caught against the manifest" "seam-mismatch" \
  "$(jq -r '.results[] | select(.scenario_id=="GM-001") | .category' "$P/.specclaw/replay/run-C/compare.json" | tr -d '\r')"

MAP_NONE='[{"scenario_id":"GM-001","verdict":"NOT REPLAYABLE","category":"clock","reason":"r","remediation":"m"},{"scenario_id":"GM-002","verdict":"NOT REPLAYABLE","category":"clock","reason":"r","remediation":"m"}]'
run_replay "$P" "$MAP_NONE" "$A1_OK" "$A2_OK"
assert_eq "a fully unreplayable selection is INCOMPLETE" "INCOMPLETE" "$VERDICT"
assert_eq "INCOMPLETE exits 2" "2" "$RENDER_RC"

# ─────────────────────────────────────────────────────────────────────────────
echo "== finalize: the evidence package retains the pipeline record =="

run_replay "$P" "$MAP_OK" "$A1_OK" "$A2_OK"
printf 'x\n' > "$P/.specclaw/replay/run-C/test.log"
bash "$REPLAY_BIN" finalize "$P/.specclaw" thing "$P/.specclaw/replay/run-C" >/dev/null 2>&1
EV="$P/.specclaw/changes/thing/replay-evidence/run-C"
for artefact in pipeline/mapping.json pipeline/compare.json pipeline/sanction-verified.json \
                pipeline/run-config.json pipeline/selection.json pipeline/test.log \
                report.md run-metadata.json expected/manifest-excerpt.json; do
  assert_eq "evidence retains ${artefact}" "yes" "$([ -f "$EV/$artefact" ] && echo yes || echo no)"
done
assert_eq "run-metadata records the manifest's own plugin version" "true" \
  "$(jq -r '(.manifest_plugin_version // "") != ""' "$EV/run-metadata.json" | tr -d '\r')"

# ─────────────────────────────────────────────────────────────────────────────
echo "== module selection (CONTRACT.md (l)) =="

# GM-001 belongs to MOD-001 only; GM-002 pins rules owned by BOTH modules, so it
# is the cross-module fixture — the case the honesty rule exists for.
seed_modules() {
  local root="$1"
  seed_replay "$root"
  cat > "$root/.specclaw/analysis/module-map.md" <<'MAPEOF'
# Module Map: t

**Status:** CONFIRMED by tester, 2026-08-11

## Modules

### MOD-001 — alpha

- **Owns (entities):** A
- **Business rules:** DR-001
- **Depends on:** None

### MOD-002 — beta

- **Owns (entities):** B
- **Business rules:** DR-002
- **Depends on:** MOD-001
MAPEOF
  # Written wholesale rather than sed-patched onto seed_baseline's copy: a
  # multi-line sed replacement is exactly the kind of quoting that breaks
  # silently and leaves the field absent, which is what this suite is for.
  cat > "$root/.specclaw/baseline/scenarios.md" <<'SCENEOF'
### GM-001 — ok

- **Seam:** Svc.Do
- **Seam layer:** service
- **Modules:** MOD-001
- **Business rules pinned:** DR-001
- **Verifies backlog item:** BL-002 — thing

### GM-002 — rejected

- **Seam:** Svc.Do
- **Seam layer:** service
- **Modules:** MOD-001, MOD-002
- **Business rules pinned:** DR-002
- **Verifies backlog item:** BL-002 — thing
SCENEOF
  bash "$BASELINE_BIN" record "$root/.specclaw" >/dev/null 2>&1
}

M="$WORK/mod"
seed_modules "$M"
MF="$M/.specclaw/baseline/manifest.json"
assert_eq "record carries a single module into the manifest" "MOD-001"   "$(jq -r '.fixtures[] | select(.scenario_id=="GM-001") | .module_ids | join(",")' "$MF" | tr -d '')"
assert_eq "record carries BOTH modules of a cross-module scenario" "MOD-001,MOD-002"   "$(jq -r '.fixtures[] | select(.scenario_id=="GM-002") | .module_ids | join(",")' "$MF" | tr -d '')"

# A module tag naming nothing in the map selects nothing, silently — so it is a
# hard record error, on the same grounds as an unmapped error code.
seed_modules "$M"
sed -i 's/^- \*\*Modules:\*\* MOD-001$/- **Modules:** MOD-404/' "$M/.specclaw/baseline/scenarios.md"
out="$(bash "$BASELINE_BIN" record "$M/.specclaw" 2>&1)"; rc=$?
assert_eq "a module tag absent from module-map.md fails the record" "1" "$rc"
assert_contains "that error names the missing module heading" "$out" "has no '### MOD-404' heading"

# A WITHDRAWN tombstone is an id kept claimed, not a scenario: it declares no
# seam layer and must not fail the record on that account.
seed_modules "$M"
printf '
### GM-009 — WITHDRAWN 2026-08-11, dropped

- **Modules:** MOD-002
'   >> "$M/.specclaw/baseline/scenarios.md"
out="$(bash "$BASELINE_BIN" record "$M/.specclaw" 2>&1)"; rc=$?
assert_eq "a WITHDRAWN tombstone does not fail the record" "0" "$rc"
assert_eq "a tombstone is not counted as a scenario" "2"   "$(jq -r '.total_scenarios' "$MF" | tr -d '')"

# ANY-of selection: the cross-module fixture is selected by BOTH modules.
seed_modules "$M"
out="$(bash "$REPLAY_BIN" resolve "$M/.specclaw" MOD-002 "$M/.specclaw/replay/run-M/selection.json" 2>&1)"; rc=$?
assert_eq "resolve accepts a MOD-### target" "0" "$rc"
assert_eq "MOD-002 selects only its own fixtures" "GM-002"   "$(jq -r '[.fixtures[].scenario_id] | join(",")' "$M/.specclaw/replay/run-M/selection.json" | tr -d '')"
assert_eq "selection records the module and its scope" "module MOD-002"   "$(jq -r '.target_kind + " " + .module' "$M/.specclaw/replay/run-M/selection.json" | tr -d '')"
assert_contains "the summary reports shared cross-module fixtures" "$out" "also belong to another module"

out="$(bash "$REPLAY_BIN" resolve "$M/.specclaw" MOD-001 "$M/.specclaw/replay/run-M/selection.json" 2>&1)"
assert_eq "MOD-001 selects its own fixture AND the shared one" "GM-001,GM-002"   "$(jq -r '[.fixtures[].scenario_id] | join(",")' "$M/.specclaw/replay/run-M/selection.json" | tr -d '')"
assert_eq "selection carries per-module manifest totals for partial-view marking" "2"   "$(jq -r '.module_totals["MOD-001"]' "$M/.specclaw/replay/run-M/selection.json" | tr -d '')"

out="$(bash "$REPLAY_BIN" resolve "$M/.specclaw" MOD-404 "$M/.specclaw/replay/run-M/selection.json" 2>&1)"; rc=$?
assert_eq "an unknown module fails rather than selecting nothing" "1" "$rc"
assert_contains "that error lists the modules that do exist" "$out" "MOD-001, MOD-002"

# The module field must never force a re-record on a project that ignores it:
# a schema-2 manifest still serves change-scoped and --all runs unchanged.
seed_modules "$M"
jq 'del(.fixtures[].module_ids) | .manifest_schema = 2' "$MF" > "$M/m" && mv "$M/m" "$MF"
out="$(bash "$REPLAY_BIN" resolve "$M/.specclaw" --all "$M/.specclaw/replay/run-M/selection.json" 2>&1)"; rc=$?
assert_eq "--all still resolves against a pre-module manifest" "0" "$rc"
out="$(bash "$REPLAY_BIN" resolve "$M/.specclaw" thing "$M/.specclaw/replay/run-M/selection.json" 2>&1)"; rc=$?
assert_eq "a change-scoped run still resolves against a pre-module manifest" "0" "$rc"
out="$(bash "$REPLAY_BIN" resolve "$M/.specclaw" MOD-001 "$M/.specclaw/replay/run-M/selection.json" 2>&1)"; rc=$?
assert_eq "but --module refuses a pre-module manifest" "1" "$rc"
assert_contains "that refusal names the re-record fix" "$out" "re-run /specclaw:bf-baseline --record"

# Schema is current but nothing is tagged: a DIFFERENT fix (design, then record).
seed_modules "$M"
jq '.fixtures = [.fixtures[] | .module_ids = []]' "$MF" > "$M/m" && mv "$M/m" "$MF"
out="$(bash "$REPLAY_BIN" resolve "$M/.specclaw" MOD-001 "$M/.specclaw/replay/run-M/selection.json" 2>&1)"; rc=$?
assert_eq "an untagged current manifest also refuses a --module run" "1" "$rc"
assert_contains "that refusal points at design mode, not just record" "$out" "design mode"

# ─────────────────────────────────────────────────────────────────────────────
echo "== item scope and the acceptance-basis join (CONTRACT.md (b)) =="

# A fixture repo built in the PIPELINE'S OWN ORDER: /specclaw:bf-baseline (A4)
# designs and records BEFORE /specclaw:bf-rebuild-plan (A5) exists, so every
# scenario carries the placeholder agents/bf-baseline-designer.md instructs the
# designer to write when rebuild-backlog.md is absent. That is the state of
# every correctly-run project's first manifest, and it is the state in which a
# join on `verifies_backlog_item` selected nothing at all.
#
# rebuild-backlog.md is then produced by a REAL specclaw-bf-rebuild-collect
# render run, never hand-written. Its "**Verification:** VERIFIABLE — fixtures:"
# lines are the independent oracle these tests compare selection against; a
# hand-written backlog would only assert this suite's own assumption about the
# format, which is exactly what the oracle exists to avoid.
COLLECT_BIN="$PLUGIN_ROOT/bin/specclaw-bf-rebuild-collect"

seed_item() {
  local root="$1"
  rm -rf "$root"
  mkdir -p "$root/.specclaw/baseline/fixtures" "$root/.specclaw/analysis" \
           "$root/.specclaw/changes/credit-notes"
  cat > "$root/.specclaw/baseline/scenarios.md" <<'SCEOF'
### GM-001 — issue a credit note

- **Seam:** Svc.Issue
- **Seam layer:** service
- **Business rules pinned:** DR-001
- **Modules:** MOD-001
- **Verifies backlog item:** not yet backlog-linked — rebuild-backlog.md does not exist yet

### GM-002 — reject a re-issue

- **Seam:** Svc.Issue
- **Seam layer:** service
- **Business rules pinned:** DR-001, DR-002
- **Modules:** MOD-001, MOD-002
- **Verifies backlog item:** not yet backlog-linked — rebuild-backlog.md does not exist yet

### GM-003 — post to the ledger

- **Seam:** Svc.Post
- **Seam layer:** service
- **Business rules pinned:** DR-003
- **Modules:** MOD-002
- **Verifies backlog item:** not yet backlog-linked — rebuild-backlog.md does not exist yet
SCEOF
  printf '### INVOICE_ALREADY_ISSUED\n\n- **Condition:** x\n- **Legacy source:** a.ext:1\n' \
    > "$root/.specclaw/baseline/error-map.md"
  local i
  for i in 1 2 3; do
    cat > "$root/.specclaw/baseline/fixtures/GM-00$i.json" <<FXEOF
{"scenario_id":"GM-00$i","captured_at":"2026-08-07T10:1${i}:00Z","anchor_date":"2026-08-07",
 "legacy_commit_sha":"abc","runtime_version":"1","normalized_fields":[],
 "input":{},"output":{"outcome":"OK","error_code":null,"threw":false,"n":$i}}
FXEOF
  done
  cat > "$root/.specclaw/analysis/module-map.md" <<'MAPEOF'
# Module Map: t

**Status:** CONFIRMED by tester, 2026-08-11

## Modules

### MOD-001 — Billing

- **Business rules:** DR-001, DR-002
- **Depends on:** None

### MOD-002 — Ledger

- **Business rules:** DR-003
- **Depends on:** MOD-001
MAPEOF
  printf '### DR-001 — a\n### DR-002 — b\n### DR-003 — c\n' \
    > "$root/.specclaw/analysis/domain-model.md"
  printf 'Rebuild-backlog item 20 — credit notes.\n' \
    > "$root/.specclaw/changes/credit-notes/proposal.md"
  bash "$BASELINE_BIN" record "$root/.specclaw" >/dev/null 2>&1

  # A5 runs AFTER: the backlog is rendered by its own tool, from a draft.
  cat > "$root/draft.md" <<'DREOF'
STRIKE: BL-023 | superseded by BL-020, 2026-08-12

### BL-020 — Credit note issuance

**Module:** MOD-001
**Maps to capability:** Issue credit notes
**Depends on:** None
**Acceptance basis (domain-model.md):**
- DR-001: a credit note is issued for a settled invoice.
- DR-002: a credit note is never issued twice.

**Verification inputs needed:**
- golden-master capture of the issuance seam

### BL-021 — Ledger posting

**Module:** MOD-002
**Maps to capability:** Post to ledger
**Depends on:** BL-020
**Acceptance basis (domain-model.md):**
- DR-003: every issued note posts to the ledger.

**Verification inputs needed:**
- golden-master capture of the posting seam

### BL-022 — Ledger export

**Module:** MOD-002
**Maps to capability:** Export
**Depends on:** None
**Acceptance basis (domain-model.md):**
- DR-777: export totals must reconcile.

**Verification inputs needed:**
- none beyond the acceptance criteria above
DREOF
  bash "$COLLECT_BIN" render "$root/.specclaw" "$root/draft.md" >/dev/null 2>&1
}

# The backlog's OWN claim about which fixtures verify an item, read back off the
# rendered "**Verification:**" line. GM ids only, sorted — the line also carries
# each fixture's legacy commit in parentheses, and ordering is not the claim.
oracle_fixtures() {
  local backlog="$1" bl="$2"
  awk -v id="$bl" '$0 ~ "^### " id " " {f=1} f && /^\*\*Verification:/ {print; exit}' "$backlog" \
    | grep -oE 'GM-[0-9]{3}' | sort -u | paste -sd, - | tr -d '\r'
}
selected_ids() {
  jq -r '[.fixtures[].scenario_id] | sort | join(",")' "$1" | tr -d '\r'
}

I="$WORK/item"
seed_item "$I"
IBL="$I/.specclaw/analysis/rebuild-backlog.md"

# ── A. The tool-internal consistency oracle ─────────────────────────────────
# --item's selection must equal the backlog's own Verification fixture list,
# because both are the same BL → DR → GM chain. If these two ever disagree,
# one of them is lying to a human reading a report.
bash "$REPLAY_BIN" resolve "$I/.specclaw" BL-020 "$I/.specclaw/replay/run-a1/selection.json" >/dev/null 2>&1
assert_eq "--item BL-020 selects exactly the backlog's own Verification list" \
  "$(oracle_fixtures "$IBL" BL-020)" "$(selected_ids "$I/.specclaw/replay/run-a1/selection.json")"
bash "$REPLAY_BIN" resolve "$I/.specclaw" BL-021 "$I/.specclaw/replay/run-a2/selection.json" >/dev/null 2>&1
assert_eq "--item BL-021 selects exactly the backlog's own Verification list" \
  "$(oracle_fixtures "$IBL" BL-021)" "$(selected_ids "$I/.specclaw/replay/run-a2/selection.json")"
assert_eq "the oracle is a real claim, not an empty string" "GM-001,GM-002" \
  "$(oracle_fixtures "$IBL" BL-020)"
assert_eq "an item run records its own scope and item" "item BL-020" \
  "$(jq -r '.target_kind + " " + .bl_item' "$I/.specclaw/replay/run-a1/selection.json" | tr -d '\r')"
assert_eq "--item needs no change directory" "no" \
  "$([ -d "$I/.specclaw/changes/BL-020" ] && echo yes || echo no)"

# ── B. The placeholder manifest is the normal case, and is silent ────────────
assert_eq "the manifest under test really does carry the placeholder" "3" \
  "$(jq '[.fixtures[] | select(.verifies_backlog_item | test("not yet backlog-linked"))] | length' \
     "$I/.specclaw/baseline/manifest.json" | tr -d '\r')"
out="$(bash "$REPLAY_BIN" resolve "$I/.specclaw" BL-020 "$I/.specclaw/replay/run-b/selection.json" 2>&1 >/dev/null)"
assert_eq "a placeholder manifest still selects correctly" "GM-001,GM-002" \
  "$(selected_ids "$I/.specclaw/replay/run-b/selection.json")"
assert_eq "and says nothing about verifies_backlog_item — there is no disagreement" "0" \
  "$(printf '%s' "$out" | grep -c 'verifies_backlog_item' || true)"
# The same join drives a change-scoped run, via the item the change cites.
bash "$REPLAY_BIN" resolve "$I/.specclaw" credit-notes "$I/.specclaw/replay/run-b2/selection.json" >/dev/null 2>&1
assert_eq "a change-scoped run resolves through the same join" "GM-001,GM-002" \
  "$(selected_ids "$I/.specclaw/replay/run-b2/selection.json")"
assert_eq "per-fixture BL attribution is derived, not read from the placeholder" "BL-020" \
  "$(jq -r '[.fixtures[] | (.bl_items_resolved // [])[]] | unique | join(",")' \
     "$I/.specclaw/replay/run-b/selection.json" | tr -d '\r')"

# ── C. A populated field that disagrees is a WARN naming both sets ───────────
seed_item "$I"
jq '.fixtures[0].verifies_backlog_item = "BL-099 — something else"' "$I/.specclaw/baseline/manifest.json" \
  > "$I/m" && mv "$I/m" "$I/.specclaw/baseline/manifest.json"
# Re-hash is unnecessary: content_hash covers the FIXTURE file, not the manifest.
out="$(bash "$REPLAY_BIN" resolve "$I/.specclaw" BL-020 "$I/.specclaw/replay/run-c/selection.json" 2>&1 >/dev/null)"
assert_contains "a disagreeing verifies_backlog_item warns" "$out" "WARN"
assert_contains "the warning names what the DR join selected" "$out" "selects: GM-001, GM-002"
assert_contains "the warning names what the field claims instead" "$out" "field names: none"
assert_contains "the warning names the stale-document fix" "$out" "re-run /specclaw:bf-baseline --record"
assert_eq "but selection is unchanged — the field is never load-bearing" "GM-001,GM-002" \
  "$(selected_ids "$I/.specclaw/replay/run-c/selection.json")"

# ── D. A valid item with genuinely zero fixtures ────────────────────────────
# The empty-selection contract: a clean INCOMPLETE, never a precondition crash
# and never an invented fixture. The backlog's own Verification line agrees.
seed_item "$I"
assert_contains "the backlog itself reports BL-022 as NO BASELINE DATA" \
  "$(awk '$0 ~ "^### BL-022 " {f=1} f && /^\*\*Verification:/ {print; exit}' "$IBL")" \
  "NO BASELINE DATA"
out="$(bash "$REPLAY_BIN" resolve "$I/.specclaw" BL-022 "$I/.specclaw/replay/run-d/selection.json" 2>&1)"; rc=$?
assert_eq "a zero-fixture item resolves cleanly, not as a precondition failure" "0" "$rc"
assert_contains "resolve states the contract's message verbatim" "$out" \
  "NO BASELINE DATA — 0 fixtures mapped to BL-022"
assert_eq "selection.json is still written, with nothing invented in it" "0" \
  "$(jq -r '.selected_count' "$I/.specclaw/replay/run-d/selection.json" | tr -d '\r')"
assert_eq "and no fixtures at all" "0" \
  "$(jq -r '.fixtures | length' "$I/.specclaw/replay/run-d/selection.json" | tr -d '\r')"
bash "$REPLAY_BIN" init-rundir "$I/.specclaw" "$I/.specclaw/replay/run-d" >/dev/null 2>&1
out="$(bash "$REPLAY_BIN" render "$I/.specclaw" BL-022 "$I/.specclaw/replay/run-d" 2>&1)"; rc=$?
assert_eq "an empty selection renders INCOMPLETE" "2" "$rc"
# Deterministic by construction: run_id is the run directory's name minus its
# "run-" prefix, so a run dir of run-d reports to report-d-BL-022.md.
DREPORT="$I/.specclaw/replay/report-d-BL-022.md"
assert_eq "an item run writes its report to the run-id + BL-### suffixed path" "yes" \
  "$([ -f "$DREPORT" ] && echo yes || echo no)"
assert_contains "the verdict is INCOMPLETE, never PASS" "$(cat "$DREPORT")" '**INCOMPLETE**'
assert_contains "and the report carries the contract's message on its face" "$(cat "$DREPORT")" \
  "NO BASELINE DATA — 0 fixtures mapped to BL-022"
# A malformed manifest keeps its LOUD failure — the placeholder and an empty
# selection are neither of these, and must not be confused with them.
seed_item "$I"
printf 'not json at all' > "$I/.specclaw/baseline/manifest.json"
out="$(bash "$REPLAY_BIN" resolve "$I/.specclaw" BL-020 "$I/.specclaw/replay/run-d2/selection.json" 2>&1)"; rc=$?
assert_eq "a malformed manifest still fails loudly" "1" "$rc"
assert_contains "and says so" "$out" "not valid JSON"

# ── E. Item validation ──────────────────────────────────────────────────────
seed_item "$I"
out="$(bash "$REPLAY_BIN" resolve "$I/.specclaw" BL-404 "$I/.specclaw/replay/run-e1/selection.json" 2>&1)"; rc=$?
assert_eq "--item on an unknown BL fails" "1" "$rc"
assert_contains "and names the items that do exist" "$out" "Items that do exist:"
assert_eq "nothing is created on disk when it fails" "no" \
  "$([ -d "$I/.specclaw/replay/run-e1" ] && echo yes || echo no)"
out="$(bash "$REPLAY_BIN" resolve "$I/.specclaw" BL-023 "$I/.specclaw/replay/run-e2/selection.json" 2>&1)"; rc=$?
assert_eq "--item on a STRUCK tombstone fails" "1" "$rc"
assert_contains "and says it is a tombstone, not an item" "$out" "STRUCK tombstone"
assert_eq "nothing is created for a tombstone either" "no" \
  "$([ -d "$I/.specclaw/replay/run-e2" ] && echo yes || echo no)"
# A struck id is also never attributed to a fixture by the reverse join.
bash "$REPLAY_BIN" resolve "$I/.specclaw" --all "$I/.specclaw/replay/run-e3/selection.json" >/dev/null 2>&1
assert_eq "a STRUCK item never appears in any fixture's attribution" "0" \
  "$(jq -r '[.fixtures[] | (.bl_items_resolved // [])[] | select(. == "BL-023")] | length' \
     "$I/.specclaw/replay/run-e3/selection.json" | tr -d '\r')"

# ── F. Module scope against the new join, and the cross-module fixture ──────
seed_item "$I"
bash "$REPLAY_BIN" resolve "$I/.specclaw" MOD-001 "$I/.specclaw/replay/run-f1/selection.json" >/dev/null 2>&1
assert_eq "MOD-001 selects every fixture tagged with it" "GM-001,GM-002" \
  "$(selected_ids "$I/.specclaw/replay/run-f1/selection.json")"
bash "$REPLAY_BIN" resolve "$I/.specclaw" MOD-002 "$I/.specclaw/replay/run-f2/selection.json" >/dev/null 2>&1
assert_eq "MOD-002 selects every fixture tagged with it" "GM-002,GM-003" \
  "$(selected_ids "$I/.specclaw/replay/run-f2/selection.json")"
# THE CROSS-MODULE RULE: GM-002 carries ["MOD-001","MOD-002"] and is selected by
# BOTH, because a shared fixture is the flow that breaks when one module is
# rebuilt alone. A module run that hid it would be a false verdict.
assert_eq "the cross-module fixture is selected by MOD-001" "1" \
  "$(jq -r '[.fixtures[] | select(.scenario_id == "GM-002")] | length' \
     "$I/.specclaw/replay/run-f1/selection.json" | tr -d '\r')"
assert_eq "the cross-module fixture is selected by MOD-002 as well" "1" \
  "$(jq -r '[.fixtures[] | select(.scenario_id == "GM-002")] | length' \
     "$I/.specclaw/replay/run-f2/selection.json" | tr -d '\r')"

# ── G. --all is the full corpus; a change-scoped run is unchanged ───────────
bash "$REPLAY_BIN" resolve "$I/.specclaw" --all "$I/.specclaw/replay/run-g1/selection.json" >/dev/null 2>&1
assert_eq "--all selects the whole manifest" "GM-001,GM-002,GM-003" \
  "$(selected_ids "$I/.specclaw/replay/run-g1/selection.json")"
assert_eq "--all matches the manifest's own fixture count" \
  "$(jq -r '.fixtures | length' "$I/.specclaw/baseline/manifest.json" | tr -d '\r')" \
  "$(jq -r '.selected_count' "$I/.specclaw/replay/run-g1/selection.json" | tr -d '\r')"
# Byte-identity for the pre-existing change scope, on the populated-manifest
# fixture the rest of this suite uses (where the field and the join agree):
# resolving twice must produce the same selection.json byte for byte, and the
# per-fixture payload must still carry every field a downstream step reads.
seed_replay "$WORK/g"
bash "$REPLAY_BIN" resolve "$WORK/g/.specclaw" thing "$WORK/g/.specclaw/replay/run-g2/selection.json" >/dev/null 2>&1
bash "$REPLAY_BIN" resolve "$WORK/g/.specclaw" thing "$WORK/g/.specclaw/replay/run-g3/selection.json" >/dev/null 2>&1
assert_eq "a change-scoped selection is byte-identical across runs" \
  "$(sha256sum < "$WORK/g/.specclaw/replay/run-g2/selection.json" | awk '{print $1}')" \
  "$(sha256sum < "$WORK/g/.specclaw/replay/run-g3/selection.json" | awk '{print $1}')"
assert_eq "and still carries every field the pipeline reads off a fixture" "true" \
  "$(jq -r '[.fixtures[0] | has("scenario_id"), has("seam_layer"), has("status"),
              has("content_hash"), has("normalized_fields"), has("business_rules_pinned"),
              has("stub_refs"), has("bl_items_resolved")] | all' \
     "$WORK/g/.specclaw/replay/run-g2/selection.json" | tr -d '\r')"

# ── H. Illegal scope combinations, mechanically refused ─────────────────────
# parse-target is where this is enforced: deciding whether an invocation is
# legal is a mechanical job, so it is not left to the skill's prose.
assert_eq "a bare change name is legal" "my-change" \
  "$(bash "$REPLAY_BIN" parse-target my-change 2>&1)"
assert_eq "--item BL-### is legal" "BL-020" \
  "$(bash "$REPLAY_BIN" parse-target --item BL-020 2>&1)"
assert_eq "--module MOD-### is legal" "MOD-001" \
  "$(bash "$REPLAY_BIN" parse-target --module MOD-001 2>&1)"
assert_eq "--all is legal" "--all" "$(bash "$REPLAY_BIN" parse-target --all 2>&1)"
assert_eq "a retention flag qualifies a run rather than selecting one" "my-change" \
  "$(bash "$REPLAY_BIN" parse-target my-change --discard 2>&1)"
assert_eq "--prune-evidence's count is never mistaken for a change name" "MOD-001" \
  "$(bash "$REPLAY_BIN" parse-target --module MOD-001 --prune-evidence 3 2>&1)"
illegal() {
  local desc="$1"; shift
  local out; out="$(bash "$REPLAY_BIN" parse-target "$@" 2>&1)"; local rc=$?
  if [ "$rc" -eq 0 ]; then bad "$desc" "expected a refusal, got [${out}]"; return; fi
  case "$out" in ERROR:*) ok "$desc" ;; *) bad "$desc" "refused but not loudly: [${out}]" ;; esac
}
illegal "--item with --module is refused"        --item BL-020 --module MOD-001
illegal "--item with --all is refused"           --item BL-020 --all
illegal "--module with --all is refused"         --module MOD-001 --all
illegal "two --item flags are refused"           --item BL-020 --item BL-021
illegal "a change name with --item is refused"   my-change --item BL-020
illegal "a change name with --module is refused" my-change --module MOD-001
illegal "a change name with --all is refused"    my-change --all
illegal "two positional targets are refused"     my-change other-change
illegal "--item with no id is refused"           --item
illegal "--item with a non-BL id is refused"     --item 20
illegal "--module with a malformed id is refused" --module MOD-1
illegal "an unknown option is refused"           --bogus
illegal "no scope at all is refused"

# ── I is in run-stub-registry-tests.sh (taint is that suite's subject) ──────

# ── J. Selection is the ONLY thing a scope changes ─────────────────────────
# The same fixture set, the same mapping, the same actual outputs, run once
# item-scoped and once change-scoped, must produce the same verdict and the
# same exit code. Anything else would mean a scope had leaked into the verdict.
seed_item "$I"
run_scope() {
  local root="$1" target="$2" tag="$3" a1="$4"
  local rd="$root/.specclaw/replay/run-$tag"
  rm -rf "$rd"; mkdir -p "$rd/actual"
  bash "$REPLAY_BIN" resolve "$root/.specclaw" "$target" "$rd/selection.json" >/dev/null 2>&1
  printf '{"stack":"t","build_command":null,"test_command":"true","results_dir":"actual","evidence_exclusions":[]}' > "$rd/run-config.json"
  cat > "$rd/mapping.json" <<'MPEOF'
[{"scenario_id":"GM-001","verdict":"REPLAYABLE","test_file":"a","legacy_seam_layer":"service","replay_seam_layer":"service"},
 {"scenario_id":"GM-002","verdict":"REPLAYABLE","test_file":"b","legacy_seam_layer":"service","replay_seam_layer":"service"}]
MPEOF
  printf '%s' "$a1" > "$rd/actual/GM-001.json"
  printf '{"output":{"outcome":"OK","error_code":null,"threw":false,"n":2}}' > "$rd/actual/GM-002.json"
  bash "$REPLAY_BIN" compare "$root/.specclaw" "$rd" >/dev/null 2>&1
  bash "$REPLAY_BIN" render "$root/.specclaw" "$target" "$rd" >/dev/null 2>&1
  local rc=$?
  local rp; rp="$(report_path_for "$root" "$target" "$tag")"
  printf '%s|%s' "$rc" "$(grep -m1 '^\*\*Overall verdict:\*\*' "$rp" | sed 's/.*\*\* //' | tr -d '\r')"
}
report_path_for() {
  local root="$1" target="$2" tag="$3"
  case "$target" in
    BL-*) printf '%s/.specclaw/replay/report-%s-%s.md' "$root" "$tag" "$target" ;;
    *)    printf '%s/.specclaw/changes/%s/replay-report.md' "$root" "$target" ;;
  esac
}
A_MATCH='{"output":{"outcome":"OK","error_code":null,"threw":false,"n":1}}'
A_DIVERGE='{"output":{"outcome":"REJECTED","error_code":null,"threw":false,"n":1}}'
for pair in "clean:$A_MATCH" "diverged:$A_DIVERGE"; do
  case_name="${pair%%:*}"; actual="${pair#*:}"
  item_r="$(run_scope "$I" BL-020 "j-$case_name-i" "$actual")"
  chg_r="$(run_scope "$I" credit-notes "j-$case_name-c" "$actual")"
  assert_eq "an item-scoped ${case_name} run reaches the same verdict as change-scoped" \
    "${chg_r#*|}" "${item_r#*|}"
  assert_eq "an item-scoped ${case_name} run exits the same as change-scoped" \
    "${chg_r%%|*}" "${item_r%%|*}"
done
# And the verdicts under test are genuinely different from each other —
# otherwise the two assertions above would pass on any constant.
assert_eq "the two J cases really do produce different verdicts" "PASS FAIL" \
  "$(run_scope "$I" BL-020 j-x1 "$A_MATCH" | sed 's/.*|//') $(run_scope "$I" BL-020 j-x2 "$A_DIVERGE" | sed 's/.*|//')"

# ─────────────────────────────────────────────────────────────────────────────
echo
echo "Passed: ${PASS}   Failed: ${FAIL}"
[ "$FAIL" -eq 0 ] || exit 1

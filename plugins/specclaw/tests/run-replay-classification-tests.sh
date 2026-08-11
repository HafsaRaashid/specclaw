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
assert_eq "manifest stamps the schema version" "2" \
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
  printf '### BL-002 — thing\n' > "$root/.specclaw/analysis/rebuild-backlog.md"
  printf 'DR-001 DR-002\n' > "$root/.specclaw/analysis/domain-model.md"
  printf 'Rebuild-backlog item 2 — thing.\n' > "$root/.specclaw/changes/thing/proposal.md"
  bash "$BASELINE_BIN" record "$root/.specclaw" >/dev/null 2>&1
}

P="$WORK/rep"
seed_replay "$P"
out="$(bash "$REPLAY_BIN" resolve "$P/.specclaw" thing "$P/.specclaw/replay/run-X/selection.json" 2>&1)"; rc=$?
assert_eq "resolve accepts a current manifest" "0" "$rc"
assert_eq "selection carries the manifest schema through" "2" \
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
echo
echo "Passed: ${PASS}   Failed: ${FAIL}"
[ "$FAIL" -eq 0 ] || exit 1

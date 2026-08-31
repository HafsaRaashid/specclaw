#!/usr/bin/env bash
# run-quality-tests.sh — regression suite for specclaw-bf-quality-collect and
# the optional quality annotation in specclaw-bf-rebuild-collect.
#
# WHY THE METRIC TOOLS ARE STUBBED. scc, lizard and jscpd are not installed in
# CI and are not installed on most contributors' machines, and the point of this
# suite is the collector's parsing, classification, registry and gate logic —
# not whether a third-party binary counts branches correctly. So every case puts
# a tiny stub on PATH that emits the documented machine-readable shape. That
# also makes the assertions exact: a fixture function's complexity is whatever
# the stub says it is, so a threshold-boundary case can be pinned to the value
# either side of the boundary rather than hoping real source lands there.
#
# The corollary is that this suite does NOT prove the collector works against
# the real tools' output. What guards that is the parsers only ever reading
# documented machine-readable formats (scc --format json, lizard --csv, jscpd
# --reporters json) and never scraping human output.
#
# Cases:
#   1  polyglot tree              → per-language coverage; complexity
#                                   NOT-MEASURED / language_unsupported for the
#                                   language lizard does not parse
#   2  jscpd absent from PATH     → duplication NOT-MEASURED / tool_missing,
#                                   exit 0; and all three absent still exits 0
#   3  threshold classification   → 11 is WARN, 21 is HIGH, rollup takes the
#                                   worst status across dimensions
#   4  QI permanence              → identical ids on an unchanged re-run; a
#                                   cleared hotspot becomes resolved, never
#                                   removed; a file-level hotspot (empty
#                                   function field in its key) survives too
#   5  compare                    → improved / regressed classification, and a
#                                   one-side-only dimension is NOT-COMPARABLE
#   6  gate                       → regressed target FAILs with exit 1,
#                                   improved target PASSes with exit 0
#   7  rebuild-plan neutrality    → with no quality.json the rendered backlog is
#                                   byte-identical; with one, the ONLY lines that
#                                   differ are the annotation and its note
#   8  advisory neutrality        → HIGH findings still exit 0
#   9  module join                → an uncited file rolls up under
#                                   MOD-UNASSIGNED; a file cited by two modules
#                                   is left unassigned, never guessed
#  10  client-safe template       → the report template body carries no internal
#                                   command name outside the provenance section
#  11  ARG_MAX regression          → a >2 MB joined file list does not overflow
#                                   argv; collector exits 0 (the fixed --slurpfile
#                                   path); pre-fix binary shown to fail (informational)
#  12  spaces / unicode paths      → filenames with spaces and non-ASCII survive
#                                   enumeration, classification, the scc join and
#                                   the module join, and register hotspots intact
#
# Plain bash + coreutils, plus jq for assertions (same as run-parser-tests.sh
# and run-cs-body-parser-tests.sh). Run from anywhere:
#   bash plugins/specclaw/tests/run-quality-tests.sh
# Exits non-zero if any case fails.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_DIR="$PLUGIN_ROOT/bin"
QUALITY_BIN="$BIN_DIR/specclaw-bf-quality-collect"
REBUILD_BIN="$BIN_DIR/specclaw-bf-rebuild-collect"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

[[ -f "$QUALITY_BIN" ]] || { echo "FATAL: missing bin script: $QUALITY_BIN" >&2; exit 2; }
[[ -f "$REBUILD_BIN" ]] || { echo "FATAL: missing bin script: $REBUILD_BIN" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

assert_eq() {
  local label="$1" want="$2" got="$3"
  if [[ "$want" == "$got" ]]; then pass "$label"
  else fail "$label (want '$want', got '$got')"; fi
}

assert_contains() {
  local label="$1" needle="$2" hay="$3"
  if [[ "$hay" == *"$needle"* ]]; then pass "$label"
  else fail "$label (missing '$needle' in: $(printf '%s' "$hay" | head -c 300))"; fi
}

# assert_eq_nonempty — an equality assertion that does NOT pass on two empty
# strings. Needed wherever both sides come from parsing an artifact: if the
# artifact is missing, both sides are "" and a plain assert_eq reports PASS for
# a case that never ran. That false green hid four broken cases here once.
assert_eq_nonempty() {
  local label="$1" want="$2" got="$3"
  if [[ -z "$want" || -z "$got" ]]; then
    fail "$label (one side empty — want '$want', got '$got')"
  else
    assert_eq "$label" "$want" "$got"
  fi
}

# clean_path <stub_dir> — a PATH holding the stub directory, whatever the
# collector genuinely needs (jq lives outside /usr/bin on some platforms, which
# is why this is computed rather than hardcoded), and nothing else. Keeping the
# host's full PATH would let a real jscpd leak in and turn a tool_missing
# assertion into a silent pass; hardcoding /usr/bin:/bin drops jq and makes the
# collector die before it measures anything.
JQ_DIR="$(dirname "$(command -v jq)")"
GIT_DIR_BIN=""
if command -v git >/dev/null 2>&1; then GIT_DIR_BIN=":$(dirname "$(command -v git)")"; fi
clean_path() { printf '%s:%s%s:/usr/bin:/bin' "$1" "$JQ_DIR" "$GIT_DIR_BIN"; }

# ── Fixture + stub writers ──────────────────────────────────────────────────
#
# Fixtures are written by the tests themselves rather than committed, per
# run-cs-body-parser-tests.sh's rule: a committed source fixture drifts out of
# sync with the assertions that depend on it.

# new_project <dir> — a project root with .specclaw/analysis and two sources in
# two languages, one of which lizard does not parse.
new_project() {
  local d="$1"
  mkdir -p "$d/.specclaw/analysis" "$d/src"
  printf 'public class Calc { public void Run() { } }\n' > "$d/src/Calc.cs"
  printf 'unit Legacy;\nbegin\nend.\n' > "$d/src/Legacy.pas"
}

# module_map <dir> <body...> — writes module-map.md with the given module blocks.
module_map_one() {
  local d="$1"
  cat > "$d/.specclaw/analysis/module-map.md" <<'MM'
# Module Map: Fixture

**Status:** CONFIRMED by fixture, 2026-08-25

## Modules

### MOD-001 — Billing

- **Purpose:** the fixture's module
- **Evidence:**
  - `src/Calc.cs:1` — the calculator
MM
}

# stub_dir <dir> — a PATH prefix directory holding metric-tool stubs.
# Each stub emits the documented machine-readable shape and ignores its args;
# the collector intersects tool output with its own enumerated file list, so a
# stub can safely emit rows for paths outside the current scope.
stub_scc() {
  local dir="$1" body="$2"
  mkdir -p "$dir"
  { printf '#!/usr/bin/env bash\ncat <<%s\n' "'SCCJSON'"; printf '%s\n' "$body"; printf 'SCCJSON\n'; } > "$dir/scc"
  chmod +x "$dir/scc"
}

stub_lizard() {
  local dir="$1" body="$2"
  mkdir -p "$dir"
  { printf '#!/usr/bin/env bash\ncat <<%s\n' "'LIZCSV'"; printf '%s\n' "$body"; printf 'LIZCSV\n'; } > "$dir/lizard"
  chmod +x "$dir/lizard"
}

# jscpd writes a report FILE into the directory named by --output, so its stub
# has to find that argument rather than printing to stdout.
stub_jscpd() {
  local dir="$1" body="$2"
  mkdir -p "$dir"
  cat > "$dir/jscpd" <<'JSCPDSTUB'
#!/usr/bin/env bash
out=""
prev=""
for a in "$@"; do
  if [ "$prev" = "--output" ]; then out="$a"; fi
  prev="$a"
done
[ -n "$out" ] || exit 0
mkdir -p "$out"
cat > "$out/jscpd-report.json" <<'JBODY'
__BODY__
JBODY
JSCPDSTUB
  # Substitute the report body without a sed s/// (the JSON carries slashes).
  awk -v b="$body" '{ if ($0 == "__BODY__") print b; else print }' "$dir/jscpd" > "$dir/jscpd.tmp"
  mv "$dir/jscpd.tmp" "$dir/jscpd"
  chmod +x "$dir/jscpd"
}

# A lizard CSV row. Columns, in lizard's own order:
#   nloc,ccn,tokens,params,length,location,file,function,long_name,start,end
liz_row() {
  local file="$1" func="$2" ccn="$3" length="$4"
  printf '%s,%s,100,2,%s,%s@1-1@%s,%s,%s,%s(),1,1\n' \
    "$length" "$ccn" "$length" "$func" "$file" "$file" "$func" "$func"
}

# ── Case 1 — polyglot coverage, and NOT-MEASURED for the unsupported language ──

echo "--- Case 1: polyglot tree — per-language coverage and language_unsupported ---"
C1="$WORK/c1"; new_project "$C1"; module_map_one "$C1"
S1="$WORK/c1-stub"
stub_scc "$S1" '[{"Name":"C#","Files":[{"Location":"src/Calc.cs","Lines":120,"Code":100}]},
 {"Name":"Pascal","Files":[{"Location":"src/Legacy.pas","Lines":300,"Code":250}]}]'
stub_lizard "$S1" "$(liz_row 'src/Calc.cs' 'Run' 4 12)"
stub_jscpd "$S1" '{"statistics":{"formats":{"csharp":{"sources":{"src/Calc.cs":{"lines":120,"duplicatedLines":2}}}}}}'

c1_out="$( cd "$C1" && PATH="$S1:$PATH" bash "$QUALITY_BIN" collect .specclaw 2>/dev/null )"
assert_eq "1a exit 0" "0" "$?"

c1_cs="$(printf '%s' "$c1_out" | jq -r '.coverage[] | select(.language == "C#") | .metrics_available | join(",")')"
assert_eq "1b C# has all three metrics" "loc,complexity,duplication" "$c1_cs"

c1_pas_avail="$(printf '%s' "$c1_out" | jq -r '.coverage[] | select(.language == "Pascal") | .metrics_available | join(",")')"
assert_eq "1c the unsupported language reports size and duplication only" "loc,duplication" "$c1_pas_avail"

c1_pas_nm="$(printf '%s' "$c1_out" | jq -r '.coverage[] | select(.language == "Pascal") | .metrics_not_measured[] | .metric + "/" + .reason')"
assert_eq "1d complexity is NOT-MEASURED with reason language_unsupported" "complexity/language_unsupported" "$c1_pas_nm"

c1_files="$(printf '%s' "$c1_out" | jq -r '"\(.files.classified)/\(.files.sized)/\(.files.function_measured)"')"
assert_eq "1e file counts: 2 classified, 2 sized, 1 function-measured" "2/2/1" "$c1_files"

# ── Case 2 — a missing tool degrades its own metrics and nothing else ─────────

echo "--- Case 2: absent tools degrade to NOT-MEASURED / tool_missing, exit 0 ---"
C2="$WORK/c2"; new_project "$C2"; module_map_one "$C2"
S2="$WORK/c2-stub"
stub_scc "$S2" '[{"Name":"C#","Files":[{"Location":"src/Calc.cs","Lines":120,"Code":100}]}]'
stub_lizard "$S2" "$(liz_row 'src/Calc.cs' 'Run' 4 12)"
# Deliberately no jscpd stub. PATH is the stub dir plus only what the collector
# genuinely needs, so the host's own jscpd (if any) cannot leak in and turn a
# tool_missing assertion into a language_unsupported one.
MINIMAL_PATH="$(clean_path "$S2")"

c2_out="$( cd "$C2" && PATH="$MINIMAL_PATH" bash "$QUALITY_BIN" collect .specclaw 2>/dev/null )"
c2_exit=$?
assert_eq "2a exit 0 with a tool missing" "0" "$c2_exit"

c2_avail="$(printf '%s' "$c2_out" | jq -r '.tool_availability | "\(.scc)/\(.lizard)/\(.jscpd)"')"
assert_eq "2b jscpd reported unavailable" "true/true/false" "$c2_avail"

c2_nm="$(printf '%s' "$c2_out" | jq -r '.coverage[] | select(.language == "C#") | .metrics_not_measured[] | .metric + "/" + .reason')"
assert_eq "2c duplication is NOT-MEASURED with reason tool_missing" "duplication/tool_missing" "$c2_nm"

c2_dup="$(printf '%s' "$c2_out" | jq -r '.modules[] | select(.module_id == "MOD-001") | .duplication.status')"
assert_eq "2d the module's duplication status is NOT-MEASURED, never PASS" "NOT-MEASURED" "$c2_dup"

# All three absent — the honest empty result, still exit 0.
c2b_out="$( cd "$C2" && PATH="$(clean_path "$WORK/empty-stub")" bash "$QUALITY_BIN" collect .specclaw 2>/dev/null )"
c2b_exit=$?
assert_eq "2e no tools at all: exit 0" "0" "$c2b_exit"
if [[ -n "$c2b_out" ]]; then
  c2b_roll="$(printf '%s' "$c2b_out" | jq -r '[.modules[].rollup_status] | unique | join(",")')"
  assert_eq "2f no tools at all: every module rollup is NOT-MEASURED" "NOT-MEASURED" "$c2b_roll"
  c2b_qi="$(printf '%s' "$c2b_out" | jq -r '[.quality_issues[] | select(.status == "open")] | length')"
  assert_eq "2g no tools at all: no hotspot invented" "0" "$c2b_qi"
else
  fail "2f/2g no tools at all: collector produced no JSON"
fi

# ── Case 3 — threshold classification and the worst-status rollup ────────────

echo "--- Case 3: threshold bands and rollup = worst status ---"
C3="$WORK/c3"; new_project "$C3"; module_map_one "$C3"
printf 'public class B { }\n' > "$C3/src/B.cs"
cat > "$C3/.specclaw/analysis/module-map.md" <<'MM'
# Module Map: Fixture

**Status:** CONFIRMED by fixture, 2026-08-25

## Modules

### MOD-001 — Billing

- **Purpose:** the fixture's module
- **Evidence:**
  - `src/Calc.cs:1` — the calculator

### MOD-002 — Reporting

- **Purpose:** the second module
- **Evidence:**
  - `src/B.cs:1` — the report builder
MM
S3="$WORK/c3-stub"
# Both files short enough that file_length is PASS, so complexity is isolated.
stub_scc "$S3" '[{"Name":"C#","Files":[{"Location":"src/Calc.cs","Lines":50,"Code":40},
 {"Location":"src/B.cs","Lines":50,"Code":40}]}]'
# MOD-001: one function at the WARN boundary (11) and one at the HIGH boundary
# (21) — so its complexity status must be the worse of the two.
# MOD-002: one function at 11 only — WARN, and nothing must promote it.
# Lengths are all 12, well under the function-length WARN band.
stub_lizard "$S3" "$(liz_row 'src/Calc.cs' 'Warnish' 11 12)
$(liz_row 'src/Calc.cs' 'Highish' 21 12)
$(liz_row 'src/B.cs' 'Warnish2' 11 12)"

c3_out="$( cd "$C3" && PATH="$(clean_path "$S3")" bash "$QUALITY_BIN" collect .specclaw 2>/dev/null )"

c3_m1="$(printf '%s' "$c3_out" | jq -r '.modules[] | select(.module_id == "MOD-001") | "\(.complexity.status)/\(.complexity.functions_warn)/\(.complexity.functions_high)/\(.complexity.max)"')"
assert_eq "3a complexity 11 is WARN and 21 is HIGH; the module takes HIGH" "HIGH/1/1/21" "$c3_m1"

c3_m2="$(printf '%s' "$c3_out" | jq -r '.modules[] | select(.module_id == "MOD-002") | "\(.complexity.status)/\(.complexity.functions_warn)/\(.complexity.functions_high)"')"
assert_eq "3b a lone complexity-11 function is WARN, not promoted" "WARN/1/0" "$c3_m2"

c3_fl="$(printf '%s' "$c3_out" | jq -r '.modules[] | select(.module_id == "MOD-001") | .file_length.status')"
assert_eq "3c file length below the WARN band is PASS" "PASS" "$c3_fl"

c3_roll="$(printf '%s' "$c3_out" | jq -r '.modules[] | select(.module_id == "MOD-001") | .rollup_status')"
assert_eq "3d the rollup takes the worst status across dimensions" "HIGH" "$c3_roll"

c3_roll2="$(printf '%s' "$c3_out" | jq -r '.modules[] | select(.module_id == "MOD-002") | .rollup_status')"
assert_eq "3e a WARN-only module rolls up WARN, not HIGH" "WARN" "$c3_roll2"

# Only the HIGH band earns a permanent id at the default register_severity.
c3_qi="$(printf '%s' "$c3_out" | jq -r '[.quality_issues[] | select(.status == "open")] | length')"
assert_eq "3f at register_severity HIGH, only the HIGH function is registered" "1" "$c3_qi"

# A config override moves the band, and the number is read from config only.
cat > "$C3/.specclaw/config.yaml" <<'CFG'
version: 1
quality:
  complexity_warn: 3
  complexity_high: 5
CFG
c3o_out="$( cd "$C3" && PATH="$(clean_path "$S3")" bash "$QUALITY_BIN" collect .specclaw 2>/dev/null )"
c3o_th="$(printf '%s' "$c3o_out" | jq -r '.thresholds | "\(.complexity_warn)/\(.complexity_high)"')"
assert_eq "3g thresholds come from config.yaml when set" "3/5" "$c3o_th"
c3o_m2="$(printf '%s' "$c3o_out" | jq -r '.modules[] | select(.module_id == "MOD-002") | .complexity.status')"
assert_eq "3h the same value reclassifies under the overridden band" "HIGH" "$c3o_m2"
rm -f "$C3/.specclaw/config.yaml"

# ── Case 4 — QI permanence ───────────────────────────────────────────────────

echo "--- Case 4: QI ids are permanent; a cleared hotspot resolves, never disappears ---"
C4="$WORK/c4"; new_project "$C4"; module_map_one "$C4"
S4="$WORK/c4-stub"
# A function-level hotspot AND a file-level one. The file-level key carries an
# empty function field, which is the shape that silently vanished before the
# projection stopped using `select` inside object construction — so it is
# asserted explicitly rather than left implied.
stub_scc "$S4" '[{"Name":"C#","Files":[{"Location":"src/Calc.cs","Lines":1500,"Code":1400}]}]'
stub_lizard "$S4" "$(liz_row 'src/Calc.cs' 'Run' 34 200)"

( cd "$C4" && PATH="$(clean_path "$S4")" bash "$QUALITY_BIN" collect .specclaw >/dev/null 2>&1 )
c4_r1="$(jq -S -c '[.quality_issues[] | {id, key, status, first_seen}]' "$C4/.specclaw/analysis/quality.json")"
( cd "$C4" && PATH="$(clean_path "$S4")" bash "$QUALITY_BIN" collect .specclaw >/dev/null 2>&1 )
c4_r2="$(jq -S -c '[.quality_issues[] | {id, key, status, first_seen}]' "$C4/.specclaw/analysis/quality.json")"
assert_eq_nonempty "4a an unchanged re-run assigns byte-identical QI ids and first_seen" "$c4_r1" "$c4_r2"

c4_n1="$(printf '%s' "$c4_r1" | jq 'length')"
assert_eq "4b three hotspots registered (complexity, function length, file length)" "3" "$c4_n1"

c4_filelevel="$(jq -r '[.quality_issues[] | select(.metric == "file_length")] | length' "$C4/.specclaw/analysis/quality.json")"
assert_eq "4c the file-level hotspot is registered despite its empty function field" "1" "$c4_filelevel"

# Now clear every hotspot. Ids must survive with status resolved.
stub_scc "$S4" '[{"Name":"C#","Files":[{"Location":"src/Calc.cs","Lines":80,"Code":70}]}]'
stub_lizard "$S4" "$(liz_row 'src/Calc.cs' 'Run' 3 10)"
( cd "$C4" && PATH="$(clean_path "$S4")" bash "$QUALITY_BIN" collect .specclaw >/dev/null 2>&1 )

c4_ids_before="$(printf '%s' "$c4_r1" | jq -r '[.[].id] | sort | join(",")')"
c4_ids_after="$(jq -r '[.quality_issues[].id] | sort | join(",")' "$C4/.specclaw/analysis/quality.json")"
assert_eq_nonempty "4d every id survives the hotspot being fixed" "$c4_ids_before" "$c4_ids_after"

c4_statuses="$(jq -r '[.quality_issues[].status] | unique | join(",")' "$C4/.specclaw/analysis/quality.json")"
assert_eq "4e all are marked resolved, none removed" "resolved" "$c4_statuses"

c4_reg="$(grep -c '^### QI-' "$C4/.specclaw/analysis/quality-issues.md")"
assert_eq "4f the registry file still holds all three entries" "3" "$c4_reg"

c4_first_kept="$(jq -r '[.quality_issues[].first_seen] | unique | length' "$C4/.specclaw/analysis/quality.json")"
assert_eq "4g first_seen is preserved through the resolution, not restamped" "1" "$c4_first_kept"

# Regressing the same hotspot must reuse the original id, not mint a new one.
stub_lizard "$S4" "$(liz_row 'src/Calc.cs' 'Run' 34 200)"
( cd "$C4" && PATH="$(clean_path "$S4")" bash "$QUALITY_BIN" collect .specclaw >/dev/null 2>&1 )
c4_reopen="$(jq -r '.quality_issues[] | select(.metric == "complexity" and .status == "open") | .id' "$C4/.specclaw/analysis/quality.json")"
c4_orig="$(printf '%s' "$c4_r1" | jq -r '.[] | select(.key | startswith("complexity|")) | .id')"
assert_eq_nonempty "4h a hotspot that comes back reopens under its original id" "$c4_orig" "$c4_reopen"

# A target-scope run registers nothing — QI ids name legacy hotspots only.
mkdir -p "$C4/rebuilt"; printf 'public class R { }\n' > "$C4/rebuilt/R.cs"
c4_regbefore="$(grep -c '^### QI-' "$C4/.specclaw/analysis/quality-issues.md")"
( cd "$C4" && PATH="$(clean_path "$S4")" bash "$QUALITY_BIN" collect .specclaw rebuilt --target >/dev/null 2>&1 )
c4_regafter="$(grep -c '^### QI-' "$C4/.specclaw/analysis/quality-issues.md")"
assert_eq "4i a --target run registers no QI" "$c4_regbefore" "$c4_regafter"

# ── Case 5 — compare ─────────────────────────────────────────────────────────

echo "--- Case 5: compare classifies improved / regressed / NOT-COMPARABLE ---"
C5="$WORK/c5"; new_project "$C5"
mkdir -p "$C5/rebuilt"; printf 'public class R { }\n' > "$C5/rebuilt/R.cs"
cat > "$C5/.specclaw/analysis/module-map.md" <<'MM'
# Module Map: Fixture

**Status:** CONFIRMED by fixture, 2026-08-25

## Modules

### MOD-001 — Billing

- **Purpose:** spans both trees
- **Evidence:**
  - `src/Calc.cs:1` — the legacy calculator
  - `rebuilt/R.cs:1` — the rebuilt calculator
MM
S5="$WORK/c5-stub"
stub_scc "$S5" '[{"Name":"C#","Files":[{"Location":"src/Calc.cs","Lines":1500,"Code":1400},
 {"Location":"rebuilt/R.cs","Lines":90,"Code":80}]},
 {"Name":"Pascal","Files":[{"Location":"src/Legacy.pas","Lines":100,"Code":90}]}]'
stub_lizard "$S5" "$(liz_row 'src/Calc.cs' 'Run' 34 200)
$(liz_row 'rebuilt/R.cs' 'Run' 4 20)"

( cd "$C5" && PATH="$(clean_path "$S5")" bash "$QUALITY_BIN" collect .specclaw src >/dev/null 2>&1 )
( cd "$C5" && PATH="$(clean_path "$S5")" bash "$QUALITY_BIN" collect .specclaw rebuilt --target >/dev/null 2>&1 )
( cd "$C5" && bash "$QUALITY_BIN" compare .specclaw >/dev/null 2>&1 )
c5_exit=$?
assert_eq "5a compare exits 0 in advisory mode" "0" "$c5_exit"

C5D="$C5/.specclaw/analysis/quality-delta.json"
c5_cx="$(jq -r '.deltas[] | select(.module_id == "MOD-001" and .metric == "complexity") | .classification' "$C5D")"
assert_eq "5b a HIGH-to-PASS dimension is improved" "improved" "$c5_cx"

# Duplication was measured on NEITHER side (no jscpd), so it is not comparable —
# and specifically not an improvement.
c5_dup="$(jq -r '.deltas[] | select(.module_id == "MOD-001" and .metric == "duplication") | .classification' "$C5D")"
assert_eq "5c a dimension measured on neither side is NOT-COMPARABLE" "NOT-COMPARABLE" "$c5_dup"

# The load-bearing one: legacy unmeasured, target measured. Never "improved".
C5B="$WORK/c5b"; new_project "$C5B"
rm -f "$C5B/src/Calc.cs"                        # legacy is the unsupported language only
mkdir -p "$C5B/rebuilt"; printf 'public class R { }\n' > "$C5B/rebuilt/R.cs"
cat > "$C5B/.specclaw/analysis/module-map.md" <<'MM'
# Module Map: Fixture

**Status:** CONFIRMED by fixture, 2026-08-25

## Modules

### MOD-001 — Billing

- **Purpose:** spans both trees
- **Evidence:**
  - `src/Legacy.pas:1` — the legacy unit
  - `rebuilt/R.cs:1` — the rebuilt calculator
MM
S5B="$WORK/c5b-stub"
stub_scc "$S5B" '[{"Name":"Pascal","Files":[{"Location":"src/Legacy.pas","Lines":90,"Code":80}]},
 {"Name":"C#","Files":[{"Location":"rebuilt/R.cs","Lines":90,"Code":80}]}]'
stub_lizard "$S5B" "$(liz_row 'rebuilt/R.cs' 'Run' 4 20)"

( cd "$C5B" && PATH="$(clean_path "$S5B")" bash "$QUALITY_BIN" collect .specclaw src >/dev/null 2>&1 )
( cd "$C5B" && PATH="$(clean_path "$S5B")" bash "$QUALITY_BIN" collect .specclaw rebuilt --target >/dev/null 2>&1 )
( cd "$C5B" && bash "$QUALITY_BIN" compare .specclaw >/dev/null 2>&1 )

c5b_legacy="$(jq -r '.deltas[] | select(.module_id == "MOD-001" and .metric == "complexity") | .legacy_status' "$C5B/.specclaw/analysis/quality-delta.json")"
c5b_target="$(jq -r '.deltas[] | select(.module_id == "MOD-001" and .metric == "complexity") | .target_status' "$C5B/.specclaw/analysis/quality-delta.json")"
c5b_class="$(jq -r '.deltas[] | select(.module_id == "MOD-001" and .metric == "complexity") | .classification' "$C5B/.specclaw/analysis/quality-delta.json")"
assert_eq "5d legacy complexity was unmeasurable" "NOT-MEASURED" "$c5b_legacy"
assert_eq "5e target complexity was measured" "PASS" "$c5b_target"
assert_eq "5f unmeasured legacy vs measured target is NOT-COMPARABLE, never improved" "NOT-COMPARABLE" "$c5b_class"

# compare fails fast, and says which snapshot is missing.
C5C="$WORK/c5c"; mkdir -p "$C5C/.specclaw/analysis"
c5c_err="$( cd "$C5C" && bash "$QUALITY_BIN" compare .specclaw 2>&1 1>/dev/null )"
c5c_exit=$?
if [[ "$c5c_exit" -ne 0 ]]; then pass "5g compare with no snapshots exits non-zero"
else fail "5g compare with no snapshots exits non-zero (got 0)"; fi
assert_contains "5h the refusal names the missing legacy snapshot" "quality.json" "$c5c_err"
assert_contains "5i the refusal names the missing target snapshot" "quality-target.json" "$c5c_err"

# ── Case 6 — the gate ────────────────────────────────────────────────────────

echo "--- Case 6: gate FAILs on regression with exit 1, PASSes with exit 0 ---"
# Reuse C5's improved pair for the PASS path.
c6_pass_out="$( cd "$C5" && bash "$QUALITY_BIN" compare .specclaw --gate 2>/dev/null )"
c6_pass_exit=$?
assert_eq "6a improved target: verdict line is PASS" "QUALITY-GATE: PASS" "$c6_pass_out"
assert_eq "6b improved target: exit 0" "0" "$c6_pass_exit"

# Now invert the pair: the rebuild is worse than the legacy it replaced.
stub_lizard "$S5" "$(liz_row 'src/Calc.cs' 'Run' 4 20)
$(liz_row 'rebuilt/R.cs' 'Run' 34 200)"
stub_scc "$S5" '[{"Name":"C#","Files":[{"Location":"src/Calc.cs","Lines":90,"Code":80},
 {"Location":"rebuilt/R.cs","Lines":1500,"Code":1400}]},
 {"Name":"Pascal","Files":[{"Location":"src/Legacy.pas","Lines":100,"Code":90}]}]'
( cd "$C5" && PATH="$(clean_path "$S5")" bash "$QUALITY_BIN" collect .specclaw src >/dev/null 2>&1 )
( cd "$C5" && PATH="$(clean_path "$S5")" bash "$QUALITY_BIN" collect .specclaw rebuilt --target >/dev/null 2>&1 )
c6_fail_out="$( cd "$C5" && bash "$QUALITY_BIN" compare .specclaw --gate 2>/dev/null )"
c6_fail_exit=$?
assert_eq "6c regressed target: exit 1" "1" "$c6_fail_exit"
assert_contains "6d regressed target: verdict line is FAIL with a count" "QUALITY-GATE: FAIL (" "$c6_fail_out"

c6_regs="$(jq -r '.gate.regression_count' "$C5D")"
if [[ "$c6_regs" -gt 0 ]]; then pass "6e the delta records the regressions the gate counted"
else fail "6e the delta records the regressions the gate counted (got $c6_regs)"; fi

# Without --gate the same regressed pair reports and exits 0. Advisory means
# advisory: the gate is the only thing that ever blocks.
( cd "$C5" && bash "$QUALITY_BIN" compare .specclaw >/dev/null 2>&1 )
assert_eq "6f the same regression without --gate exits 0" "0" "$?"

# ── Case 7 — rebuild-plan neutrality ─────────────────────────────────────────

echo "--- Case 7: bf-rebuild-plan is unchanged when quality.json is absent ---"
# Both projects share the same BASENAME under different parents. The rendered
# document's title is derived from the project directory name, so differently
# named fixtures would make the two outputs differ in their heading and defeat
# the byte-comparison this case exists for.
C7A="$WORK/c7-without/proj"; C7B="$WORK/c7-with/proj"
for d in "$C7A" "$C7B"; do
  mkdir -p "$d/.specclaw/analysis"
  cp -R "$FIXTURES_DIR/rebuild-plan/analysis/." "$d/.specclaw/analysis/"
done
C7_DRAFT="$WORK/c7-draft.md"
cat > "$C7_DRAFT" <<'DRAFT'
### BL-001 — Manage Things

**Module:** MOD-001
**Maps to capability:** "Create and edit a Thing"
**Depends on:** None
**Acceptance basis (domain-model.md):**
- DR-001: a Thing must have a name

**Verification inputs needed:**
- A golden-master capture of the Thing editor.

## Sequencing Rationale

Single item, nothing to sequence.

## Coverage Check

- **MOD-001** — "Create and edit a Thing" → BL-001

**Orphaned:** none

### Open Questions Blocking Readiness

None — no open questions touch any item's acceptance basis.
DRAFT

# The annotated run gets a quality.json; the other gets none. Everything else
# about the two projects is identical, including the draft.
cat > "$C7B/.specclaw/analysis/quality.json" <<'QJ'
{"schema_version":1,
 "modules":[{"module_id":"MOD-001","rollup_status":"HIGH"}],
 "quality_issues":[{"id":"QI-001","module_id":"MOD-001","status":"open"},
                   {"id":"QI-002","module_id":"MOD-001","status":"open"},
                   {"id":"QI-003","module_id":"MOD-001","status":"resolved"}]}
QJ

cp "$C7_DRAFT" "$C7A/.specclaw/analysis/.rebuild-plan-draft.md"
( cd "$C7A" && bash "$REBUILD_BIN" render .specclaw .specclaw/analysis/.rebuild-plan-draft.md >/dev/null 2>&1 )
assert_eq "7a render succeeds with no quality.json" "0" "$?"
cp "$C7_DRAFT" "$C7B/.specclaw/analysis/.rebuild-plan-draft.md"
( cd "$C7B" && bash "$REBUILD_BIN" render .specclaw .specclaw/analysis/.rebuild-plan-draft.md >/dev/null 2>&1 )
assert_eq "7b render succeeds with a quality.json" "0" "$?"

C7A_OUT="$C7A/.specclaw/analysis/rebuild-backlog.md"
C7B_OUT="$C7B/.specclaw/analysis/rebuild-backlog.md"

# The un-annotated run must carry the rollup line and NO quality text anywhere.
if grep -qE '^- \*\*MOD-001 — Core:\*\* 1/1 capability bullets covered; 0 excluded; 0 orphaned$' "$C7A_OUT"; then
  pass "7c with no quality.json the rollup line ends exactly where it always did"
else
  fail "7c with no quality.json the rollup line ends exactly where it always did (got: $(grep -E '^- \*\*MOD-001' "$C7A_OUT" | head -1))"
fi
# GENERATED content only. Every HTML comment in the rendered file is the
# template's own prose, copied verbatim whether or not quality.json exists, and
# the template has to document the quality-remediation mechanism for
# QUALITY-MEASURED to be discoverable at all. Stripping the comments is what
# keeps this assertion about what it was always about: that a project which
# never measured gets a document with no quality FINDINGS in it.
c7a_generated="$(awk '/^<!--/{c=1} c{ if (/-->/) c=0; next } {print}' "$C7A_OUT")"
if printf '%s' "$c7a_generated" | grep -qi 'quality'; then
  fail "7d with no quality.json nothing generated mentions quality (found: $(printf '%s' "$c7a_generated" | grep -in 'quality' | head -2))"
else
  pass "7d with no quality.json nothing generated mentions quality"
fi

# THE NEUTRALITY PROOF. Diff the two runs and require every differing line to be
# a quality annotation. Anything else differing would mean the hook changed
# output it has no business touching.
c7_diff="$(diff "$C7A_OUT" "$C7B_OUT" | grep -E '^[<>]' || true)"
# A rollup line appears on BOTH sides of the diff — un-suffixed on the `<` side,
# suffixed on the `>` side — so both must be allowed, not just the annotated one.
# Filtering only for the suffix text would report the un-suffixed half as stray.
c7_stray="$(printf '%s\n' "$c7_diff" \
  | grep -E '^[<>]' \
  | grep -vE '^[<>] - \*\*MOD-[0-9]+ — ' \
  | grep -vE 'warrant extra rebuild attention' \
  | grep -vE '^[<>][[:space:]]*$' || true)"
if [[ -z "$c7_stray" ]]; then
  pass "7e the annotation is the ONLY difference between the two renders"
else
  fail "7e the annotation is the ONLY difference between the two renders (stray: $(printf '%s' "$c7_stray" | head -c 300))"
fi

assert_contains "7f the annotated rollup carries the status and open-QI count" \
  "0 orphaned; quality HIGH (2 open QI)" "$(grep -E '^- \*\*MOD-001 — ' "$C7B_OUT" | head -1)"
if grep -q 'warrant extra rebuild attention' "$C7B_OUT"; then
  pass "7g HIGH modules are flagged for extra rebuild attention"
else
  fail "7g HIGH modules are flagged for extra rebuild attention"
fi

# A malformed or unreadable quality.json degrades to the absent case rather than
# breaking the backlog. Every failure mode is the same empty string.
C7C="$WORK/c7-broken/proj"; mkdir -p "$C7C/.specclaw/analysis"
cp -R "$FIXTURES_DIR/rebuild-plan/analysis/." "$C7C/.specclaw/analysis/"
printf 'this is not json at all\n' > "$C7C/.specclaw/analysis/quality.json"
cp "$C7_DRAFT" "$C7C/.specclaw/analysis/.rebuild-plan-draft.md"
( cd "$C7C" && bash "$REBUILD_BIN" render .specclaw .specclaw/analysis/.rebuild-plan-draft.md >/dev/null 2>&1 )
c7c_exit=$?
assert_eq "7h an unreadable quality.json does not break render" "0" "$c7c_exit"
if diff -q "$C7A_OUT" "$C7C/.specclaw/analysis/rebuild-backlog.md" >/dev/null 2>&1; then
  pass "7i an unreadable quality.json degrades to byte-identical un-annotated output"
else
  fail "7i an unreadable quality.json degrades to byte-identical un-annotated output"
fi

# ── Case 8 — advisory neutrality ─────────────────────────────────────────────

echo "--- Case 8: HIGH findings are advisory and still exit 0 ---"
C8="$WORK/c8"; new_project "$C8"; module_map_one "$C8"
S8="$WORK/c8-stub"
stub_scc "$S8" '[{"Name":"C#","Files":[{"Location":"src/Calc.cs","Lines":5000,"Code":4800}]}]'
stub_lizard "$S8" "$(liz_row 'src/Calc.cs' 'Run' 99 900)"
( cd "$C8" && PATH="$(clean_path "$S8")" bash "$QUALITY_BIN" collect .specclaw >/dev/null 2>&1 )
assert_eq "8a a run full of HIGH findings exits 0" "0" "$?"
c8_roll="$(jq -r '.modules[] | select(.module_id == "MOD-001") | .rollup_status' "$C8/.specclaw/analysis/quality.json")"
assert_eq "8b and the findings really are HIGH" "HIGH" "$c8_roll"

# The snapshot is archived rather than overwritten, and the archived copy says
# it is superseded.
( cd "$C8" && PATH="$(clean_path "$S8")" bash "$QUALITY_BIN" collect .specclaw >/dev/null 2>&1 )
c8_arch="$(find "$C8/.specclaw/analysis/archive" -name '*-quality.json' 2>/dev/null | head -1)"
if [[ -n "$c8_arch" ]]; then
  pass "8c a re-run archives the prior snapshot"
  c8_sup="$(jq -r '.superseded' "$c8_arch" 2>/dev/null)"
  assert_eq "8d the archived snapshot is flagged superseded" "true" "$c8_sup"
else
  fail "8c a re-run archives the prior snapshot"
  fail "8d the archived snapshot is flagged superseded"
fi

# ── Case 9 — the module join ──────────────────────────────────────────────────

echo "--- Case 9: uncited files roll up under MOD-UNASSIGNED; ambiguity is not guessed ---"
C9="$WORK/c9"; new_project "$C9"
printf 'public class Shared { }\n' > "$C9/src/Shared.cs"
printf 'public class Lonely { }\n' > "$C9/src/Lonely.cs"
cat > "$C9/.specclaw/analysis/module-map.md" <<'MM'
# Module Map: Fixture

**Status:** PROPOSED

## Modules

### MOD-001 — Billing

- **Purpose:** cites one file, and shares one
- **Evidence:**
  - `src/Calc.cs:1` — the calculator
  - `src/Shared.cs:3` — shared helper

### MOD-002 — Reporting

- **Purpose:** also claims the shared file
- **Evidence:**
  - `src/Shared.cs:9` — shared helper again

### MOD-003 — Retired — WITHDRAWN 2026-08-25, superseded by MOD-001

- **Evidence:**
  - `src/Lonely.cs:1` — a tombstone must not claim a file
MM
S9="$WORK/c9-stub"
stub_scc "$S9" '[{"Name":"C#","Files":[{"Location":"src/Calc.cs","Lines":50,"Code":40},
 {"Location":"src/Shared.cs","Lines":50,"Code":40},
 {"Location":"src/Lonely.cs","Lines":50,"Code":40}]},
 {"Name":"Pascal","Files":[{"Location":"src/Legacy.pas","Lines":50,"Code":40}]}]'
stub_lizard "$S9" "$(liz_row 'src/Calc.cs' 'Run' 4 12)"

c9_out="$( cd "$C9" && PATH="$(clean_path "$S9")" bash "$QUALITY_BIN" collect .specclaw 2>/dev/null )"

c9_m1="$(printf '%s' "$c9_out" | jq -r '.modules[] | select(.module_id == "MOD-001") | .files')"
assert_eq "9a a module gets exactly the files it cites unambiguously" "1" "$c9_m1"

c9_unassigned="$(printf '%s' "$c9_out" | jq -r '.modules[] | select(.module_id == "MOD-UNASSIGNED") | .files')"
assert_eq "9b uncited, tombstone-cited and ambiguous files all land in MOD-UNASSIGNED" "3" "$c9_unassigned"

c9_ambig="$(printf '%s' "$c9_out" | jq -r '.files.module_ambiguous')"
assert_eq "9c the file two modules cite is counted as ambiguous, not allocated" "1" "$c9_ambig"

c9_m2="$(printf '%s' "$c9_out" | jq -r '[.modules[] | select(.module_id == "MOD-002")] | length')"
assert_eq "9d a module whose only citation was ambiguous claims no files" "0" "$c9_m2"

c9_status="$(printf '%s' "$c9_out" | jq -r '.module_map_status')"
assert_eq "9e an unconfirmed map is reported as PROPOSED, not treated as confirmed" "PROPOSED" "$c9_status"

# No map at all is a normal state, not an error.
C9B="$WORK/c9b"; new_project "$C9B"
c9b_out="$( cd "$C9B" && PATH="$(clean_path "$S9")" bash "$QUALITY_BIN" collect .specclaw 2>/dev/null )"
c9b_exit=$?
assert_eq "9f no module-map.md at all: exit 0" "0" "$c9b_exit"
c9b_mods="$(printf '%s' "$c9b_out" | jq -r '[.modules[].module_id] | join(",")')"
assert_eq "9g with no map every file rolls up under MOD-UNASSIGNED" "MOD-UNASSIGNED" "$c9b_mods"
c9b_status="$(printf '%s' "$c9b_out" | jq -r '.module_map_status')"
assert_eq "9h and the absence is reported rather than implied" "ABSENT" "$c9b_status"

# ── Case 10 — the report template is client-safe ──────────────────────────────

echo "--- Case 10: the report template body names no internal command ---"
# What is mechanically checkable here is the TEMPLATE, not a generated report:
# the report is written by an agent, which no bash suite can run. So this pins
# the thing the agent is handed — if an internal name is not in the template's
# body, the agent has to invent one to leak it, and its own prompt forbids that.
for tpl in quality-report.md quality-delta.md; do
  T="$PLUGIN_ROOT/templates/$tpl"
  if [[ ! -f "$T" ]]; then fail "10 template exists: $tpl"; continue; fi

  # Everything above the provenance heading, with HTML comments removed — the
  # comments are authoring guidance for the agent and are expected to discuss
  # the pipeline by name.
  body="$(awk '/^## Internal provenance/{exit} {print}' "$T" | awk '/<!--/{c=1} !c{print} /-->/{c=0}')"

  leaked=""
  for name in "specclaw" "SpecClaw" "bf-quality" "bf-rebuild-plan" "bf-analyze" "bf-domain"; do
    case "$body" in *"$name"*) leaked="${leaked}${name} " ;; esac
  done
  if [[ -z "$leaked" ]]; then
    pass "10a ${tpl} body carries no internal command or framework name"
  else
    fail "10a ${tpl} body carries no internal command or framework name (leaked: $leaked)"
  fi

  if grep -q '^## Internal provenance' "$T"; then
    pass "10b ${tpl} has the provenance section internal names belong in"
  else
    fail "10b ${tpl} has the provenance section internal names belong in"
  fi
done

# The agent prompt must actually forbid the agent doing its own measuring.
AGENT="$PLUGIN_ROOT/agents/bf-quality-analyst.md"
if [[ -f "$AGENT" ]]; then
  agent_body="$(cat "$AGENT")"
  assert_contains "10c the agent prompt names its single JSON input" "quality.json" "$agent_body"
  # tools: is the hard guarantee — Read and Write only means no Bash, so the
  # agent cannot invoke a metric tool whatever the prose says.
  if grep -qE '^tools: *Read, *Write$' "$AGENT"; then
    pass "10d the agent is granted Read and Write only, so it cannot run a tool"
  else
    fail "10d the agent is granted Read and Write only (got: $(grep -E '^tools:' "$AGENT"))"
  fi
else
  fail "10c the quality agent prompt exists"
  fail "10d the agent is granted Read and Write only"
fi

# ── Case 11 — the ARG_MAX regression: a file list too big for argv ────────────
#
# The bug: the aggregation step passed each per-file JSON array as
# `--argjson X "$(cat X.json)"`. Those arrays carry one element per source file,
# so on a large repo the substitution put multiple megabytes into a single argv
# slot and the run died with "Argument list too long" (E2BIG) before jq started
# — a single argument over MAX_ARG_STRLEN (128 KiB on Linux) is enough to trip
# it, well below the total ARG_MAX. The fix reads those files with --slurpfile,
# off argv entirely. This case builds a tree whose joined path list is over 2 MB
# and requires the collector to complete with exit 0.
#
# Metric tools are deliberately ABSENT here: the file list is built from the
# extension classification, independent of any tool, so the argv pressure is
# reproduced without invoking scc/lizard/jscpd across thousands of files (which
# would make the case slow without testing anything new). loc/funcs/dup come
# back empty; files.json and filemod.json are what get large.

echo "--- Case 11: a >2 MB joined file list does not overflow argv (ARG_MAX) ---"
C11="$WORK/c11"
mkdir -p "$C11/.specclaw/analysis"
# Long nested paths: a handful of long-named directories, each holding many
# long-named files, reaches >2 MB of path text with far fewer inodes than flat
# files would — so the case stays fast while genuinely exceeding the threshold.
DIRPAD="dir_$(printf 'd%.0s' $(seq 1 96))"          # ~100-char directory names
FILEPAD="$(printf 'f%.0s' $(seq 1 196))"            # ~200-char file stems
mkdir -p "$C11/src"
n_created=0
for d in $(seq 1 10); do
  sub="$C11/src/${DIRPAD}_${d}"
  mkdir -p "$sub"
  for i in $(seq 1 800); do
    printf 'class C{}' > "$sub/${FILEPAD}_${i}.cs"
    n_created=$((n_created + 1))
  done
done
# No module-map: every file rolls up under MOD-UNASSIGNED, which is fine — the
# point is the size of the list, not the join.
list_bytes="$(find "$C11/src" -type f -name '*.cs' | wc -c | tr -d ' ')"
if [[ "$list_bytes" -gt 2097152 ]]; then
  pass "11a the generated path list exceeds 2 MB (${list_bytes} bytes across ${n_created} files)"
else
  fail "11a the generated path list exceeds 2 MB (only ${list_bytes} bytes) — case would not exercise the bug"
fi

# The regression itself: the FIXED collector must complete cleanly.
c11_out="$( cd "$C11" && PATH="$(clean_path "$WORK/empty-stub")" bash "$QUALITY_BIN" collect .specclaw 2>/dev/null )"
c11_exit=$?
assert_eq "11b collect exits 0 on a >2 MB file list" "0" "$c11_exit"
if [[ -n "$c11_out" ]]; then
  c11_classified="$(printf '%s' "$c11_out" | jq -r '.files.classified')"
  assert_eq "11c every generated .cs file was classified and measured" "$n_created" "$c11_classified"
else
  fail "11c every generated .cs file was classified and measured (collector produced no JSON)"
fi

# Belt and braces: prove the PRE-fix code actually failed on this same tree, so
# the case is known to exercise the bug rather than passing vacuously. This is
# informational — some platforms (notably MSYS2) raise the single-arg limit, so
# a clean pre-run is reported, not asserted.
PRE_COLLECT="$WORK/pre-collect"
if git -C "$SCRIPT_DIR" show "feat/bf-quality:plugins/specclaw/bin/specclaw-bf-quality-collect" > "$PRE_COLLECT" 2>/dev/null && [[ -s "$PRE_COLLECT" ]]; then
  ( cd "$C11" && PATH="$(clean_path "$WORK/empty-stub")" bash "$PRE_COLLECT" collect .specclaw >/dev/null 2>&1 )
  pre_exit=$?
  if [[ "$pre_exit" -ne 0 ]]; then
    pass "11d (informational) the pre-fix collector failed on this tree (exit ${pre_exit}), confirming the case bites"
  else
    echo "NOTE: 11d the pre-fix collector did NOT fail here (exit 0) — this platform's single-arg limit is above the list size; the fix is still exercised by 11b."
    PASS=$((PASS + 1))
  fi
else
  echo "NOTE: 11d pre-fix binary not retrievable (feat/bf-quality not present) — skipping the informational pre-run."
  PASS=$((PASS + 1))
fi

# ── Case 12 — paths with spaces and unicode are measured, not mangled ─────────

echo "--- Case 12: filenames with spaces and unicode survive the whole pipeline ---"
C12="$WORK/c12"
mkdir -p "$C12/.specclaw/analysis" "$C12/src"
printf 'public class A { }\n' > "$C12/src/My Invoice Calc.cs"
printf 'public class B { }\n' > "$C12/src/naïve café résumé.cs"
cat > "$C12/.specclaw/analysis/module-map.md" <<'MM'
# Module Map: Unicode

**Status:** CONFIRMED by fixture, 2026-08-25

## Modules

### MOD-001 — Billing

- **Evidence:**
  - `src/My Invoice Calc.cs:1` — the calculator with spaces in its name
MM
S12="$WORK/c12-stub"
# scc/lizard emit rows keyed by the exact spaced/unicode paths, to prove the
# join survives them too (not just enumeration).
stub_scc "$S12" '[{"Name":"C#","Files":[
 {"Location":"src/My Invoice Calc.cs","Lines":1400,"Code":1300},
 {"Location":"src/naïve café résumé.cs","Lines":50,"Code":40}]}]'
stub_lizard "$S12" "$(liz_row 'src/My Invoice Calc.cs' 'Run' 34 150)"

c12_out="$( cd "$C12" && PATH="$(clean_path "$S12")" bash "$QUALITY_BIN" collect .specclaw 2>/dev/null )"
c12_exit=$?
assert_eq "12a collect exits 0 with spaced/unicode paths" "0" "$c12_exit"

c12_classified="$(printf '%s' "$c12_out" | jq -r '.files.classified')"
assert_eq "12b both files were classified, neither split on its space" "2" "$c12_classified"

# Both files' size rows joined — proving the scc join keys survive the space and
# the non-ASCII bytes intact, not just enumeration.
c12_sized="$(printf '%s' "$c12_out" | jq -r '.files.sized')"
assert_eq "12c both spaced/unicode files joined to their scc size rows" "2" "$c12_sized"

# Their LOC is summed correctly (1300 + 40). This is the "measured correctly"
# guarantee: every metric is computed with the path intact and no word-splitting.
c12_loc="$(printf '%s' "$c12_out" | jq -r '[.modules[].loc] | add')"
assert_eq "12d the LOC of both files is measured and summed correctly" "1340" "$c12_loc"

# A complexity hotspot on the spaced path is registered with the path byte-exact
# in its key — the path travelled intact all the way into the QI registry.
c12_hot="$(printf '%s' "$c12_out" | jq -r '[.quality_issues[] | select(.file == "src/My Invoice Calc.cs")] | length')"
if [[ "$c12_hot" -ge 1 ]]; then
  pass "12e a hotspot on the spaced path is registered with the path intact"
else
  fail "12e a hotspot on the spaced path is registered with the path intact (got $c12_hot)"
fi

# KNOWN LIMITATION, asserted so it is documented rather than surprising: the
# module-map Evidence citation `src/My Invoice Calc.cs` does NOT match this file,
# because parse_module_citations' path regex has no space in its character
# class. So a spaced path cited in the map rolls up under MOD-UNASSIGNED. This
# is pre-existing, unrelated to the ARG_MAX fix, and deliberately not changed
# here (that would be a second behavioural change under a fix ticket). The file
# is still fully measured — it just is not attributed to its module.
c12_unassigned_loc="$(printf '%s' "$c12_out" | jq -r '.modules[] | select(.module_id == "MOD-UNASSIGNED") | .loc')"
assert_eq "12f (documents a pre-existing gap) a spaced citation is unmatched, so both files sit under MOD-UNASSIGNED" "1340" "$c12_unassigned_loc"

# ── Case 13 — quality remediation backlog items ──────────────────────────────
#
# The measured hotspots stop being advice and become something the rebuild is
# accountable for. Every assertion here is about a state BASH computed: which
# modules get an item, which hotspots each lists, whether it is gated, and
# whether the delta says it is done. The agent narrates; it decides nothing.
#
# WHAT KEEPS THIS OPTIONAL is asserted first and asserted twice — here, and in
# Case 7's byte-for-byte diff of an annotated against an un-annotated render.

echo
echo "--- Case 13: quality remediation items ---"

REPLAY_BIN="$BIN_DIR/specclaw-bf-replay"

# A three-module project: MOD-001 and MOD-002 will measure HIGH, MOD-003 only
# WARN. That is the shape the whole severity-floor behaviour turns on.
qr_project() {
  local root="$1"
  rm -rf "$root"; mkdir -p "$root/.specclaw/analysis"
  cat > "$root/.specclaw/analysis/module-map.md" <<'MM'
# Module Map: QR

**Status:** CONFIRMED by Tester, 2026-08-31

## Modules

### MOD-001 — Auth

- **Business rules:** DR-001
- **Depends on:** None

### MOD-002 — Billing

- **Business rules:** DR-002
- **Depends on:** MOD-001

### MOD-003 — Reports

- **Business rules:** DR-003
- **Depends on:** MOD-002
MM
  printf '### DR-001 — a\n### DR-002 — b\n### DR-003 — c\n' \
    > "$root/.specclaw/analysis/domain-model.md"
  cat > "$root/draft.md" <<'DR'
### BL-001 — Sign In

**Module:** MOD-001
**Depends on:** None
**Acceptance basis (domain-model.md):**
- DR-001: a session is authenticated before any action.

### BL-002 — Raise an Invoice

**Module:** MOD-002
**Depends on:** BL-001
**Acceptance basis (domain-model.md):**
- DR-002: an invoice has at least one line.

### BL-003 — Monthly Statement

**Module:** MOD-003
**Depends on:** BL-002
**Acceptance basis (domain-model.md):**
- DR-003: a statement covers one calendar month.

## Sequencing Rationale

Auth, then billing, then reporting.

## Coverage Check

- **MOD-001** — "Sign in" → BL-001
- **MOD-002** — "Raise an invoice" → BL-002
- **MOD-003** — "Monthly statement" → BL-003
DR
}

# MOD-001: two HIGH hotspots. MOD-002: one HIGH. MOD-003: one WARN only, which
# under the default HIGH floor must produce an advisory count and NO item.
qr_quality_json() {
  cat > "$1/.specclaw/analysis/quality.json" <<'QJ'
{"schema_version":1,
 "thresholds":{"complexity_high":20,"file_length_high":1000,"register_severity":"WARN"},
 "modules":[{"module_id":"MOD-001","rollup_status":"HIGH"},
            {"module_id":"MOD-002","rollup_status":"HIGH"},
            {"module_id":"MOD-003","rollup_status":"WARN"}],
 "quality_issues":[
   {"id":"QI-001","module_id":"MOD-001","status":"open","metric":"complexity",
    "file":"legacy/auth/session","function":"Validate","value":34,"severity":"HIGH"},
   {"id":"QI-002","module_id":"MOD-001","status":"open","metric":"file_length",
    "file":"legacy/auth/session","function":null,"value":1420,"severity":"HIGH"},
   {"id":"QI-003","module_id":"MOD-002","status":"open","metric":"duplication",
    "file":null,"function":null,"value":22.5,"severity":"HIGH"},
   {"id":"QI-004","module_id":"MOD-003","status":"open","metric":"complexity",
    "file":"legacy/reports/monthly","function":"Build","value":13,"severity":"WARN"},
   {"id":"QI-009","module_id":"MOD-001","status":"resolved","metric":"complexity",
    "file":"legacy/auth/old","function":"Gone","value":null,"severity":null}]}
QJ
}

qr_render()  { ( cd "$1" && bash "$REBUILD_BIN" render .specclaw ./draft.md ) >/dev/null 2>&1; }
qr_refresh() { : > "$1/empty-draft.md"; ( cd "$1" && bash "$REBUILD_BIN" render .specclaw ./empty-draft.md ) >/dev/null 2>&1; }
qr_backlog() { printf '%s' "$1/.specclaw/analysis/rebuild-backlog.md"; }
qr_block()   { awk -v id="$2" '$0 ~ ("^### " id " ") {f=1;next} f && /^### / {exit} f' "$1"; }
qr_section() { awk '/^## Backlog/{f=1} /^## Sequencing Rationale/{f=0} f' "$1"; }

# Append a note block to one item, exactly where a human would: under its own
# Status-notes heading, after the last bash-written field of that item.
qr_add_note() {
  local f="$1" id="$2" anchor="$3" note="$4"
  awk -v id="$id" -v anchor="$anchor" -v note="$note" '
    $0 ~ ("^### " id " ") { inblock = 1 }
    { print }
    inblock && index($0, anchor) == 1 {
      print ""
      print "**Status notes (human-added):**"
      print note
      inblock = 0
    }
  ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

# ── 13a — optionality: no quality.json, no remediation anything ──────────────
# The byte-for-byte half of this guarantee is Case 7's diff; this half asserts
# that nothing the new mechanism emits leaks into a project that never measured.
QRA="$WORK/qr-a"; qr_project "$QRA"; qr_render "$QRA"
# Every HTML comment in the rendered file comes from the template verbatim and
# is present whether or not quality.json exists — the template documents the
# mechanism, which is what makes QUALITY-MEASURED discoverable at all. What must
# be untouched is the GENERATED content, so that is what this strips down to.
qra_out="$(awk '/^<!--/{c=1} c{ if (/-->/) c=0; next } {print}' "$(qr_backlog "$QRA")")"
if [[ "$qra_out" == *"QUALITY-REMEDIATION"* || "$qra_out" == *"QUALITY-MEASURED"* || "$qra_out" == *"Quality state"* || "$qra_out" == *"quality"* ]]; then
  fail "13a with no quality.json nothing generated mentions quality at all"
else
  pass "13a with no quality.json nothing generated mentions quality at all"
fi
assert_eq "13a2 and no item beyond the three drafted ones exists" "3" \
  "$(grep -cE '^### BL-[0-9]{3} ' "$(qr_backlog "$QRA")")"

# ── 13b — two HIGH modules get one item each; the WARN module gets none ──────
QRB="$WORK/qr-b"; qr_project "$QRB"; qr_quality_json "$QRB"; qr_render "$QRB"
QRB_OUT="$(qr_backlog "$QRB")"
assert_eq "13b exactly two remediation items are generated" "2" \
  "$(grep -c '^\*\*Item type:\*\* QUALITY-REMEDIATION' "$QRB_OUT")"
assert_eq "13b2 they take the next free ids, in module order" "BL-004 BL-005" \
  "$(grep -B4 '^\*\*Item type:\*\* QUALITY-REMEDIATION' "$QRB_OUT" | grep -oE 'BL-[0-9]{3}' | paste -sd' ' -)"
assert_contains "13b3 the MOD-001 item lists both of its HIGH hotspots" \
  "- QI-001 — complexity, legacy/auth/session::Validate, measured 34, HIGH" \
  "$(qr_block "$QRB_OUT" BL-004)"
assert_contains "13b4 a file-level hotspot keeps its own empty function field" \
  "- QI-002 — file_length, legacy/auth/session, measured 1420, HIGH" \
  "$(qr_block "$QRB_OUT" BL-004)"
assert_contains "13b5 a module-wide hotspot says so rather than naming a file" \
  "- QI-003 — duplication, module-wide, measured 22.5, HIGH" \
  "$(qr_block "$QRB_OUT" BL-005)"
if qr_block "$QRB_OUT" BL-004 | grep -q 'QI-009'; then
  fail "13b6 a resolved hotspot is never listed as something to remediate"
else
  pass "13b6 a resolved hotspot is never listed as something to remediate"
fi
# MOD-003's WARN hotspot: an advisory count on its rollup line, and no item.
assert_contains "13b7 the WARN-only module gets an advisory count, not an item" \
  "1 advisory QI below the HIGH remediation floor (no item generated)" \
  "$(grep -E '^- \*\*MOD-003 — ' "$QRB_OUT")"
if grep -A6 '^### BL-00[45] ' "$QRB_OUT" | grep -q 'MOD-003'; then
  fail "13b8 no remediation item is generated for the WARN-only module"
else
  pass "13b8 no remediation item is generated for the WARN-only module"
fi
# The new Verification value, and the item's own third axis.
assert_contains "13b9 the item's Verification is the new QUALITY-MEASURED channel" \
  "**Verification:** QUALITY-MEASURED" "$(qr_block "$QRB_OUT" BL-004)"
if qr_block "$QRB_OUT" BL-004 | grep -q 'NO BASELINE DATA'; then
  fail "13b10 a remediation item never reports NO BASELINE DATA"
else
  pass "13b10 a remediation item never reports NO BASELINE DATA"
fi
# PD-04, asserted on a RENDERED item and not only on the template: the
# acceptance criterion is a measurement of the target, never an instruction to
# go and change the legacy implementation.
qrb_body="$(qr_block "$QRB_OUT" BL-004)"
if printf '%s' "$qrb_body" | grep -qiE 'refactor|clean up|rewrite (the )?legacy|fix the legacy'; then
  fail "13b11 the item never asks anyone to change the legacy implementation"
else
  pass "13b11 the item never asks anyone to change the legacy implementation"
fi
assert_contains "13b12 and states the measured criterion in the target's terms" \
  "the REBUILT MOD-001 measures within the configured thresholds" "$qrb_body"

# ── 13c — idempotency: two consecutive refreshes are identical ───────────────
# Compared refresh-to-refresh rather than render-to-refresh: the first run also
# merges the agent's draft, which is a different operation from re-deriving an
# existing document, and conflating the two would test the wrong thing.
QRC="$WORK/qr-c"; qr_project "$QRC"; qr_quality_json "$QRC"
qr_render "$QRC"; qr_refresh "$QRC"
qrc_one_4="$(qr_block "$(qr_backlog "$QRC")" BL-004)"
qrc_one_5="$(qr_block "$(qr_backlog "$QRC")" BL-005)"
qrc_one="$(qr_section "$(qr_backlog "$QRC")")"
qr_refresh "$QRC"
qrc_two_4="$(qr_block "$(qr_backlog "$QRC")" BL-004)"
qrc_two_5="$(qr_block "$(qr_backlog "$QRC")" BL-005)"
qrc_two="$(qr_section "$(qr_backlog "$QRC")")"

# THE CLAIM UNDER TEST is that a remediation item is a pure function of
# quality.json: same hotspots in, byte-identical item out, no second item, no
# new ledger line, no renumbering. Asserted on the items themselves rather than
# on the whole section, because the section carries a pre-existing whitespace
# drift that has nothing to do with this mechanism (see 13c4).
if [[ -n "$qrc_one_4" && "$qrc_one_4" == "$qrc_two_4" && "$qrc_one_5" == "$qrc_two_5" ]]; then
  pass "13c an unchanged quality.json regenerates both remediation items byte-identically"
else
  fail "13c an unchanged quality.json regenerates both remediation items byte-identically ($(diff <(printf '%s' "$qrc_one_4") <(printf '%s' "$qrc_two_4") | head -c 300))"
fi
assert_eq "13c2 and the remediation ids are unchanged across both runs" "BL-004 BL-005" \
  "$(grep -B4 '^\*\*Item type:\*\* QUALITY-REMEDIATION' "$(qr_backlog "$QRC")" | grep -oE 'BL-[0-9]{3}' | paste -sd' ' -)"

# The rest of the Backlog section is unchanged too, once runs of blank lines are
# collapsed — no item appears, disappears, or changes a field.
if [[ "$(printf '%s' "$qrc_one" | cat -s)" == "$(printf '%s' "$qrc_two" | cat -s)" ]]; then
  pass "13c3 and nothing else in the Backlog section changes"
else
  fail "13c3 and nothing else in the Backlog section changes ($(diff <(printf '%s' "$qrc_one" | cat -s) <(printf '%s' "$qrc_two" | cat -s) | head -c 300))"
fi

# 13c4 DOCUMENTS A PRE-EXISTING DEFECT, deliberately, rather than leaving it to
# be rediscovered as a mystery diff. Every refresh adds one blank line under each
# PRESERVED item's heading: render writes "heading, blank, body", the next run's
# EXIST_STATIC parse keeps that blank as the body's first line, and the run after
# that prepends another. It is unbounded, it predates this change (the collector
# on main does it identically, with and without quality.json), and it is left
# alone here because fixing it rewrites the whitespace of every existing
# project's backlog — a behavioural change that deserves its own decision rather
# than a ride-along on this one.
#
# Remediation items are IMMUNE, which is what 13c above asserts: their bodies are
# regenerated from quality.json every run and never parsed back out of the
# document, so there is nothing for a stray blank line to accumulate in.
qrc_pre_blanks="$(qr_block "$(qr_backlog "$QRC")" BL-001 | sed -n '1,4p' | grep -c '^$')"
qrc_rem_blanks="$(qr_block "$(qr_backlog "$QRC")" BL-004 | sed -n '1,4p' | grep -c '^$')"
if [[ "$qrc_pre_blanks" -gt "$qrc_rem_blanks" ]]; then
  pass "13c4 (documents a pre-existing defect) preserved items accumulate a blank line per refresh; regenerated remediation items do not"
else
  fail "13c4 (documents a pre-existing defect) expected preserved-item blank drift to exceed the remediation item's (got $qrc_pre_blanks vs $qrc_rem_blanks)"
fi

# ── 13d — a newly measured hotspot APPENDS to the module's existing item ─────
QRD="$WORK/qr-d"; qr_project "$QRD"; qr_quality_json "$QRD"
qr_render "$QRD"; qr_refresh "$QRD"
jq '.quality_issues += [{"id":"QI-011","module_id":"MOD-001","status":"open",
     "metric":"function_length","file":"legacy/auth/session","function":"Renew",
     "value":260,"severity":"HIGH"}]' \
  "$QRD/.specclaw/analysis/quality.json" > "$QRD/q.tmp" \
  && mv "$QRD/q.tmp" "$QRD/.specclaw/analysis/quality.json"
qr_refresh "$QRD"
QRD_OUT="$(qr_backlog "$QRD")"
assert_eq "13d the re-measured run creates no second item for the module" "2" \
  "$(grep -c '^\*\*Item type:\*\* QUALITY-REMEDIATION' "$QRD_OUT")"
assert_eq "13d2 and renumbers nothing" "BL-004 BL-005" \
  "$(grep -B4 '^\*\*Item type:\*\* QUALITY-REMEDIATION' "$QRD_OUT" | grep -oE 'BL-[0-9]{3}' | paste -sd' ' -)"
assert_contains "13d3 the new hotspot is listed on the existing item" \
  "- QI-011 — function_length, legacy/auth/session::Renew, measured 260, HIGH" \
  "$(qr_block "$QRD_OUT" BL-004)"
assert_contains "13d4 and the addition is recorded, dated" \
  "⊕ **Added $(date +%Y-%m-%d):** QI-011" "$(qr_block "$QRD_OUT" BL-004)"

# ── 13e — gating on the declared BUILT: signal ───────────────────────────────
QRE="$WORK/qr-e"; qr_project "$QRE"; qr_quality_json "$QRE"; qr_render "$QRE"
QRE_OUT="$(qr_backlog "$QRE")"
assert_contains "13e with no BUILT: note the remediation item is BLOCKED" \
  "**Gate:** BLOCKED — quality: awaiting functional items" "$(qr_block "$QRE_OUT" BL-004)"
assert_contains "13e2 and its Quality state says there is nothing to measure yet" \
  "**Quality state:** BLOCKED" "$(qr_block "$QRE_OUT" BL-004)"
qr_add_note "$QRE_OUT" BL-001 "**Verification:**" "- BUILT: PR #12, merged 2026-08-30"
qr_refresh "$QRE"
assert_contains "13e3 once every functional item is BUILT the gate goes CLEAR" \
  "**Gate:** CLEAR" "$(qr_block "$QRE_OUT" BL-004)"

# ── 13f — completion is computed from the delta, never asserted ──────────────
# Same project, now gate-clear, so the state below reflects the measurement and
# nothing else.
cat > "$QRE/.specclaw/analysis/quality-delta.json" <<'QD'
{"schema_version":1,"generated_at":"2026-09-01T10:00:00Z",
 "deltas":[
   {"module_id":"MOD-001","metric":"complexity","legacy_status":"HIGH","target_status":"PASS","classification":"improved"},
   {"module_id":"MOD-001","metric":"function_length","legacy_status":"PASS","target_status":"PASS","classification":"unchanged"},
   {"module_id":"MOD-001","metric":"duplication","legacy_status":"PASS","target_status":"PASS","classification":"unchanged"},
   {"module_id":"MOD-001","metric":"file_length","legacy_status":"HIGH","target_status":"WARN","classification":"improved"}]}
QD
qr_refresh "$QRE"
assert_contains "13f a delta within thresholds with no regression computes DONE" \
  "**Quality state:** DONE" "$(qr_block "$QRE_OUT" BL-004)"
assert_contains "13f2 and cites the delta it was computed from" \
  "2026-09-01T10:00:00Z" "$(qr_block "$QRE_OUT" BL-004)"
# A regressing delta reopens it and names the metric that failed.
jq '.deltas |= map(if .metric == "file_length"
      then .target_status = "HIGH" | .classification = "regressed" else . end)' \
  "$QRE/.specclaw/analysis/quality-delta.json" > "$QRE/d.tmp" \
  && mv "$QRE/d.tmp" "$QRE/.specclaw/analysis/quality-delta.json"
qr_refresh "$QRE"
qre_state="$(qr_block "$QRE_OUT" BL-004 | grep '^\*\*Quality state:\*\*')"
assert_contains "13f3 a regressing delta leaves the item open" "**Quality state:** OPEN" "$qre_state"
assert_contains "13f4 and names the failing metric" "file_length regressed to HIGH" "$qre_state"

# ── 13g — bf-replay refuses a remediation item cleanly ───────────────────────
mkdir -p "$QRE/.specclaw/baseline/fixtures"
cat > "$QRE/.specclaw/baseline/manifest.json" <<'MJ'
{"manifest_schema":3,"fixtures":[
  {"scenario_id":"GM-001","business_rules_pinned":"DR-001","verifies_backlog_item":"BL-001",
   "module_ids":["MOD-001"],"legacy_commit_sha":"abc1234"}]}
MJ
qrg_err="$(bash "$REPLAY_BIN" resolve "$QRE/.specclaw" BL-004 "$QRE/sel.json" 2>&1 >/dev/null)"
qrg_exit=$?
assert_eq "13g the refusal exits 1, the same as every other non-applicable --item scope" "1" "$qrg_exit"
assert_contains "13g2 it names the item type" "is a QUALITY-REMEDIATION item" "$qrg_err"
assert_contains "13g3 it points at the command that DOES verify it" \
  "/specclaw:bf-quality --compare" "$qrg_err"
if [[ "$qrg_err" == *"NO BASELINE DATA"* ]]; then
  fail "13g4 the refusal never reports NO BASELINE DATA"
else
  pass "13g4 the refusal never reports NO BASELINE DATA"
fi
if [[ -e "$QRE/sel.json" ]]; then
  fail "13g5 nothing was created on disk"
else
  pass "13g5 nothing was created on disk"
fi
# THE CONTROL, and the reason it asserts on the error rather than on a
# selection: this fixture's manifest is deliberately a stub, so BL-001 stops at
# the baseline-integrity check further down. That is exactly the point — it got
# PAST the item-kind switch, which a remediation item never does. Asserting the
# guard is narrow means asserting it fires for one item and not the other, not
# that the other one completes a full replay.
qrg_ok_err="$(bash "$REPLAY_BIN" resolve "$QRE/.specclaw" BL-001 "$QRE/sel-ok.json" 2>&1 >/dev/null)"
if [[ "$qrg_ok_err" == *"QUALITY-REMEDIATION"* ]]; then
  fail "13g6 the guard is narrow — it does not fire on an ordinary item"
else
  pass "13g6 the guard is narrow — it does not fire on an ordinary item"
fi
assert_contains "13g7 and that item reaches the join the guard skips" \
  "Baseline check failed" "$qrg_ok_err"

# ── 13h — a human status note on a remediation item survives verbatim ────────
QRH="$WORK/qr-h"; qr_project "$QRH"; qr_quality_json "$QRH"; qr_render "$QRH"
QRH_OUT="$(qr_backlog "$QRH")"
qr_add_note "$QRH_OUT" BL-004 "**Quality state:**" \
  "- Agreed with Dana 2026-08-31: the session validator is being split, not ported."
qr_refresh "$QRH"
assert_contains "13h a status note on a remediation item survives a refresh verbatim" \
  "- Agreed with Dana 2026-08-31: the session validator is being split, not ported." \
  "$(qr_block "$QRH_OUT" BL-004)"
assert_eq "13h2 and is not duplicated by the regeneration" "1" \
  "$(qr_block "$QRH_OUT" BL-004 | grep -c 'Agreed with Dana')"

# ── 13i — the severity floor is config, and lowering it changes the outcome ──
QRI="$WORK/qr-i"; qr_project "$QRI"; qr_quality_json "$QRI"
cat > "$QRI/.specclaw/config.yaml" <<'CY'
project:
  name: QR

quality:
  register_severity: WARN
  remediation_severity_floor: WARN
CY
qr_render "$QRI"
QRI_OUT="$(qr_backlog "$QRI")"
assert_eq "13i lowering the floor to WARN gives the WARN-only module an item too" "3" \
  "$(grep -c '^\*\*Item type:\*\* QUALITY-REMEDIATION' "$QRI_OUT")"
assert_contains "13i2 and that item lists the WARN hotspot" \
  "- QI-004 — complexity, legacy/reports/monthly::Build, measured 13, WARN" \
  "$(qr_block "$QRI_OUT" BL-006)"
if grep -qE '^- \*\*MOD-003 — .*advisory QI below' "$QRI_OUT"; then
  fail "13i3 nothing is below the floor any more, so no advisory count is printed"
else
  pass "13i3 nothing is below the floor any more, so no advisory count is printed"
fi

# ── 13j — module-status reports an open remediation item per module ──────────
( cd "$QRB" && bash "$REBUILD_BIN" module-status .specclaw ) >/dev/null 2>&1
QRB_MS="$QRB/.specclaw/analysis/module-status.md"
assert_contains "13j module-status carries a Quality remediation column" \
  "| Quality remediation |" "$(grep -m1 '^| Module |' "$QRB_MS")"
assert_contains "13j2 a module with an open item is visibly not done" \
  "| ⚠ BLOCKED |" "$(grep -m1 '^| MOD-001 |' "$QRB_MS")"
assert_contains "13j3 a module with no such item reads as having none, not as passing" \
  "| — |" "$(grep -m1 '^| MOD-003 |' "$QRB_MS")"
assert_contains "13j4 and the notes say what an open item means" \
  "A module with an open quality remediation item is not a done module" \
  "$(cat "$QRB_MS")"

# ── Result ───────────────────────────────────────────────────────────────────

echo
echo "======================================"
echo "  passed: $PASS"
echo "  failed: $FAIL"
echo "======================================"
[[ "$FAIL" -eq 0 ]] || exit 1

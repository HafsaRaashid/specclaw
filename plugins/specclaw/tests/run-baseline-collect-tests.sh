#!/usr/bin/env bash
# run-baseline-collect-tests.sh — regression suite for `specclaw-bf-baseline`'s
# module-map co-ownership reciprocity, in BOTH places it is computed: `collect`
# (module_map.modules[].rules, fed to bf-baseline-designer) and `record`'s
# fallback module derivation (MOD_RULES, used only when a scenario's own
# `Modules:` field is left blank). A `DR-###` rule co-owned by two modules
# must land in BOTH modules' rule sets in either path, even though the
# analyst's convention only requires ONE side to write the annotation.
#
# THE REGRESSION: each rule set used to be computed by grepping a module's OWN
# split-out MOD-###.md text for `DR-###` tokens. A co-owned rule annotated on
# only one module's line (the documented, minimum-required form — see
# agents/bf-domain-analyst.md) never appeared in the OTHER module's own file
# text, so that module's rule set silently omitted it. Downstream,
# bf-baseline-designer derives each scenario's `Modules:` tag from collect's
# index (agents/bf-baseline-designer.md:19,67), so the missing module never
# got tagged onto the fixture and `/specclaw:bf-replay --module` could sign
# that module off clean without ever replaying the rule it implements. The
# fix is one shared pair of functions (coowned_pairs / apply_coowned_rules)
# used by both collect and record, so this suite pins both call sites.
#
# Needs jq (collect's own output is validated through it here).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BASELINE_BIN="$PLUGIN_ROOT/bin/specclaw-bf-baseline"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ $# -gt 1 ] && echo "         $2"; }

assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  case "$haystack" in *"$needle"*) ok "$label" ;;
    *) bad "$label" "missing [$needle]" ;; esac
}
assert_not_contains() {
  local haystack="$1" needle="$2" label="$3"
  case "$haystack" in *"$needle"*) bad "$label" "unexpectedly found [$needle]" ;;
    *) ok "$label" ;; esac
}

if ! command -v jq >/dev/null 2>&1; then
  echo "run-baseline-collect-tests.sh: jq not installed — skipping"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

new_project() { # <root>
  rm -rf "$1"; mkdir -p "$1/.specclaw/analysis"
  printf '# Domain Model\n' > "$1/.specclaw/analysis/domain-model.md"
}

rules_of() { # <collect-json> <mod-id>
  printf '%s' "$1" | jq -r --arg m "$2" '.module_map.modules[] | select(.mod_id == $m) | .rules | sort | join(",")'
}

echo "=================================================="
echo "specclaw-bf-baseline collect — co-ownership reciprocity"
echo "=================================================="

# ── 1. THE REGRESSION: a one-sided annotation still reaches both modules ────
echo
echo "-- reciprocity: annotated on one side only --"

R="$WORK/basic"; new_project "$R"
cat > "$R/.specclaw/analysis/module-map.md" <<'EOF'
# Module Map

**Status:** CONFIRMED by H, 2026-08-07

### MOD-001 — Foo
- **Business rules:** DR-001, DR-003 (co-owned with MOD-002: dedup check)
- **Depends on:** None

### MOD-002 — Bar
- **Business rules:** DR-005
- **Depends on:** None
EOF
OUT="$(bash "$BASELINE_BIN" collect "$R/.specclaw" 2>&1)"
assert_contains "$(rules_of "$OUT" "MOD-001")" "DR-003" \
  "the annotating module keeps the rule it wrote (grepped from its own file, unaffected by the fix)"
assert_contains "$(rules_of "$OUT" "MOD-002")" "DR-003" \
  "the named co-owner gets the rule too, though its own section never repeats the id"
assert_not_contains "$(rules_of "$OUT" "MOD-002")" "DR-001" \
  "and picks up ONLY the rule it was named on — not MOD-001's other, unrelated rule"

# ── 2. Each annotation pairs with the NEAREST DR-### to its LEFT ────────────
echo
echo "-- pairing: nearest id on the same line, not a leftmost/whole-line match --"

R="$WORK/nearest"; new_project "$R"
cat > "$R/.specclaw/analysis/module-map.md" <<'EOF'
# Module Map

**Status:** CONFIRMED by H, 2026-08-07

### MOD-001 — Foo
- **Business rules:** DR-001 (co-owned with MOD-002), DR-002 (co-owned with MOD-003)
- **Depends on:** None

### MOD-002 — Bar
- **Business rules:** DR-005
- **Depends on:** None

### MOD-003 — Baz
- **Business rules:** DR-006
- **Depends on:** None
EOF
OUT="$(bash "$BASELINE_BIN" collect "$R/.specclaw" 2>&1)"
assert_contains "$(rules_of "$OUT" "MOD-002")" "DR-001" \
  "the first annotation pairs with DR-001, its nearest id, not DR-002"
assert_not_contains "$(rules_of "$OUT" "MOD-002")" "DR-002" \
  "and does not also pick up the second rule on the same line"
assert_contains "$(rules_of "$OUT" "MOD-003")" "DR-002" \
  "the second annotation pairs with DR-002, its own nearest id"
assert_not_contains "$(rules_of "$OUT" "MOD-003")" "DR-001" \
  "and does not pick up the first rule on the same line"

# ── 3. A rule already listed on both sides is not duplicated ────────────────
echo
echo "-- no duplicate when both sides already repeat the id --"

R="$WORK/dedup"; new_project "$R"
cat > "$R/.specclaw/analysis/module-map.md" <<'EOF'
# Module Map

**Status:** CONFIRMED by H, 2026-08-07

### MOD-001 — Foo
- **Business rules:** DR-003 (co-owned with MOD-002: dedup check)
- **Depends on:** None

### MOD-002 — Bar
- **Business rules:** DR-003 (co-owned with MOD-001: dedup check), DR-005
- **Depends on:** None
EOF
OUT="$(bash "$BASELINE_BIN" collect "$R/.specclaw" 2>&1)"
MOD2_DR003_COUNT="$(printf '%s' "$OUT" | jq -r '.module_map.modules[] | select(.mod_id == "MOD-002") | [.rules[] | select(. == "DR-003")] | length')"
if [ "$MOD2_DR003_COUNT" = "1" ]; then
  ok "a rule already listed on both sides appears exactly once, not twice"
else
  bad "a rule already listed on both sides appears exactly once, not twice" "got ${MOD2_DR003_COUNT} occurrences"
fi

# ── 4. THE SECOND REGRESSION: record's own fallback derivation ──────────────
#
# A scenario that declares no `Modules:` field at all falls back to `record`
# deriving it from the module map itself (MOD_RULES) — a second, independent
# implementation of the same per-module grep, and the one this suite's
# earlier sections do NOT exercise (they only call `collect`). Fixed by the
# same shared coowned_pairs/apply_coowned_rules pair, so it must show the
# same reciprocity.
echo
echo "-- record's fallback module derivation (no Modules: field declared) --"

R="$WORK/record-fallback"; new_project "$R"
mkdir -p "$R/.specclaw/baseline/fixtures"
cat > "$R/.specclaw/analysis/module-map.md" <<'EOF'
# Module Map

**Status:** CONFIRMED by H, 2026-08-07

### MOD-001 — Foo
- **Business rules:** DR-001, DR-003 (co-owned with MOD-002: dedup check)
- **Depends on:** None

### MOD-002 — Bar
- **Business rules:** DR-005
- **Depends on:** None
EOF
cat > "$R/.specclaw/baseline/scenarios.md" <<'EOF'
### GM-001 — dedup check, no Modules field declared

- **Seam:** Svc.Do
- **Seam layer:** service
- **Business rules pinned:** DR-003
- **Verifies backlog item:** not yet backlog-linked
EOF
cat > "$R/.specclaw/baseline/fixtures/GM-001.json" <<'EOF'
{"scenario_id":"GM-001","captured_at":"2026-08-07T10:15:00Z","anchor_date":"2026-08-07",
 "legacy_commit_sha":"abc","runtime_version":"1","normalized_fields":[],
 "input":{},"output":{"outcome":"OK","error_code":null,"threw":false,"result":{"x":1}}}
EOF
bash "$BASELINE_BIN" record "$R/.specclaw" >/dev/null 2>&1
MOD_IDS="$(jq -rc '.fixtures[0].module_ids' "$R/.specclaw/baseline/manifest.json")"
assert_contains "$MOD_IDS" "MOD-001" \
  "the annotating module is still derived (unaffected by the fix)"
assert_contains "$MOD_IDS" "MOD-002" \
  "and the named co-owner is now derived too, though the scenario names no Modules: field at all"

echo
echo "=================================================="
echo "Passed: $PASS   Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0

#!/usr/bin/env bash
# run-bf-status-tests.sh — regression suite for specclaw-bf-status, the
# read-only per-phase dashboard for the brownfield workstream.
#
# What this suite protects, and why each one is here:
#
#   - IT WRITES NOTHING. The whole justification for this command not being
#     archived like every other .specclaw/ document is that it produces no
#     artifact at all. A future edit that starts caching its output would
#     quietly acquire a staleness problem this design does not have, so the
#     no-write property is asserted directly against the file tree.
#
#   - A PHASE IS "not run" ONLY FROM ITS OWN ARTIFACT. Never inferred from a
#     sibling document that happens to mention it.
#
#   - THE REPLAY ROW REPORTS LATEST-PER-TARGET, NOT LATEST OVERALL. This is
#     the defect the suite exists for: with a plain newest-run read, a change
#     whose own most recent verdict is FAIL disappears behind an unrelated
#     module that passed a day later. The dashboard would then render DONE
#     over an outstanding failure, which is the one thing a status view must
#     never do.
#
#   - STUB TAINT IS NEVER A FALSE POSITIVE. A clean verdict must never be
#     reported as resting on a placeholder. Asserted for both a tainted and an
#     untainted run. (The CRLF hazard behind this is documented at the
#     assertion itself, along with what that check does and does not prove.)
#
#   - AN ANSWER ON THE LINE BELOW ITS TAG IS AN ANSWER. specclaw-bf-clarify's
#     own block_answer_text reads multi-line answers, so counting them as
#     unanswered here would manufacture blocking questions that do not exist.
#
#   - MISSING OPTIONAL TOOLING DEGRADES, NEVER FAILS. A dashboard that exits
#     non-zero because jq is absent is worse than one that renders honestly
#     with less detail.
#
# Bash + coreutils. jq is exercised where present and deliberately hidden for
# the degradation test.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATUS_BIN="$PLUGIN_ROOT/bin/specclaw-bf-status"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ $# -gt 1 ] && echo "         $2"; }

assert_eq() {
  local expected="$1" actual="$2" label="$3"
  if [ "$expected" = "$actual" ]; then ok "$label"
  else bad "$label" "expected [$expected], got [$actual]"; fi
}
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

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ── Fixtures ─────────────────────────────────────────────────────────────────

# A bare initialized project: .specclaw/ exists, no brownfield artifact does.
new_empty() {
  local root="$1"
  rm -rf "$root"; mkdir -p "$root/.specclaw/analysis"
  printf 'project:\n  name: "Fixture"\n' > "$root/.specclaw/config.yaml"
}

# The five analysis documents, so phases downstream of them are reachable.
seed_analysis() {
  local root="$1" map_status="${2:-PROPOSED}"
  mkdir -p "$root/.specclaw/analysis"
  local f
  for f in codebase-report architecture domain-model functional-spec; do
    printf '**Date generated:** 2026-08-01\n' > "$root/.specclaw/analysis/$f.md"
  done
  cat > "$root/.specclaw/analysis/module-map.md" <<EOF
# Module Map

**Status:** ${map_status}

### MOD-001 — Core
- **Depends on:** None

### MOD-002 — Reporting
- **Depends on:** MOD-001

### MOD-003 — WITHDRAWN — folded into MOD-001
- **Depends on:** None
EOF
}

# One retained replay run, in whichever evidence pool the caller names.
seed_run() { # <root> <pool-relative-dir> <run_id> <target> <verdict> <date> <tainted:true|false>
  local root="$1" pool="$2" run_id="$3" target="$4" verdict="$5" date="$6" taint="$7"
  local d="$root/.specclaw/$pool/run-$run_id"
  mkdir -p "$d"
  cat > "$d/run-metadata.json" <<EOF
{
  "run_id": "${run_id}",
  "target": "${target}",
  "module": null,
  "date": "${date}",
  "overall_verdict": "${verdict}",
  "stub_tainted": ${taint},
  "bl_items_covered": []
}
EOF
}

run_status() { bash "$STATUS_BIN" "$1/.specclaw" 2>&1; }

echo "=================================================="
echo "specclaw-bf-status regression suite"
echo "=================================================="

# ── 1. The no-write invariant ────────────────────────────────────────────────
echo
echo "-- writes nothing --"

R="$WORK/nowrite"; new_empty "$R"; seed_analysis "$R"
seed_run "$R" "replay/evidence" "20260820-101500" "MOD-001" "PASS" "2026-08-20" "false"
BEFORE="$(find "$R/.specclaw" | LC_ALL=C sort | cksum)"
BEFORE_CONTENT="$(find "$R/.specclaw" -type f -exec cat {} + | cksum)"
run_status "$R" >/dev/null
AFTER="$(find "$R/.specclaw" | LC_ALL=C sort | cksum)"
AFTER_CONTENT="$(find "$R/.specclaw" -type f -exec cat {} + | cksum)"
assert_eq "$BEFORE" "$AFTER" "creates and removes no file"
assert_eq "$BEFORE_CONTENT" "$AFTER_CONTENT" "modifies no existing file"

# ── 2. Absence is reported as absence ────────────────────────────────────────
echo
echo "-- a phase is 'not run' only from its own artifact --"

R="$WORK/empty"; new_empty "$R"
OUT="$(run_status "$R")"; RC=$?
assert_eq "0" "$RC" "an untouched project is not an error"
assert_contains "$OUT" "codebase-report.md not written" "bf-analyze reads as not run"
assert_contains "$OUT" "Run \`/specclaw:bf-analyze\`" "and is recommended as the next command"

# A backlog naming a module map does NOT make the map exist.
R="$WORK/noinfer"; new_empty "$R"
printf '### BL-001 — Thing\n- **Module:** MOD-001\n' > "$R/.specclaw/analysis/rebuild-backlog.md"
OUT="$(run_status "$R")"
assert_contains "$OUT" "missing: domain-model.md functional-spec.md module-map.md" \
  "a backlog citing MOD-001 never implies bf-domain has run"

# ── 3. The module-map confirmation gate ──────────────────────────────────────
echo
echo "-- module map confirmation --"

R="$WORK/proposed"; new_empty "$R"; seed_analysis "$R" "PROPOSED"
OUT="$(run_status "$R")"
assert_contains "$OUT" "Module map is not confirmed" "PROPOSED raises an attention item"
assert_contains "$OUT" "2 module(s)" "WITHDRAWN modules are excluded from the count"

R="$WORK/confirmed"; new_empty "$R"; seed_analysis "$R" "CONFIRMED by Hafsa, 2026-08-07"
OUT="$(run_status "$R")"
assert_not_contains "$OUT" "Module map is not confirmed" "CONFIRMED raises nothing"

# ── 4. Answered-vs-unanswered, including multi-line answers ──────────────────
echo
echo "-- clarification counting --"

R="$WORK/clarify"; new_empty "$R"; seed_analysis "$R" "CONFIRMED by H, 2026-08-07"
cat > "$R/.specclaw/analysis/clarifications.md" <<'EOF'
# Clarifications

## Standard bank

### SQ-001 — Answered inline, blocking
- **Blocking:** yes — the stack
- **Answer:** .NET 9
- **Decided by:** H, 2026-08-05

### SQ-014 — Unanswered, blocking
- **Blocking:** yes — every fixture
- **Answer:**
- **Decided by:**

## Extracted questions

### CQ-001 — Answered on the NEXT line, blocking
- **Blocking:** yes — MOD-002
- **Answer:**
  Preserve the legacy behaviour.
- **Decided by:** H, 2026-08-06

### CQ-002 — Unanswered, NOT blocking
- **Blocking:** no
- **Answer:**
- **Decided by:**
EOF
cat > "$R/.specclaw/analysis/pending-questions.md" <<'EOF'
# Pending Questions

### PQ-001 — Open one
- **Status:** OPEN

### PQ-002 — Already promoted
- **Status:** PROMOTED → CQ-002

### PQ-003 — Another open one
- **Status:** OPEN
EOF
OUT="$(run_status "$R")"
assert_contains "$OUT" "4 question(s), 2 unanswered (1 blocking)" \
  "a multi-line answer counts as answered, and only blocking gaps are called blocking"
assert_contains "$OUT" "PQ buffer: 2 OPEN" "PROMOTED entries are not open work"

# ── 5. Backlog item states ───────────────────────────────────────────────────
echo
echo "-- backlog counting --"

R="$WORK/backlog"; new_empty "$R"; seed_analysis "$R" "CONFIRMED by H, 2026-08-07"
cat > "$R/.specclaw/analysis/rebuild-backlog.md" <<'EOF'
# Rebuild Backlog

### BL-001 — Active and verifiable
**Gate:** CLEAR
**Verification:** VERIFIABLE — fixtures: GM-001

### BL-002 — Active, pending capture
**Gate:** CLEAR
**Verification:** PENDING CAPTURE — scenarios designed, no recorded fixture yet: GM-002

### BL-003 — Deferred
**Status:** Deferred — awaiting CQ-002
**Gate:** BLOCKED — blocked by BL-001
**Verification:** PENDING CAPTURE — scenarios designed, no recorded fixture yet: GM-003

### BL-004 — STRUCK — superseded by BL-001
EOF
OUT="$(run_status "$R")"
assert_contains "$OUT" "2 active item(s) (2 gate CLEAR, 1 VERIFIABLE); 1 struck, 1 deferred" \
  "struck and deferred items are counted apart from active ones"

# ── 6. THE REGRESSION: latest per target, not latest overall ─────────────────
echo
echo "-- replay: latest PER TARGET --"

R="$WORK/replay"; new_empty "$R"; seed_analysis "$R" "CONFIRMED by H, 2026-08-07"
# An older FAIL on one target, a newer PASS on a DIFFERENT target. Reading only
# the newest run would render this DONE and lose the FAIL entirely.
seed_run "$R" "changes/trial-balance/replay-evidence" "20260818-090000" "trial-balance" "FAIL" "2026-08-18" "false"
seed_run "$R" "replay/evidence"                      "20260820-101500" "MOD-001"       "PASS" "2026-08-20" "false"
OUT="$(run_status "$R")"
if command -v jq >/dev/null 2>&1; then
  assert_contains "$OUT" "2 run(s) over 2 target(s)" "both targets are counted"
  assert_contains "$OUT" "latest per target: 1 PASS, 1 not" "the newer PASS does not absorb the older FAIL"
  assert_contains "$OUT" "Replay target **trial-balance**" "the failing target is named, not just counted"
  assert_contains "$OUT" "is **FAIL** (2026-08-18)" "with its own verdict and date"
  # And the row must not read DONE while a target is outstanding.
  ROW="$(printf '%s\n' "$OUT" | grep 'Replay acceptance' || true)"
  assert_contains "$ROW" "ATTN" "the row reads ATTN, never DONE, while a target's latest run failed"

  # Two runs on the SAME target: the newer one does supersede.
  R2="$WORK/replay-same"; new_empty "$R2"; seed_analysis "$R2" "CONFIRMED by H, 2026-08-07"
  seed_run "$R2" "replay/evidence" "20260818-090000" "MOD-001" "FAIL" "2026-08-18" "false"
  seed_run "$R2" "replay/evidence" "20260820-101500" "MOD-001" "PASS" "2026-08-20" "false"
  OUT2="$(run_status "$R2")"
  assert_contains "$OUT2" "2 run(s) over 1 target(s)" "same-target runs collapse to one target"
  assert_contains "$OUT2" "latest per target: 1 PASS, 0 not" "a re-run on the same target supersedes its own earlier verdict"
  assert_not_contains "$OUT2" "is **FAIL**" "the superseded FAIL is not resurfaced"
else
  echo "  (skipped — jq not installed)"
fi

# ── 7. Stub taint is never a false positive ──────────────────────────────────
echo
echo "-- stub taint --"

if command -v jq >/dev/null 2>&1; then
  R="$WORK/clean"; new_empty "$R"; seed_analysis "$R" "CONFIRMED by H, 2026-08-07"
  seed_run "$R" "replay/evidence" "20260820-101500" "MOD-001" "PASS" "2026-08-20" "false"
  OUT="$(run_status "$R")"
  assert_not_contains "$OUT" "dependency-bypass stub" \
    "an untainted run is never reported as resting on a stub (the CRLF trap)"

  R="$WORK/tainted"; new_empty "$R"; seed_analysis "$R" "CONFIRMED by H, 2026-08-07"
  seed_run "$R" "replay/evidence" "20260820-101500" "MOD-001" "PASS" "2026-08-20" "true"
  OUT="$(run_status "$R")"
  assert_contains "$OUT" "dependency-bypass stub" "a tainted run is reported"
  assert_contains "$OUT" '`PASS*`' "and its verdict is marked, never presented as a bare PASS"

  # A PROPERTY CHECK, NOT A PROOF OF THE GUARD — stated plainly because the
  # difference matters to whoever edits this next.
  #
  # A native Windows jq writes CRLF, and the stray \r lands in the LAST field
  # it printed — which for the replay TSV is the stub-taint flag, so an
  # untainted run would come back carrying "\r", read as non-empty, and be
  # accused of resting on a placeholder. Two things stop that: the literal
  # "-" sentinel (an empty trailing TSV field is also indistinguishable from a
  # truncated line, so this one is worth having regardless of platform), and
  # `| tr -d '\r'` inside jqr.
  #
  # Neither is currently mutation-detectable: bash's own command substitution
  # strips a trailing CR along with the newline, so on every platform tested
  # the CR is gone before either guard sees it. Removing them both still
  # passes. They stay as cheap insurance — matching the same discipline
  # specclaw-bf-rebuild-collect already applies to its metadata reads — and
  # this asserts the property they exist to preserve, so a future refactor
  # that reads jq output some other way (a temp file, a process substitution,
  # a `read -r` loop) is caught here rather than in a user's dashboard.
  R="$WORK/nocr"; new_empty "$R"; seed_analysis "$R" "CONFIRMED by H, 2026-08-07"
  mkdir -p "$R/.specclaw/bootstrap"
  printf '{"not_applicable":null,"foundation_ready":true,"stack":{"api":"Go"}}\n' \
    > "$R/.specclaw/bootstrap/bootstrap-manifest.json"
  seed_run "$R" "replay/evidence" "20260820-101500" "MOD-001" "PASS" "2026-08-20" "false"
  CR_COUNT="$(run_status "$R" | tr -dc '\r' | wc -c | tr -d '[:space:]')"
  assert_eq "0" "$CR_COUNT" "no carriage return reaches the output from any jq read"
else
  echo "  (skipped — jq not installed)"
fi

# ── 8. Degradation without jq ────────────────────────────────────────────────
echo
echo "-- degrades without jq, never fails --"

R="$WORK/nojq"; new_empty "$R"; seed_analysis "$R" "CONFIRMED by H, 2026-08-07"
mkdir -p "$R/.specclaw/baseline" "$R/.specclaw/bootstrap"
printf '# Seams\n'  > "$R/.specclaw/baseline/seams.md"
printf '{"total_scenarios":1,"fixtures":[],"missing_scenarios":["GM-001"]}\n' > "$R/.specclaw/baseline/manifest.json"
printf '{"not_applicable":null,"foundation_ready":true,"stack":{"api":"Go"}}\n' > "$R/.specclaw/bootstrap/bootstrap-manifest.json"
seed_run "$R" "replay/evidence" "20260820-101500" "MOD-001" "PASS" "2026-08-20" "false"

# An empty PATH entry ahead of the real one is not enough — hide jq by
# stripping whichever directory it actually resolves from (on most Linux
# distros, including GitHub Actions runners, that IS /usr/bin — so a fixed
# "/usr/bin:/bin" allowlist does not hide it there).
JQ_DIR="$(command -v jq >/dev/null 2>&1 && dirname "$(command -v jq)" || true)"
NOJQ_PATH="$(printf '%s' "$PATH" | tr ':' '\n' | grep -vFx "$JQ_DIR" | paste -sd: -)"
NOJQ_OUT="$(env PATH="$NOJQ_PATH" bash "$STATUS_BIN" "$R/.specclaw" 2>&1)"; NOJQ_RC=$?
if env PATH="$NOJQ_PATH" bash -c 'command -v jq' >/dev/null 2>&1; then
  echo "  (skipped — jq is on the restricted PATH too, cannot simulate its absence)"
else
  assert_eq "0" "$NOJQ_RC" "exits 0 with no jq"
  assert_contains "$NOJQ_OUT" "jq\` is not on PATH" "and says so on its own face"
  assert_contains "$NOJQ_OUT" "install jq" "pointing at what would sharpen the detail"
  assert_contains "$NOJQ_OUT" "2 module(s)" "every markdown-derived count stays exact"
fi

# ── 9. Argument handling ─────────────────────────────────────────────────────
echo
echo "-- argument handling --"

OUT="$(bash "$STATUS_BIN" --help 2>&1)"; RC=$?
assert_eq "0" "$RC" "--help exits 0"
assert_contains "$OUT" "Usage: specclaw-bf-status" "and prints usage"

OUT="$(bash "$STATUS_BIN" 2>&1)"; RC=$?
assert_eq "2" "$RC" "a missing argument exits 2"
assert_contains "$OUT" "<specclaw_dir> is required" "naming what is missing"

OUT="$(bash "$STATUS_BIN" "$WORK/does-not-exist" 2>&1)"; RC=$?
assert_eq "2" "$RC" "a missing .specclaw dir exits 2"
assert_contains "$OUT" "/specclaw:init" "pointing at the command that creates it"

echo
echo "=================================================="
echo "Passed: $PASS   Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0

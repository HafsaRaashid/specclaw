#!/usr/bin/env bash
# run-parser-tests.sh — regression suite for specclaw's bin parsers.
#
# Locks in the recently fixed behaviors:
#   B2: validate-change task counting ignores ``` fenced blocks and only
#       counts backtick-wrapped `T<n>` ids.
#   B3: verify collect parses ACs as AC1 / AC-1, with/without `- [ ]`,
#       with/without **bold**.
#   B4: verify collect parses `Files:` lines that begin with a `  - ` bullet.
# Plus NFR2: existing in-repo change docs still parse (no regression).
#
# Plain bash only — no bats/npm. Run from anywhere:
#   bash plugins/specclaw/tests/run-parser-tests.sh
# Exits non-zero if any case fails.

set -uo pipefail

# --- Resolve own dir and locate ../bin ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
BIN_DIR="$(cd "$SCRIPT_DIR/../bin" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

PARSE_TASKS="$BIN_DIR/specclaw-parse-tasks"
VALIDATE_CHANGE="$BIN_DIR/specclaw-validate-change"
VERIFY="$BIN_DIR/specclaw-verify"

for b in "$PARSE_TASKS" "$VALIDATE_CHANGE" "$VERIFY"; do
  if [[ ! -x "$b" && ! -f "$b" ]]; then
    echo "FATAL: missing bin script: $b" >&2
    exit 2
  fi
done

# --- mktemp workspace with a real .specclaw-like layout (changes/<name>/) ---
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# assert_eq <label> <expected> <actual>
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label (= '$actual')"
  else
    fail "$label (expected '$expected', got '$actual')"
  fi
}

# Build a change dir under the temp workspace and echo its specclaw_dir.
# Usage: make_change <change_name> [spec_fixture] [tasks_fixture]
make_change() {
  local name="$1" spec="${2:-}" tasks="${3:-}"
  local cdir="$WORK/changes/$name"
  mkdir -p "$cdir"
  [[ -n "$spec" ]] && cp "$FIXTURES_DIR/$spec" "$cdir/spec.md"
  [[ -n "$tasks" ]] && cp "$FIXTURES_DIR/$tasks" "$cdir/tasks.md"
  echo "$cdir"
}

echo "=== specclaw bin parser regression suite ==="
echo "bin:      $BIN_DIR"
echo "fixtures: $FIXTURES_DIR"
echo

# ─────────────────────────────────────────────────────────────────────────────
# Case 1 — parse-tasks finds exactly the real T-tasks (template Legend +
# fenced `T<n>` placeholder are not numeric ids, so they are not picked up).
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Case 1: parse-tasks finds exactly the real T-tasks ---"
c1="$(make_change c1-tasks "" tasks.md)"
ids="$("$PARSE_TASKS" "$c1/tasks.md" | jq -r '[.[].id] | sort | join(",")')"
assert_eq "parse-tasks task ids" "T1,T2,T3" "$ids"
# Statuses round-trip correctly for the three markers.
st="$("$PARSE_TASKS" "$c1/tasks.md" | jq -r '[.[] | .status] | join(",")')"
assert_eq "parse-tasks statuses (x,space,~)" "complete,pending,in_progress" "$st"
# --validate exits 0 on well-formed output.
if "$PARSE_TASKS" --validate "$c1/tasks.md" >/dev/null 2>&1; then
  pass "parse-tasks --validate exits 0"
else
  fail "parse-tasks --validate exits 0"
fi
echo

# ─────────────────────────────────────────────────────────────────────────────
# Case 2 — B2: validate-change `status` counts only real backtick T-ids,
# excluding the fenced block (numeric `T9`/`T8` examples) and bare legend lines.
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Case 2 (B2): validate-change status excludes fence + legend ---"
c2="$(make_change b2-fence "" tasks-fenced-id.md)"
line="$("$VALIDATE_CHANGE" "$WORK" b2-fence status | grep -o 'tasks.md ([0-9]*/[0-9]* complete)')"
# Real tasks: T1 [x], T2 [ ] -> 1 complete of 2 total. Fenced T9/T8 ignored.
assert_eq "B2 status line" "tasks.md (1/2 complete)" "$line"

# Same fixture against the c1 tasks (which has 3 real tasks, 1 complete) to
# confirm counting tracks the real markers and not the fenced placeholder.
line1="$("$VALIDATE_CHANGE" "$WORK" c1-tasks status | grep -o 'tasks.md ([0-9]*/[0-9]* complete)')"
assert_eq "B2 status line (case-1 tasks)" "tasks.md (1/3 complete)" "$line1"
echo

# ─────────────────────────────────────────────────────────────────────────────
# Case 3 — B3: verify collect parses all three AC formats.
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Case 3 (B3): verify collect parses mixed AC formats ---"
c3="$(make_change b3-ac spec.md tasks.md)"
ac_count="$("$VERIFY" collect "$WORK" b3-ac 2>/dev/null | jq '.acceptance_criteria | length')"
assert_eq "AC count" "3" "$ac_count"
# Each AC line is non-empty and the AC ids are all represented.
ac_join="$("$VERIFY" collect "$WORK" b3-ac 2>/dev/null | jq -r '.acceptance_criteria | join("\n")')"
for needle in "AC-1" "AC2" "AC-3"; do
  if grep -q "$needle" <<<"$ac_join"; then
    pass "AC contains $needle"
  else
    fail "AC contains $needle"
  fi
done
empty_acs="$("$VERIFY" collect "$WORK" b3-ac 2>/dev/null | jq '[.acceptance_criteria[] | select(. == "")] | length')"
assert_eq "no empty AC entries" "0" "$empty_acs"
echo

# ─────────────────────────────────────────────────────────────────────────────
# Case 4 — B4: verify collect parses `  - Files:` bullet lines.
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Case 4 (B4): verify collect parses bulleted Files: lines ---"
# Reuse the b3-ac change (its tasks.md has `  - Files:` bullets with backticks).
paths="$("$VERIFY" collect "$WORK" b3-ac 2>/dev/null | jq -r '[.changed_files[].path] | sort | join(",")')"
assert_eq "changed_files paths" "src/a.ts,src/b.ts,src/c.ts,src/d.ts" "$paths"
echo

# ─────────────────────────────────────────────────────────────────────────────
# Case 5 — NFR2: existing in-repo change still parses (no regression).
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Case 5 (NFR2): real in-repo change still parses ---"
REAL_SPECCLAW="$REPO_ROOT/.specclaw"
REAL_CHANGE="build-engine"
if [[ ! -f "$REAL_SPECCLAW/changes/$REAL_CHANGE/spec.md" ]]; then
  # Fallback: pick any change that has both spec.md and tasks.md.
  for d in "$REAL_SPECCLAW"/changes/*/; do
    if [[ -f "$d/spec.md" && -f "$d/tasks.md" ]]; then
      REAL_CHANGE="$(basename "$d")"
      break
    fi
  done
fi

if [[ -f "$REAL_SPECCLAW/changes/$REAL_CHANGE/spec.md" && -f "$REAL_SPECCLAW/changes/$REAL_CHANGE/tasks.md" ]]; then
  echo "    using real change: $REAL_CHANGE"
  real_ids="$("$PARSE_TASKS" "$REAL_SPECCLAW/changes/$REAL_CHANGE/tasks.md" | jq 'length')"
  if [[ "$real_ids" -gt 0 ]]; then
    pass "NFR2 parse-tasks found $real_ids tasks in $REAL_CHANGE"
  else
    fail "NFR2 parse-tasks found 0 tasks in $REAL_CHANGE"
  fi
  real_acs="$("$VERIFY" collect "$REAL_SPECCLAW" "$REAL_CHANGE" 2>/dev/null | jq '.acceptance_criteria | length')"
  if [[ "$real_acs" -gt 0 ]]; then
    pass "NFR2 verify collect found $real_acs ACs in $REAL_CHANGE"
  else
    fail "NFR2 verify collect found 0 ACs in $REAL_CHANGE"
  fi
else
  fail "NFR2 could not locate a real change with spec.md + tasks.md under $REAL_SPECCLAW"
fi
echo

# ─────────────────────────────────────────────────────────────────────────────
# Case 6 — grounded-context: specclaw-discover-context ranking, filtering,
# budget, and off-switch (all jq-free; runs in a non-git temp tree, which also
# exercises the find fallback).
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Case 6: discover-context ranking / filtering / budget ---"
DISCOVER="$BIN_DIR/specclaw-discover-context"
if [[ ! -f "$DISCOVER" ]]; then
  fail "discover-context script missing at $DISCOVER"
else
  # Fixture project: copy the static tree, add a .specclaw dir per sub-case.
  DPROJ="$WORK/discovery-proj"
  mkdir -p "$DPROJ/.specclaw"
  cp -R "$FIXTURES_DIR/discovery/." "$DPROJ/"
  printf 'context:\n  discovery: true\n' > "$DPROJ/.specclaw/config.yaml"

  # 6a (AC1/AC2) — ranking: llms.txt-listed guide.md first (tier 1), root
  # canonical CLAUDE/README (tier 2), nested src/README (tier 4).
  paths="$(bash "$DISCOVER" "$DPROJ/.specclaw" list 2>/dev/null | cut -f3 | tr '\n' ',')"
  assert_eq "6a ranked order" "docs/guide.md,CLAUDE.md,README.md,docs/skip.md,src/README.md," "$paths"

  # 6b (AC2) — missing llms.txt entry warns but does not fail.
  if bash "$DISCOVER" "$DPROJ/.specclaw" list 2>&1 >/dev/null | grep -q "docs/nope.md"; then
    pass "6b llms.txt missing entry warned"
  else
    fail "6b llms.txt missing entry warned"
  fi

  # 6c (AC3) — defaults exclude CHANGELOG.md and archive/.
  listed="$(bash "$DISCOVER" "$DPROJ/.specclaw" list 2>/dev/null | cut -f3)"
  if grep -q "CHANGELOG.md" <<<"$listed" || grep -q "archive/old.md" <<<"$listed"; then
    fail "6c default exclusions (CHANGELOG/archive leaked)"
  else
    pass "6c default exclusions"
  fi

  # 6d (AC4) — precedence: folders includes docs/, exclude still beats it;
  # root-relative pattern excludes root README.
  printf 'context:\n  discovery: true\n  folders:\n    - "docs"\n  exclude:\n    - "docs/skip.md"\n' > "$DPROJ/.specclaw/config.yaml"
  paths="$(bash "$DISCOVER" "$DPROJ/.specclaw" list 2>/dev/null | cut -f3 | tr '\n' ',')"
  assert_eq "6d exclude beats folders" "docs/guide.md," "$paths"
  printf 'context:\n  discovery: true\n  exclude:\n    - "./README.md"\n    - "src"\n' > "$DPROJ/.specclaw/config.yaml"
  paths="$(bash "$DISCOVER" "$DPROJ/.specclaw" list 2>/dev/null | cut -f3 | tr '\n' ',')"
  assert_eq "6d root-relative + segment excludes" "docs/guide.md,CLAUDE.md,docs/skip.md," "$paths"

  # 6e (AC5) — budget: emit stays within budget and names every casualty.
  printf 'context:\n  discovery: true\n' > "$DPROJ/.specclaw/config.yaml"
  out="$(bash "$DISCOVER" "$DPROJ/.specclaw" emit --budget 4 2>/dev/null)"
  if grep -q '^<!-- dropped (over 4-line budget):' <<<"$out"; then
    pass "6e budget footer present"
  else
    fail "6e budget footer present"
  fi
  # Budget 4: guide.md (2) + CLAUDE.md (2) fit exactly; the rest must be
  # named as dropped. " README.md" (leading space) avoids matching src/README.md.
  for casualty in " README.md" "docs/skip.md" "src/README.md"; do
    if grep "^<!-- dropped" <<<"$out" | grep -q "$casualty"; then
      pass "6e names dropped:$casualty"
    else
      fail "6e names dropped:$casualty"
    fi
  done

  # 6f (AC6) — discovery off: zero output, exit 0.
  printf 'context:\n  discovery: false\n' > "$DPROJ/.specclaw/config.yaml"
  out="$(bash "$DISCOVER" "$DPROJ/.specclaw" emit 2>/dev/null)"; rc=$?
  if [[ -z "$out" && "$rc" -eq 0 ]]; then
    pass "6f discovery off = empty output, exit 0"
  else
    fail "6f discovery off = empty output, exit 0 (rc=$rc, ${#out} bytes)"
  fi

  # 6g — git enumeration path: run against the real repo, expect README.md
  # (tier 2) present and .specclaw/ absent.
  real_list="$(bash "$DISCOVER" "$REPO_ROOT/.specclaw" list 2>/dev/null | cut -f3)"
  if grep -qx "README.md" <<<"$real_list" && ! grep -q "^\.specclaw/" <<<"$real_list"; then
    pass "6g git-tree enumeration on real repo"
  else
    fail "6g git-tree enumeration on real repo"
  fi
fi
echo

# ─────────────────────────────────────────────────────────────────────────────
# Case 8 — update-check: compare logic, gate, fail-silence, cache (all offline).
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Case 8: update-check compare / gate / silence / cache ---"
CHECK_BIN="$BIN_DIR/specclaw-check-update"
UPROJ="$WORK/update-proj/.specclaw"
mkdir -p "$UPROJ"
printf 'version: 1\n' > "$UPROJ/config.yaml"

if [[ ! -f "$CHECK_BIN" ]]; then
  fail "specclaw-check-update missing"
else
  local_ver="$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$BIN_DIR/../.claude-plugin/plugin.json" | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"

  # 8a (AC1) — newer remote → exactly one line with both versions + update hint
  out="$(bash "$CHECK_BIN" "$UPROJ" --remote-version 99.0.0)"
  if [[ "$(wc -l <<<"$out")" == "1" ]] && grep -q "99.0.0" <<<"$out" && grep -q "$local_ver" <<<"$out" && grep -q "/plugin update specclaw" <<<"$out"; then
    pass "8a newer remote notifies"
  else
    fail "8a newer remote notifies (got: $out)"
  fi

  # 8b (AC2) — equal and older remote → silent, exit 0
  out_eq="$(bash "$CHECK_BIN" "$UPROJ" --remote-version "$local_ver")"; rc_eq=$?
  out_old="$(bash "$CHECK_BIN" "$UPROJ" --remote-version 0.0.1)"; rc_old=$?
  if [[ -z "$out_eq" && -z "$out_old" && "$rc_eq" -eq 0 && "$rc_old" -eq 0 ]]; then
    pass "8b equal/older silent"
  else
    fail "8b equal/older silent"
  fi

  # 8c (AC3) — gate beats hook: update_check false + newer remote → silent
  printf 'version: 1\nplugin:\n  update_check: false\n' > "$UPROJ/config.yaml"
  out="$(bash "$CHECK_BIN" "$UPROJ" --remote-version 99.0.0)"; rc=$?
  if [[ -z "$out" && "$rc" -eq 0 ]]; then
    pass "8c gate disables check"
  else
    fail "8c gate disables check"
  fi
  printf 'version: 1\n' > "$UPROJ/config.yaml"

  # 8d (AC5) — fresh cache short-circuits network: seed newer cached version,
  # no --remote-version, notification comes from the cache alone
  printf '%s 99.0.0\n' "$(date +%s)" > "$UPROJ/.update-check"
  out="$(bash "$CHECK_BIN" "$UPROJ")"
  if grep -q "99.0.0 available" <<<"$out"; then
    pass "8d cache short-circuit notifies"
  else
    fail "8d cache short-circuit notifies (got: $out)"
  fi

  # 8e (AC5) — corrupt cache ignored (treated stale); with no network result
  # available the check stays silent rather than erroring
  printf 'garbage-not-epoch 99.0.0\n' > "$UPROJ/.update-check"
  out="$(bash "$CHECK_BIN" "$UPROJ" --remote-version 0.0.1)"; rc=$?
  if [[ -z "$out" && "$rc" -eq 0 ]]; then
    pass "8e corrupt cache ignored"
  else
    fail "8e corrupt cache ignored"
  fi
  rm -f "$UPROJ/.update-check"

  # 8f (AC4) — unreachable repo host: silent exit 0 (fail-silent network path).
  # Copy the script beside a fake manifest so repo derivation hits a dead host.
  FAKEBIN="$WORK/fake-plugin/bin"
  mkdir -p "$FAKEBIN" "$WORK/fake-plugin/.claude-plugin"
  cp "$CHECK_BIN" "$FAKEBIN/"
  printf '{ "name": "specclaw", "version": "0.0.1", "repository": "https://invalid.invalid/nobody/nothing" }\n' > "$WORK/fake-plugin/.claude-plugin/plugin.json"
  out="$(bash "$FAKEBIN/specclaw-check-update" "$UPROJ" --force 2>/dev/null)"; rc=$?
  if [[ -z "$out" && "$rc" -eq 0 ]]; then
    pass "8f unreachable host silent"
  else
    fail "8f unreachable host silent (rc=$rc, out: $out)"
  fi
fi
echo

# ─────────────────────────────────────────────────────────────────────────────
# Case 7 — smart-base-branch: detect_base_branch chain + base-aware setup.
# Local bare origin with default branch 'develop'; jq-free asserts.
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Case 7: base branch detection + base-aware setup ---"
BUILD_BIN="$BIN_DIR/specclaw-build"
GPROJ="$WORK/base-branch-proj"

# Build a bare origin whose default branch is 'develop'
mkdir -p "$WORK/origin-src" && (
  cd "$WORK/origin-src"
  git init -q -b develop .
  git config user.email t@t && git config user.name t
  echo base > base.txt && git add . && git commit -qm base
  echo dev2 > dev2.txt && git add . && git commit -qm dev2
) && git clone -q --bare "$WORK/origin-src" "$WORK/origin.git" && (
  git -C "$WORK/origin.git" symbolic-ref HEAD refs/heads/develop
) && git clone -q "$WORK/origin.git" "$GPROJ" && (
  cd "$GPROJ"
  git config user.email t@t && git config user.name t
  mkdir -p .specclaw/changes/bb-test
  printf 'version: 1\ngit:\n  strategy: "branch-per-change"\n  branch_prefix: "specclaw/"\n' > .specclaw/config.yaml
  printf '# t\n- [ ] `T1` — x\n  - Files: a\n' > .specclaw/changes/bb-test/tasks.md
)

if [[ ! -f "$BUILD_BIN" ]]; then
  fail "specclaw-build missing"
else
  # 7a (AC1) — detection resolves origin/HEAD -> develop; setup JSON reports it
  setup_json="$(cd "$GPROJ" && bash "$BUILD_BIN" setup .specclaw bb-test 2>/dev/null)"
  base_val="$(printf '%s' "$setup_json" | grep -o '"base_branch": "[^"]*"' | sed 's/.*: "//;s/"//')"
  assert_eq "7a detected base (origin/HEAD)" "develop" "$base_val"

  # 7b (AC4) — new change branch starts at origin/develop tip
  tip_origin="$(git -C "$GPROJ" rev-parse origin/develop)"
  tip_branch="$(git -C "$GPROJ" rev-parse specclaw/bb-test)"
  assert_eq "7b branch starts at origin/develop tip" "$tip_origin" "$tip_branch"

  # 7c (AC5) — resume path unchanged (second run warns, same branch)
  resume_out="$(cd "$GPROJ" && bash "$BUILD_BIN" setup .specclaw bb-test 2>&1 >/dev/null)"
  if grep -q "already exists — resuming" <<<"$resume_out"; then
    pass "7c resume warning intact"
  else
    fail "7c resume warning intact"
  fi

  # 7d (AC2) — config override beats origin/HEAD
  (cd "$GPROJ" && git checkout -q develop && git branch -q -D specclaw/bb-test)
  printf 'version: 1\ngit:\n  strategy: "branch-per-change"\n  branch_prefix: "specclaw/"\n  base_branch: "release/1.0"\n' > "$GPROJ/.specclaw/config.yaml"
  (cd "$GPROJ" && git branch -q "release/1.0")
  setup_json="$(cd "$GPROJ" && bash "$BUILD_BIN" setup .specclaw bb-test 2>/dev/null)"
  base_val="$(printf '%s' "$setup_json" | grep -o '"base_branch": "[^"]*"' | sed 's/.*: "//;s/"//')"
  assert_eq "7d config override wins" "release/1.0" "$base_val"

  # 7e (AC3) — no origin remote: falls back to local main/master without error
  NOREMOTE="$WORK/noremote-proj"
  mkdir -p "$NOREMOTE" && (
    cd "$NOREMOTE"
    git init -q -b main .
    git config user.email t@t && git config user.name t
    echo x > x.txt && git add . && git commit -qm x
    mkdir -p .specclaw/changes/nr-test
    printf 'version: 1\ngit:\n  strategy: "branch-per-change"\n  branch_prefix: "specclaw/"\n' > .specclaw/config.yaml
    printf '# t\n- [ ] `T1` — x\n  - Files: a\n' > .specclaw/changes/nr-test/tasks.md
  )
  setup_json="$(cd "$NOREMOTE" && bash "$BUILD_BIN" setup .specclaw nr-test 2>/dev/null)"
  base_val="$(printf '%s' "$setup_json" | grep -o '"base_branch": "[^"]*"' | sed 's/.*: "//;s/"//')"
  assert_eq "7e no-remote fallback" "main" "$base_val"

  # 7f (AC6) — specclaw-pr uses detected base, no hardcoded '--base main'
  if grep -q -- '--base "\$pr_base"' "$BIN_DIR/specclaw-pr" && ! grep -q -- '--base main' "$BIN_DIR/specclaw-pr"; then
    pass "7f pr --base uses detection"
  else
    fail "7f pr --base uses detection"
  fi
fi
echo

# ─────────────────────────────────────────────────────────────────────────────
# Case 9 — analyze-codebase collect: manifest detection (Node/Go/Delphi), the
# single-line `engines.node` version_signal regression, LOC-by-extension,
# test-location detection, path-scoping exclusion, and discovered_docs parity
# with a standalone specclaw-discover-context run (all jq-free; the plain
# fixture copy exercises the `find` fallback, the git-initialized copy
# exercises the `git ls-files` path).
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Case 9: analyze-codebase collect — manifests, LOC, test-locations, docs, scoping ---"
ANALYZE_BIN="$BIN_DIR/specclaw-analyze-codebase"
DISCOVER="$BIN_DIR/specclaw-discover-context"
if [[ ! -f "$ANALYZE_BIN" ]]; then
  fail "specclaw-analyze-codebase missing"
else
  # Plain copy of the fixture tree, no .git anywhere above it -> exercises the
  # `find` fallback enumeration path.
  AFIX="$WORK/analyze-proj"
  mkdir -p "$AFIX/.specclaw"
  cp -R "$FIXTURES_DIR/analyze/." "$AFIX/"
  printf 'context:\n  discovery: true\n' > "$AFIX/.specclaw/config.yaml"

  out="$(bash "$ANALYZE_BIN" collect "$AFIX/.specclaw" 2>/dev/null)"

  # 9a (AC1) — output is a well-formed JSON object: balanced braces, starts
  # with `{`/ends with `}`, and every documented top-level field is present.
  # (jq is not installed in this environment, so this is the grep/awk
  # fallback equivalent of `jq -e '.'`.)
  open_braces="$(grep -o '{' <<<"$out" | wc -l | tr -d ' ')"
  close_braces="$(grep -o '}' <<<"$out" | wc -l | tr -d ' ')"
  if [[ "${out:0:1}" == "{" && "${out: -1}" == "}" && "$open_braces" == "$close_braces" ]] \
     && grep -q '"path":' <<<"$out" && grep -q '"project_root":' <<<"$out" \
     && grep -q '"top_level_dirs":' <<<"$out" && grep -q '"manifests":' <<<"$out" \
     && grep -q '"loc_by_extension":' <<<"$out" && grep -q '"test_locations":' <<<"$out" \
     && grep -q '"discovered_docs":' <<<"$out"; then
    pass "9a collect output is a well-formed JSON object with all documented fields"
  else
    fail "9a collect output is a well-formed JSON object with all documented fields"
  fi

  # 9b (AC3) — package.json manifest: type=node, both real dependencies, and
  # the single-line `"engines": { "node": ">=18.0.0" },` version_signal
  # correctly captured (this exact single-line style was a real bug found and
  # fixed in the script — regression lock-in).
  node_line="$(grep -o '{"path": "package.json".*}' <<<"$out")"
  if grep -q '"type": "node"' <<<"$node_line" \
     && grep -q '"dependencies": \["express", "lodash"\]' <<<"$node_line" \
     && grep -q '"version_signal": ">=18.0.0"' <<<"$node_line"; then
    pass "9b package.json manifest: type=node, deps, single-line engines.node version_signal"
  else
    fail "9b package.json manifest: type=node, deps, single-line engines.node version_signal (got: $node_line)"
  fi

  # 9c (AC3) — go.mod manifest: type=go, both modules from the require( )
  # block, and the `go 1.21` directive as version_signal.
  go_line="$(grep -o '{"path": "go.mod".*}' <<<"$out")"
  if grep -q '"type": "go"' <<<"$go_line" \
     && grep -q '"dependencies": \["github.com/pkg/errors", "github.com/stretchr/testify"\]' <<<"$go_line" \
     && grep -q '"version_signal": "1.21"' <<<"$go_line"; then
    pass "9c go.mod manifest: type=go, deps from require() block, version_signal"
  else
    fail "9c go.mod manifest: type=go, deps from require() block, version_signal (got: $go_line)"
  fi

  # 9d (AC3, NFR1) — the Delphi .dproj manifest: type=delphi and dependencies
  # extracted from <DCCReference Include="..."> entries. This is the
  # language-agnostic differentiator the feature exists for.
  dproj_line="$(grep -o '{"path": "AnalyzeFixture.dproj".*}' <<<"$out")"
  if grep -q '"type": "delphi"' <<<"$dproj_line" \
     && grep -q '"dependencies": \["AnalyzeFixture.pas", "Unit1.pas"\]' <<<"$dproj_line"; then
    pass "9d .dproj manifest: type=delphi, deps from DCCReference entries"
  else
    fail "9d .dproj manifest: type=delphi, deps from DCCReference entries (got: $dproj_line)"
  fi

  # 9e (AC4) — loc_by_extension matches a hand-computed `wc -l` count for the
  # fixture's known 5-line file (sample.qux, a distinctive extension so the
  # assertion is unambiguous).
  qux_loc="$(grep -o '"qux": [0-9]*' <<<"$out" | grep -o '[0-9]*')"
  hand_count="$(wc -l < "$FIXTURES_DIR/analyze/sample.qux" | tr -d ' ')"
  assert_eq "9e loc_by_extension[qux] matches wc -l" "$hand_count" "$qux_loc"

  # 9f (AC5) — test_locations includes the fixture's tests/ directory.
  if grep -q '"test_locations": \["tests"' <<<"$out"; then
    pass "9f test_locations includes tests/"
  else
    fail "9f test_locations includes tests/ (got: $(grep '"test_locations":' <<<"$out"))"
  fi

  # 9g (AC6) — discovered_docs is identical to what `specclaw-discover-context
  # <dir> emit` produces standalone against the same directory (same script
  # invoked, no reimplementation). Compare by applying the same json_escape
  # transform to the standalone output and diffing against the embedded
  # field, rather than reverse-unescaping — escaping is the one-way step both
  # sides actually perform.
  direct_docs="$(bash "$DISCOVER" "$AFIX/.specclaw" emit 2>/dev/null)"
  json_escape_9g() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
  }
  expected_escaped="$(json_escape_9g "$direct_docs")"
  embedded_escaped="$(grep -o '"discovered_docs": ".*"$' <<<"$out" | sed -E 's/^"discovered_docs": "(.*)"$/\1/')"
  assert_eq "9g discovered_docs identical to standalone discover-context emit" "$expected_escaped" "$embedded_escaped"

  # 9h (AC2) — scoping to sub/ excludes every root-level manifest, and (AC5
  # edge case) test_locations is empty since sub/ has no test-like directory.
  sub_out="$(bash "$ANALYZE_BIN" collect "$AFIX/.specclaw" sub 2>/dev/null)"
  if grep -q '"path": "package.json"' <<<"$sub_out" \
     || grep -q '"path": "go.mod"' <<<"$sub_out" \
     || grep -q '"path": "AnalyzeFixture.dproj"' <<<"$sub_out"; then
    fail "9h sub/ scoping excludes root-level manifests (found one)"
  else
    pass "9h sub/ scoping excludes root-level manifests"
  fi
  sub_test_loc_line="$(grep '"test_locations":' <<<"$sub_out")"
  if grep -q '"tests"' <<<"$sub_test_loc_line"; then
    fail "9i sub/ scoping: test_locations empty (no test-like dir under sub/) (got: $sub_test_loc_line)"
  else
    pass "9i sub/ scoping: test_locations empty (no test-like dir under sub/)"
  fi

  # 9j (AC2) — scoping to tests/ excludes sub/'s file, every root manifest,
  # and the root-level sample.qux LOC entry, while still reporting its own
  # file and test_locations entry.
  tests_out="$(bash "$ANALYZE_BIN" collect "$AFIX/.specclaw" tests 2>/dev/null)"
  if grep -q '"path": "package.json"' <<<"$tests_out" \
     || grep -q 'sub/extra.txt' <<<"$tests_out" \
     || grep -q '"qux"' <<<"$tests_out"; then
    fail "9j tests/ scoping excludes files outside it (root manifests, sub/, sample.qux)"
  else
    pass "9j tests/ scoping excludes files outside it (root manifests, sub/, sample.qux)"
  fi
  if grep -q 'tests/sample.txt' <<<"$tests_out" && grep -q '"test_locations": \["tests"' <<<"$tests_out"; then
    pass "9k tests/ scoping still reports its own file and test_locations entry"
  else
    fail "9k tests/ scoping still reports its own file and test_locations entry"
  fi

  # 9l — same fixture, git-initialized copy: exercises the `git ls-files`
  # enumeration path (the plain, non-git copy above exercises the `find`
  # fallback). Confirms parity on the regression-sensitive facts: node
  # manifest + version_signal, and LOC.
  AFIX_GIT="$WORK/analyze-proj-git"
  mkdir -p "$AFIX_GIT/.specclaw"
  cp -R "$FIXTURES_DIR/analyze/." "$AFIX_GIT/"
  printf 'context:\n  discovery: true\n' > "$AFIX_GIT/.specclaw/config.yaml"
  (
    cd "$AFIX_GIT"
    git init -q .
    git config user.email t@t && git config user.name t
    git add -A && git commit -qm init
  ) >/dev/null 2>&1
  git_out="$(bash "$ANALYZE_BIN" collect "$AFIX_GIT/.specclaw" 2>/dev/null)"
  node_line_git="$(grep -o '{"path": "package.json".*}' <<<"$git_out")"
  qux_loc_git="$(grep -o '"qux": [0-9]*' <<<"$git_out" | grep -o '[0-9]*')"
  if grep -q '"type": "node"' <<<"$node_line_git" \
     && grep -q '"version_signal": ">=18.0.0"' <<<"$node_line_git" \
     && [[ "$qux_loc_git" == "$hand_count" ]]; then
    pass "9l git ls-files enumeration path matches find-fallback facts (node manifest + LOC)"
  else
    fail "9l git ls-files enumeration path matches find-fallback facts (got node_line=$node_line_git qux_loc=$qux_loc_git)"
  fi
fi
echo

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
echo "=================================================="
echo "$PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0

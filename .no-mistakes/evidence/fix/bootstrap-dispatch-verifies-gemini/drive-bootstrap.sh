#!/usr/bin/env bash
# Drives the real bin/fm-bootstrap.sh against scratch FM_HOMEs holding crew-dispatch configs.
# Usage: drive-bootstrap.sh <worktree-root>
set -u
ROOT=$1
SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/fm-gemini-dispatch.XXXXXX")
trap 'rm -rf "$SCRATCH"' EXIT

# Pre-fix product: same bin/ tree, with only fm-bootstrap.sh taken from the base commit.
mkdir -p "$SCRATCH/base"
cp -R "$ROOT/bin" "$SCRATCH/base/bin"
git -C "$ROOT" show 795e5e4aacdf120908224617cfcc4dd1b76e0d37:bin/fm-bootstrap.sh > "$SCRATCH/base/bin/fm-bootstrap.sh"
chmod +x "$SCRATCH/base/bin/fm-bootstrap.sh"

n=0
run_case() { # <label> <bootstrap> <json>
  n=$((n + 1))
  local home="$SCRATCH/home-$n" out rc
  mkdir -p "$home/config"
  printf '%s\n' manual > "$home/config/backlog-backend"
  printf '%s\n' "$3" > "$home/config/crew-dispatch.json"
  out=$(FM_HOME="$home" FM_ROOT_OVERRIDE="$home" FM_BOOTSTRAP_NETWORK=skip FM_BOOTSTRAP_DETECT_ONLY=1 "$2" 2>&1)
  rc=$?
  printf '=== %s\n' "$1"
  printf 'config/crew-dispatch.json: %s\n' "$3"
  printf 'bootstrap exit: %s\n' "$rc"
  printf 'CREW_DISPATCH lines:\n'
  printf '%s\n' "$out" | grep '^CREW_DISPATCH' || printf '  (none)\n'
  printf '\n'
}

FIXED="$ROOT/bin/fm-bootstrap.sh"
BASE="$SCRATCH/base/bin/fm-bootstrap.sh"
INTENT='{"rules":[{"when":"multimodal evidence, long-context document digestion","use":{"harness":"gemini"}}],"default":{"harness":"claude"}}'

run_case "BEFORE fix (base 795e5e4): gemini rule + claude default" "$BASE" "$INTENT"
run_case "AFTER fix (4abb464): gemini rule + claude default" "$FIXED" "$INTENT"
run_case "AFTER fix: gemini as default profile" "$FIXED" '{"rules":[],"default":{"harness":"gemini"}}'
run_case "AFTER fix: gemini inside a quota-balanced pool with claude" "$FIXED" '{"rules":[{"when":"research","select":"quota-balanced","use":[{"harness":"claude"},{"harness":"gemini"}]}],"default":{"harness":"claude"}}'
run_case "AFTER fix: gemini with model and effort (record-and-omit contract, accepted by design)" "$FIXED" '{"rules":[{"when":"video review","use":{"harness":"gemini","model":"gemini-3.8-flash-high","effort":"high"}}],"default":{"harness":"claude"}}'
run_case "ADVERSARIAL: unknown harness is still flagged" "$FIXED" '{"rules":[{"when":"anything","use":{"harness":"spaceship"}}],"default":{"harness":"claude"}}'
run_case "ADVERSARIAL: near-miss names (Gemini, gemini-cli, gemini with space) are still flagged" "$FIXED" '{"rules":[{"when":"a","use":{"harness":"Gemini"}},{"when":"b","use":{"harness":"gemini-cli"}},{"when":"c","use":{"harness":"gemini "}}],"default":{"harness":"claude"}}'
run_case "ADVERSARIAL: gemini alongside an unverified harness reports only the unverified one" "$FIXED" '{"rules":[{"when":"a","use":{"harness":"gemini"}},{"when":"b","use":{"harness":"spaceship"}}],"default":{"harness":"claude"}}'
run_case "ADVERSARIAL: gemini with malformed effort type is still flagged" "$FIXED" '{"rules":[{"when":"a","use":{"harness":"gemini","effort":3}}],"default":{"harness":"claude"}}'
run_case "REGRESSION GUARD: claude invalid effort is still flagged next to a gemini rule" "$FIXED" '{"rules":[{"when":"a","use":{"harness":"gemini"}}],"default":{"harness":"claude","effort":"ultra"}}'

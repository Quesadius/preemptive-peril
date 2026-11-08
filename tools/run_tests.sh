#!/usr/bin/env bash
# run_tests.sh — headless verification gate.
#
# Single source of truth for local hooks and CI. Runs, in order:
#   1. Core purity check
#   2. gdlint on all GDScript
#   3. Parse check on every script
#   4. gdUnit4 test suite, headless
#
# Usage:  ./tools/run_tests.sh [test_subdir]
# Exit 0 = everything green.

set -uo pipefail

GODOT="${GODOT_BIN:-godot}"
TEST_DIR="${1:-res://tests}"
status=0

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
fail() { printf '\033[31mFAIL: %s\033[0m\n' "$1" >&2; status=1; }

if ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "godot not found. Set GODOT_BIN to the Godot 4.7 binary path." >&2
  exit 127
fi

step "Core purity"
if ./tools/check_core_purity.sh; then
  echo "clean"
else
  fail "core/, ai/, or data/ depends on the engine"
fi

step "Lint"
if command -v gdlint >/dev/null 2>&1; then
  # Only lint directories that exist — later-milestone dirs aren't created yet.
  lint_dirs=()
  for d in core ai data presentation ui persistence autoload tests; do
    [[ -d "$d" ]] && lint_dirs+=("$d/")
  done
  if [[ ${#lint_dirs[@]} -eq 0 ]] || gdlint "${lint_dirs[@]}" 2>&1; then
    echo "clean"
  else
    fail "gdlint reported issues"
  fi
else
  echo "gdlint not installed (pip install 'gdtoolkit==4.*') — skipping"
fi

step "Parse check"
parse_failed=0
while IFS= read -r -d '' f; do
  if ! "$GODOT" --headless --path . --check-only --script "$f" >/dev/null 2>&1; then
    echo "  parse error: $f" >&2
    parse_failed=1
  fi
done < <(find core ai data presentation ui persistence autoload tools -name '*.gd' -print0 2>/dev/null)
if [[ $parse_failed -eq 0 ]]; then echo "clean"; else fail "one or more scripts failed to parse"; fi

step "Tests (headless)"
if [[ -d "addons/gdUnit4" ]]; then
  if "$GODOT" --headless --path . \
      -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a "$TEST_DIR" --continue --ignoreHeadlessMode; then
    echo "passed"
  else
    fail "test suite red"
  fi
elif [[ -d "addons/gut" ]]; then
  if "$GODOT" --headless --path . \
      -s addons/gut/gut_cmdln.gd -gdir="$TEST_DIR" -ginclude_subdirs -gexit; then
    echo "passed"
  else
    fail "test suite red"
  fi
else
  fail "no test framework installed — add gdUnit4 or GUT to addons/"
fi

if [[ $status -eq 0 ]]; then
  printf '\n\033[32mAll checks green.\033[0m\n'
else
  printf '\n\033[31mVerification failed.\033[0m\n' >&2
fi
exit $status

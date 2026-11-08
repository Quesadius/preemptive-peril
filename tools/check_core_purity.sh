#!/usr/bin/env bash
# check_core_purity.sh — enforces that core/, ai/, and data/ stay engine-free.
#
# Single source of truth for local hooks and CI, same role as tools/check_coverage.sh
# in the C++ projects.
#
# Usage:
#   ./tools/check_core_purity.sh                          # sweep all pure dirs
#   ./tools/check_core_purity.sh core/rules/movement.gd   # check specific files
#
# Exit 0 = clean, 1 = violation found.

set -uo pipefail

PURE_DIRS=("core" "ai" "data")

# Rules are parallel arrays so regex alternation (|) can't collide with a delimiter.
PATTERNS=()
REASONS=()
TAGS=()

rule() {
  PATTERNS+=("$1")
  REASONS+=("$2")
  TAGS+=("${3:-}")
}

rule '^[[:space:]]*extends[[:space:]]+(Node|Node2D|Node3D|CanvasItem|Control|Sprite2D|TileMapLayer|CharacterBody2D|Area2D)([[:space:]]|$)' \
     'extends a Node type — pure layers may only extend RefCounted or Resource'
rule '\bget_tree[[:space:]]*\(' \
     'references the scene tree'
rule '\bget_node[[:space:]]*\(|\$[A-Za-z_%"]' \
     'references nodes by path'
rule '\bEngine\.' \
     'references the Engine singleton'
rule '\bInput\.' \
     'reads input directly'
rule '\bget_viewport[[:space:]]*\(' \
     'references a viewport'
rule '\b(preload|load)[[:space:]]*\([[:space:]]*"[^"]*\.tscn"' \
     'loads a scene'
rule '^[[:space:]]*signal[[:space:]]+' \
     'declares a signal — core returns events, it does not emit'
rule '^[[:space:]]*@(onready|tool)\b' \
     'uses a Node-only annotation'
rule '\b(queue_free|add_child|remove_child)[[:space:]]*\(' \
     'manipulates the scene tree'
rule '^[[:space:]]*(print|print_rich|printt|prints)[[:space:]]*\(' \
     'prints to stdout — use push_error/push_warning'
rule '\b(randi|randf|randi_range|randf_range|randomize)[[:space:]]*\(' \
     'uses global RNG — route randomness through GameState.rng' 'rng'
rule '\bRandomNumberGenerator\.new[[:space:]]*\(' \
     'constructs an RNG — only deterministic_rng.gd may do this' 'rng'

fail=0

check_file() {
  local file="$1"
  [[ "$file" == *.gd ]] || return 0
  [[ -f "$file" ]] || return 0

  # The one file allowed to construct randomness.
  local allow_rng=0
  [[ "$(basename "$file")" == "deterministic_rng.gd" ]] && allow_rng=1

  local i
  for i in "${!PATTERNS[@]}"; do
    if [[ "${TAGS[$i]}" == "rng" && $allow_rng -eq 1 ]]; then
      continue
    fi

    local lineno line trimmed
    while IFS=: read -r lineno line; do
      [[ -z "$lineno" ]] && continue
      trimmed="${line#"${line%%[![:space:]]*}"}"
      # Skip comment-only lines.
      [[ "$trimmed" == \#* ]] && continue
      printf 'PURITY VIOLATION  %s:%s\n' "$file" "$lineno" >&2
      printf '  %s\n' "${REASONS[$i]}" >&2
      printf '  > %s\n' "$trimmed" >&2
      fail=1
    done < <(grep -nE "${PATTERNS[$i]}" "$file" 2>/dev/null || true)
  done
}

in_pure_dir() {
  local rel="$1" d
  for d in "${PURE_DIRS[@]}"; do
    [[ "$rel" == "$d/"* ]] && return 0
  done
  return 1
}

if [[ $# -gt 0 ]]; then
  # Hook mode: only the paths handed to us, and only those inside a pure dir.
  for f in "$@"; do
    rel="${f#./}"
    rel="${rel#"$PWD/"}"
    if in_pure_dir "$rel"; then
      check_file "$rel"
    fi
  done
else
  # Full mode: sweep everything.
  for d in "${PURE_DIRS[@]}"; do
    [[ -d "$d" ]] || continue
    while IFS= read -r -d '' f; do
      check_file "$f"
    done < <(find "$d" -name '*.gd' -print0)
  done
fi

if [[ $fail -ne 0 ]]; then
  printf '\ncore/, ai/, and data/ must run headless with no scene loaded.\n' >&2
  printf 'Move engine-dependent code to presentation/ instead of weakening this check.\n' >&2
  exit 1
fi

exit 0

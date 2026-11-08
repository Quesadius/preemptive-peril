#!/usr/bin/env bash
# hook_post_edit.sh — PostToolUse hook for Edit|Write.
#
# Reads the Claude Code hook payload on stdin, extracts the edited file,
# formats it with gdformat, and purity-checks it if it lives in a pure directory.
#
# Exit 2 feeds stderr back to Claude so it fixes the violation itself.

set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-$PWD}" || exit 0

INPUT=$(cat)
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[[ -z "$FILE" || ! -f "$FILE" ]] && exit 0
[[ "$FILE" != *.gd ]] && exit 0

# Format in place. Never fatal — a parse error here just means gdformat can't
# read it yet, and the parse check in run_tests.sh will catch that properly.
if command -v gdformat >/dev/null 2>&1; then
  gdformat "$FILE" >/dev/null 2>&1 || true
fi

# Architectural gate.
if ! ./tools/check_core_purity.sh "$FILE" 2>&1; then
  exit 2
fi

exit 0

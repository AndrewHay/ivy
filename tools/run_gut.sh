#!/usr/bin/env bash
# Run GUT headlessly and fail if any test script was skipped due to parse/load errors.
# GUT alone can exit 0 when scripts are ignored (ivy-t3o).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
if [[ ! -x "$GODOT" ]]; then
	echo "Godot not found at: $GODOT (set GODOT=...)" >&2
	exit 127
fi

SUITE="${1:-fast}"
shift || true

case "$SUITE" in
	fast)
		GUT_ARGS=(-gdir=res://test)
		;;
	slow)
		GUT_ARGS=(-gdir=res://test/slow)
		;;
	full)
		GUT_ARGS=(-gdir=res://test -gdir=res://test/slow)
		;;
	*)
		echo "Usage: $0 [fast|slow|full] [extra gut args...]" >&2
		exit 2
		;;
esac

LOG="${GUT_LOG:-}"
if [[ -z "$LOG" ]]; then
	LOG="$(mktemp -t ivy-gut.XXXXXX.log)"
	TEE_LOG=1
else
	TEE_LOG=0
fi

set +e
"$GODOT" --headless --script addons/gut/gut_cmdln.gd "${GUT_ARGS[@]}" -gexit "$@" 2>&1 | tee "$LOG"
GODOT_EXIT=${PIPESTATUS[0]}
set -e

scan_fail=0

if grep -qE 'Ignoring script res://test/' "$LOG"; then
	echo "FAIL: GUT ignored at least one fast/slow test script (usually parse error)." >&2
	grep -E 'Ignoring script res://test/' "$LOG" >&2 || true
	scan_fail=1
fi

if grep -qE 'SCRIPT ERROR: Parse Error:.*\(res://test/' "$LOG"; then
	echo "FAIL: Parse error in a test script." >&2
	grep -E 'SCRIPT ERROR: Parse Error:.*\(res://test/' "$LOG" >&2 || true
	scan_fail=1
fi

if grep -qE 'Failed to load script "res://test/' "$LOG"; then
	echo "FAIL: Godot failed to load a test script." >&2
	grep -E 'Failed to load script "res://test/' "$LOG" >&2 || true
	scan_fail=1
fi

if grep -qF '[ERROR]:  Nothing was run.' "$LOG"; then
	echo "FAIL: GUT ran zero tests." >&2
	scan_fail=1
fi

if [[ "$TEE_LOG" -eq 1 ]]; then
	rm -f "$LOG"
fi

if [[ "$GODOT_EXIT" -ne 0 ]]; then
	exit "$GODOT_EXIT"
fi
if [[ "$scan_fail" -ne 0 ]]; then
	exit 1
fi
exit 0

#!/usr/bin/env bash
# Run GUT headlessly and fail if any test script was skipped due to parse/load errors.
# GUT alone can exit 0 when scripts are ignored (ivy-t3o).
#
# AGENTS: do not invoke this script (it needs extra permissions). Copy the commands
# below and run them directly with working_directory = the project root. Run one
# Godot test process at a time, and never kill Godot processes you did not start.
#
#   # 1. Run GUT, saving the log inside the workspace (pick ONE -gdir / -gtest form):
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://test -gexit > .tmp/gut.log 2>&1; echo "godot exit $?"
#   #    slow:     -gdir=res://test/slow
#   #    full:     -gdir=res://test -gdir=res://test/slow
#   #    one file: -gtest=res://test/test_foo.gd   (instead of -gdir; full res:// path)
#
#   # 2. Show the result summary:
#   tail -40 .tmp/gut.log
#
#   # 3. Check for skipped/broken scripts. Any output here means the run is NOT clean,
#   #    even if GUT printed "All tests passed":
#   grep -E 'Ignoring script res://test/|SCRIPT ERROR: Parse Error:.*\(res://test/|Failed to load script "res://test/|\[ERROR\]:  Nothing was run\.' .tmp/gut.log
#
# The run is clean only if: godot exit is 0, the summary shows no failures, and step 3 prints nothing.
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

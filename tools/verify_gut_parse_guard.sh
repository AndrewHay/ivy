#!/usr/bin/env bash
# Regression check for ivy-t3o: wrapper + inventory must fail when a test script won't parse.
#
# AGENTS: do not invoke this script (it needs extra permissions). Run the steps directly
# from the project root, and always do step 4, even if an earlier step fails:
#
#   # 1. Back up and break the smoke test:
#   cp test/test_gut_smoke.gd .tmp/test_gut_smoke.gd.bak
#   printf '\nfunc @@ivy_t3o_guard_syntax_error(): pass\n' >> test/test_gut_smoke.gd
#   # 2. Run GUT on it:
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://test -gselect=gut -gexit > .tmp/gut_guard.log 2>&1
#   # 3. Expect at least one match (a match means the guard works):
#   grep -E 'Ignoring script res://test/|SCRIPT ERROR: Parse Error:.*\(res://test/|Failed to load script "res://test/' .tmp/gut_guard.log
#   # 4. Restore:
#   mv .tmp/test_gut_smoke.gd.bak test/test_gut_smoke.gd
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TARGET="test/test_gut_smoke.gd"
BACKUP="$(mktemp -t gut-smoke-backup.XXXXXX)"
cp "$TARGET" "$BACKUP"
cleanup() {
	mv "$BACKUP" "$TARGET"
}
trap cleanup EXIT

printf '\nfunc @@ivy_t3o_guard_syntax_error(): pass\n' >>"$TARGET"

set +e
./tools/run_gut.sh fast -gselect=gut 2>&1 | tail -20
WRAPPER_EXIT=$?
set -e

if [[ "$WRAPPER_EXIT" -eq 0 ]]; then
	echo "FAIL: run_gut.sh should exit non-zero when a test script has a parse error." >&2
	exit 1
fi

echo "OK: run_gut.sh detected broken test script (exit $WRAPPER_EXIT)."

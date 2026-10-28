#!/usr/bin/env bash
# Regression check for ivy-t3o: wrapper + inventory must fail when a test script won't parse.
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

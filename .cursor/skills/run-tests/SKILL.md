---
name: run-tests
description: Runs the GUT unit test suite for the ivy Godot project headlessly and interprets the results. Use when asked to run tests, check if tests pass, verify code changes don't break anything, or diagnose test failures.
---

# Run Tests

## Run command

Always run from the project root with `required_permissions: ["all"]` and `working_directory: /Users/andrewhay/github/ivy`:

```bash
pwd && test "$(pwd)" = "/Users/andrewhay/github/ivy" || exit 1
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless \
  --script addons/gut/gut_cmdln.gd \
  -gdir=res://test \
  -gexit 2>&1
```

Set `block_until_ms` to at least `60000` — the suite takes ~5s but Godot startup adds overhead.

## Interpreting results

- Exit code `0` + `---- All tests passed! ----` → clean
- Any `FAILED` lines → report each failing test name and the assertion message
- Script parse errors (see below) → GUT installation is broken, fix first

## Known failure: mixed GUT version

If output contains `Parse Error: Identifier "GutErrorTracker" not declared`, the local `addons/gut/` has been partially overwritten by Godot's plugin updater (it's gitignored and not pinned). Fix:

```bash
curl -L -o /tmp/gut-9.4.0.zip \
  "https://api.github.com/repos/bitwes/Gut/zipball/v9.4.0"
cd /tmp && unzip -q gut-9.4.0.zip
rm -rf /Users/andrewhay/github/ivy/addons/gut
cp -R /tmp/bitwes-Gut-*/addons/gut /Users/andrewhay/github/ivy/addons/gut
```

Then re-run the test command. The version in `addons/gut/utils.gd` should read `'9.4.0'`.

## Project facts

| Item | Value |
|---|---|
| GUT version | 9.4.0 |
| Godot version | 4.4 |
| Test directory | `res://test/` |
| `addons/gut/` | gitignored — local install only |

---
name: run-tests
description: Runs the GUT unit test suite for the ivy Godot project headlessly and interprets the results. Use when asked to run tests, check if tests pass, verify code changes don't break anything, or diagnose test failures.
---

<!-- Generated for Claude Code by semantic-memory from semantic-memory/assets/gamedev/skills/run-tests/SKILL.md.
     Edit the source and re-run the semantic-memory install; local edits
     here are overwritten. -->

# Run Tests

## Never invoke the `tools/*.sh` wrappers

`tools/run_gut.sh` and `tools/verify_gut_parse_guard.sh` need extra shell permissions. Do **not** run them. Each starts with an `AGENTS:` comment block. Copy the commands from that block and run them directly: a direct `/Applications/Godot.app/...` call needs no `required_permissions`. If the block and this skill disagree, the block wins, because it sits next to the checks it replaces.

Always set `working_directory: /Users/andrewhay/github/ivy`. Do not prefix the command with `cd`. Run one Godot test process at a time, and never kill a Godot process you did not start (that includes the user's editor).

## Default (fast) suite

Most pipeline work should use the **fast** suite only. It excludes the mesh-SDF gate tests and the 30-day mesh scenario regression in `res://test/slow/` (tracked as ivy-c7e.2).

```bash
# 1. Run, logging inside the workspace:
/Applications/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://test -gexit > .tmp/gut.log 2>&1; echo "godot exit $?"

# 2. Summary:
tail -40 .tmp/gut.log

# 3. Skipped/broken-script check. Any output means the run is NOT clean:
grep -E 'Ignoring script res://test/|SCRIPT ERROR: Parse Error:.*\(res://test/|Failed to load script "res://test/|\[ERROR\]:  Nothing was run\.' .tmp/gut.log
```

Step 3 is mandatory. GUT can print "All tests passed" and exit 0 even after it skipped a script because of a parse or load error (ivy-t3o). `run_gut.sh` used to perform this check, so a direct run has to repeat it.

To see the failures, run `grep -nE 'FAILED|\[Failed\]' .tmp/gut.log`.

Set `block_until_ms` to at least **`240000`** (4 minutes). Baseline measured 2026-10-28 (ivy-zfg): **72 scripts, 606 tests, ~170 s GUT time** (~175 s wall) on Godot 4.7.2 / main, after grass and leaf gusts landed.

`-gdir=res://test` does **not** recurse into `test/slow/` unless `-ginclude_subdirs` is set.

### Running one script (timing / debug)

`-gtest` takes **full `res://` paths**, and it **adds** scripts rather than filtering `-gdir`. Do **not** combine `-gdir=res://test` with `-gtest=name.gd`: that still runs the whole directory.

```bash
# One file only (then run steps 2 and 3 as above):
/Applications/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gtest=res://test/test_time.gd -gexit > .tmp/gut.log 2>&1; echo "godot exit $?"

# Filename substring filter (still scans -gdir):
/Applications/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://test -gselect=time -gexit > .tmp/gut.log 2>&1; echo "godot exit $?"
```

Per-file wall times for isolated `-gtest=res://…` runs are in `.tmp/gut_per_file_times.txt` after a sweep. Before the ivy-zfg moves, the most expensive fast-suite files were `test_time` (~103 s), `test_village_grass_scatter` (~21 s), `test_village_backdrop` (~19 s) and `test_determinism` (~17 s).

### Hangs after a script error

Headless Godot does not quit when a `--script` hits a runtime error. For one-off probe scripts (not GUT), add `--quit-after <frames>` and call `quit()` on every exit path. Do not wrap the command in perl or `timeout` tricks.

## Parse-guard regression

This confirms that the step 3 check catches a broken test script. Follow the `AGENTS:` block in `tools/verify_gut_parse_guard.sh`:

1. Back up `test/test_gut_smoke.gd`.
2. Append a syntax error to it.
3. Run GUT with `-gselect=gut`, then expect the step 3 `grep` to match.
4. Restore the file. Always do this step, even if an earlier step failed.

## Slow suite (mesh SDF + scenario gates)

Run this before closing work that touches any of:

- `assets/structures/*`, `mesh_sdf.gd`, `surface_query.gd` or `structure_body.gd`
- scenario seeding
- the **`main.tscn` building picker or session teardown**
- the **SG-8 interior light bake** on `surface_wall_sim`

Also run it before M2.6 mesh-gate sign-off. Use the same three steps with `-gdir=res://test/slow`:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://test/slow -gexit > .tmp/gut.log 2>&1; echo "godot exit $?"
```

Set `block_until_ms` to at least **`1200000`** (20 minutes). The suite includes `test_change_building.gd`, `test_sg8_interior_light.gd` and `test_interior_leak.gd` (moved in ivy-zfg), plus mesh SDF, scenario seeding, wall archetypes and more. Re-measure after adding slow scripts. The three moved integration scripts alone take ~110 s wall in one process (2026-10-28).

## Full suite (fast + slow)

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://test -gdir=res://test/slow -gexit > .tmp/gut.log 2>&1; echo "godot exit $?"
```

Set `block_until_ms` to at least **`1200000`** (20 minutes). Running fast and slow separately is faster than one combined process because of SDF memory pressure.

## Interpreting results

The run is clean only when all three hold:

- `godot exit 0`
- `---- All tests passed! ----` in the tail
- the step 3 `grep` prints nothing

Otherwise:

- `FAILED` lines: report each failing test's name and its assertion message.
- `Ignoring script`, `Parse Error` or `Failed to load` on `res://test/`: fix the test script before trusting the run.
- Parse errors inside `addons/gut/` (see below): the GUT installation is broken. Fix it first.

## Known failure: mixed GUT version

If the output contains `Parse Error: Identifier "GutErrorTracker" not declared`, Godot's plugin updater has partially overwritten the local `addons/gut/`. The addon is gitignored and not pinned. To fix it:

```bash
curl -L -o /tmp/gut-9.4.0.zip \
  "https://api.github.com/repos/bitwes/Gut/zipball/v9.4.0"
cd /tmp && unzip -q gut-9.4.0.zip
rm -rf /Users/andrewhay/github/ivy/addons/gut
cp -R /tmp/bitwes-Gut-*/addons/gut /Users/andrewhay/github/ivy/addons/gut
```

Then re-run the test command. The version string in `addons/gut/utils.gd` should read `'9.4.0'`.

## Runtime baseline (2026-10-28, ivy-zfg)

| Suite | GUT time | Tests | Wall (approx.) |
|---|---:|---:|---:|
| Fast `-gdir=res://test` | 170 s | 606 | 175 s |
| Slow `-gdir=res://test/slow` (full dir) | re-measure | — | often 15–20+ min |

**Dominant cost:** anything that boots `main.tscn`, runs a GROW sim over several game days, or calls `LightBake.bake()` belongs in `test/slow/`, or should use a minimal tick horizon (see `SHORT_GROW_GAME_DAYS` in `test_time.gd`, and `test_m6_free_plant.gd`).

## Project facts

| Item | Value |
|---|---|
| GUT version | 9.4.0 |
| Godot version | 4.4+ |
| Fast test directory | `res://test/` (no subdirs) |
| Slow test directory | `res://test/slow/` |
| `addons/gut/` | gitignored, local install only |

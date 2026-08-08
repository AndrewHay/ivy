---
name: run-ui-script
description: Runs a plain-text sequence of UI steps against the running ivy game scene, capturing screenshots at chosen points. Use when verifying multi-step UI/gameplay flows or regression-testing interactive behavior.
---

# Run UI Script

Headlessly launches the main scene, executes a `.txt` verb file, and captures PNGs where requested.

## Run command

Run with `required_permissions: ["all"]` and `working_directory: /Users/andrewhay/github/ivy`:

```bash
pwd && test "$(pwd)" = "/Users/andrewhay/github/ivy" || exit 1
/Applications/Godot.app/Contents/MacOS/Godot \
  res://tools/run_ui_script.tscn \
  -- \
  --script=/Users/andrewhay/github/ivy/tools/ui_scripts/smoke.txt \
  --outdir=/tmp/ivy_ui_script/
```

Set `block_until_ms` to at least `30000`.

After the run, read PNGs from `--outdir` and check the log for `FAILED` steps.

## Instruction file format

Plain `.txt`, one verb per line, `#` comments and blank lines ignored:

```text
WAIT 500
SCREENSHOT boot.png
```

## Verb reference (bootstrap)

| Verb | Effect |
|---|---|
| `WAIT <ms>` | Wait N real-time milliseconds |
| `SCREENSHOT [name.png]` | Capture a PNG into `--outdir` |

Add project-specific verbs (clicks, queue actions, etc.) as gameplay UI is implemented — mirror probot's `run_ui_script.gd` pattern.

## Files involved

- `tools/run_ui_script.gd` — runner script
- `tools/run_ui_script.tscn` — scene hosting the runner
- `tools/ui_scripts/smoke.txt` — canonical smoke test

## Healthy output

```
[ui-script] script=...  outdir=/tmp/ivy_ui_script/  steps=2
[ui-script]   saved /tmp/ivy_ui_script/01_boot.png size=(1920, 1080)
```

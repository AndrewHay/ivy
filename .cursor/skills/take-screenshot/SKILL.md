---
name: take-screenshot
description: Captures a PNG screenshot of the running ivy game scene. Use when verifying UI rendering, debugging visual regressions, capturing a "what does it look like right now" image, or whenever the user asks for a screenshot of the game.
---

# Take Screenshot

Headlessly launches the main scene, lets it settle, and writes a PNG to disk.

## Run command

Run with `required_permissions: ["all"]` and `working_directory: /Users/andrewhay/github/ivy`:

```bash
pwd && test "$(pwd)" = "/Users/andrewhay/github/ivy" || exit 1
/Applications/Godot.app/Contents/MacOS/Godot \
  res://tools/take_screenshot.tscn \
  -- \
  --out=/tmp/ivy.png
```

Set `block_until_ms` to at least `15000`.

After the command finishes, read the resulting PNG to inspect it visually.

## Recognised arguments

| Flag | Purpose | Default |
|------|---------|---------|
| `--out=PATH` | Absolute path for the output PNG | `/tmp/ivy_debug.png` |
| `--settle-frames=N` | Process frames before capture | `30` |

Note the `--` separator: everything after it is forwarded to Godot's `OS.get_cmdline_user_args()`.

## Files involved

- `tools/take_screenshot.gd` — runner script (loads `main.tscn`, captures viewport, quits).
- `tools/take_screenshot.tscn` — bare `Node` scene that hosts the script.

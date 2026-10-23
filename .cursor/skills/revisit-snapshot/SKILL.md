---
name: revisit-snapshot
description: Loads a debug snapshot from .tmp/snapshots/, reads snapshot.json and PNGs, optionally replays the scene and captures replay/orbit images, then reports MATCH/MISMATCH and annotation context. Use when the user says "look at my snapshot", "revisit snapshot", "my last snapshot", or asks an agent to investigate a saved F9 capture.
---

# Revisit Snapshot

Developer-only debug snapshots (ivy-nrp, `IvyParams.dev_build`). Each save is a folder under
`res://.tmp/snapshots/` (gitignored) with `snapshot.json`, `clean.png`, and optionally
`annotated.png`. The file `.tmp/snapshots/latest` holds the newest folder name (one line).

## When to use

Trigger phrases: **"look at my snapshot"**, **"revisit snapshot X"**, **"my last snapshot"**,
**"what did I mark in the snapshot"**, or any question about a saved F9 capture.

## Resolve the folder

1. If the user names a folder or id, use it.
2. Otherwise read `latest`:
   ```bash
   cat /Users/andrewhay/github/ivy/.tmp/snapshots/latest
   ```
3. Absolute path: `/Users/andrewhay/github/ivy/.tmp/snapshots/<folder>/` (or globalise
   `res://.tmp/snapshots/<folder>/`).

## Read-only path (always do first)

1. Open `snapshot.json` — note `scene.building_id`, `time.tick_index`, `note`, `annotations[]`
   (normalised geometry, `comment`, `world_anchors`, `nearby_plant`), and `fingerprint.run_hash`.
2. **Embed in the chat response** (markdown `![]()`):
   - `annotated.png` if present, else `clean.png`
3. Summarise each annotation: id, kind, comment, collider names from anchors, and any
   `nearby_plant` segment/tip references.

**Skip replay** when the user only wants commentary on the image/JSON, or when replay would be
slow and hashes are not in question.

## Replay path (when state must be verified or re-seen in 3D)

macOS cannot capture the game viewport headlessly — replay runs **non-headless**.

```bash
pwd && test "$(pwd)" = "/Users/andrewhay/github/ivy" || exit 1
/Applications/Godot.app/Contents/MacOS/Godot \
  res://tools/replay_snapshot.tscn \
  -- \
  --snapshot=latest
```

Optional orbit shots around annotation **id** `n` (uses `world_anchors` centroid):

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  res://tools/replay_snapshot.tscn \
  -- \
  --snapshot=latest \
  --orbit-highlight=1
```

Writes `replay.png` and `orbit_highlight_<id>_<azimuth>.png` into the snapshot folder.

Set `block_until_ms` to at least **`120000`** (building bootstrap + replay).

After the run:

1. Read stdout for **`[replay-snapshot] MATCH`** or **`MISMATCH`** (compare `run_hash`).
2. Embed **`annotated.png`** (or `clean.png`) and **`replay.png`** side by side in the answer.
3. If orbit PNGs exist, embed the best one beside the annotated frame.
4. Report annotation-linked **segments/tips** from JSON and whether replay geometry aligns with
   the marked regions.

## UI-script alternative

For multi-step inspection after load, use `run-ui-script` with a `.txt` that starts with:

```text
SNAPSHOT_LOAD latest
ORBIT 45 6 2
SCREENSHOT after_orbit.png
```

See `.cursor/skills/run-ui-script/SKILL.md` for `SNAPSHOT_LOAD` and `ORBIT`.

## Files

| Path | Role |
|------|------|
| `src/debug/snapshot_recipe.gd` | Schema v1 JSON |
| `src/debug/snapshot_replay.gd` | Replay + `RunHash` verify |
| `tools/replay_snapshot.gd` | CLI replay + PNG outputs |
| `src/main/main.gd` | `load_snapshot_from_dir`, F9 save |
| `test/test_debug_snapshot.gd` | Mechanical regression tests |

## Save reminders (for the user)

- **F9** — snapshot with highlight tool (`HelpPanel` Developer section when `dev_build`).
- **Shift+F9** — quick save without overlay.

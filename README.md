# Ivy

Godot 4.4 game project with the same Cursor agent pipeline and dev tooling patterns as [probot](https://github.com/AndrewHay/probot-the-game).

## Quick start

1. Open this folder in Cursor (multi-root with probot is fine during early setup).
2. Godot 4.4+ — open `project.godot`.
3. Run tests (see `.cursor/skills/run-tests/SKILL.md`).

## Linux hosts (cloud dev containers)

ivy runs on Linux (tested: Ubuntu 24.04 x86_64, Godot 4.7.2, Blender 4.2.1) as well as macOS.
Skills and docs give the macOS binary paths; on Linux use `$GODOT` and `$BLENDER` instead
(the container's `~/.ivy-env` sets both). Scripts that launch the binaries themselves read
those variables and fall back to the macOS paths.

1. **Set Godot's Blender path before the first import.** ivy has `.blend` files. Without
   `filesystem/import/blender/blender_path` in Godot's editor settings
   (`~/.config/godot/editor_settings-4.7.tres`), a headless `--import` can't ask for it and
   cancels the **whole** batch, yet still exits 0. Set it to the Blender binary, e.g.
   `filesystem/import/blender/blender_path = "/usr/local/bin/blender"`.
2. **Import, then check the import really finished:**
   `"$GODOT" --headless --path . --import`. Then compare the count of
   `.godot/imported` files with the count of `*.import` files outside `.godot/`. The cache
   should have at least as many. A cancelled import leaves only a handful (14 in the first
   Linux run).
3. **Run tests only on a complete import.** GUT on a missing cache doesn't fail fast: every
   glTF load fails, each village backdrop build logs hundreds of errors, and the suite is
   many times slower. The first Linux run printed for about 24 minutes, then stopped printing
   while its memory grew to 10 GB (bead `ivy-8eej`). `test/gut_pre_run.gd` now aborts GUT with
   exit 3 and `[gut-pre-run] ABORT` when more than 10% of imported sources have no cache file.
4. **Screenshots and captures** run non-headless (`--headless` renders nothing) under Xvfb:
   `Xvfb :99 -screen 0 1920x1080x24 &`, then
   `DISPLAY=:99 "$GODOT" --path . --display-driver x11 --rendering-driver vulkan --audio-driver Dummy <scene> -- <user args>`.
   This rendered on the GPU (NVIDIA L4) in the Phase 0 test.
5. **User args go after `--`** and tools read them with `OS.get_cmdline_user_args()`.
   Output paths default to `res://.tmp/...` inside the project, never a home directory.

## Docs

- `DESIGN.md` — game design intent
- `IMPLEMENTATION.md` — system contracts
- `TECHNICAL_INDEX.md` — file index and signal flow
- `PIPELINE.md` — agent stage order
- **Feature queue: `bd` (`bd ready`, `bd show <id>`)** — see `.cursor/rules/beads-kernel.mdc`. `work-items/WORK_ITEMS.md` is a read-only historical archive; new work is not added there.

## Agent workflow

Rules in `.cursor/rules/`, subagents in `.cursor/agents/`, skills in `.cursor/skills/`.

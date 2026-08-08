# Ivy — Technical Index

Last updated: 2026-08-07

> Update this file whenever files are added, removed, renamed, or change responsibility.
> See `.cursor/rules/technical-index-maintenance.mdc`.

---

## File Index

| Path | Summary |
|------|---------|
| `project.godot` | Godot project config; main scene `res://src/main/main.tscn` |
| `src/main/main.tscn` | Root Control scene (bootstrap placeholder UI) |
| `src/main/main.gd` | Sets placeholder title label on ready |
| `test/test_gut_smoke.gd` | GUT smoke tests (infrastructure sanity check) |
| `tools/take_screenshot.gd` | Headless screenshot runner for main scene |
| `tools/take_screenshot.tscn` | Scene hosting the screenshot runner |
| `tools/ui_scripts/smoke.txt` | Minimal UI script smoke test (wait + screenshot) |
| `addons/gut/` | GUT test framework (local install, gitignored) |

---

## Cross-Reference

| System | Primary files |
|--------|----------------|
| Bootstrap UI | `src/main/main.tscn`, `src/main/main.gd` |
| Testing | `test/`, `addons/gut/` |
| Dev tooling | `tools/take_screenshot.*`, `tools/run_ui_script.*` |

---

## Signal Flow Summary

_No gameplay signals yet — add as systems are implemented._

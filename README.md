# Ivy

Godot 4.4 game project with the same Cursor agent pipeline and dev tooling patterns as [probot](https://github.com/AndrewHay/probot-the-game).

## Quick start

1. Open this folder in Cursor (multi-root with probot is fine during early setup).
2. Godot 4.4+ — open `project.godot`.
3. Run tests (see `.cursor/skills/run-tests/SKILL.md`).

## Docs

- `DESIGN.md` — game design intent
- `IMPLEMENTATION.md` — system contracts
- `TECHNICAL_INDEX.md` — file index and signal flow
- `PIPELINE.md` — agent stage order
- **Feature queue: `bd` (`bd ready`, `bd show <id>`)** — see `.cursor/rules/beads-kernel.mdc`. `work-items/WORK_ITEMS.md` is a read-only historical archive; new work is not added there.

## Agent workflow

Rules in `.cursor/rules/`, subagents in `.cursor/agents/`, skills in `.cursor/skills/`.

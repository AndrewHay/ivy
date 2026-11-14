<!-- Generated for Claude Code by semantic-memory from .cursor/rules/algorithm-playgrounds.mdc.
     Edit the source and re-run the semantic-memory install; local edits
     here are overwritten. -->

# Algorithm Playgrounds

Design principle G7 (see `DESIGN.md` → *Algorithm playgrounds*). When you design or
change an algorithm whose result is judged by **feel** — ivy growth, grass blowing,
gusts, fauna motion, camera glides — it must have a **dedicated playground scene** so the
*human designer* can experiment with it. Do not tune by editing constants and eyeballing
the full game, and do not decide "which variant feels better" yourself.

## A playground has

- **Isolation**: standalone scene at `scenes/playground/<name>_playground.tscn`; no village
  build, sim clock, HUD, or save state.
- **Live knobs**: every constant that shapes the feel is a control; changes apply next frame;
  defaults == production values.
- **Algorithm variants**: a selector between structurally different algorithms, always
  including **Current (production)**.
- **Presets, Reset to production, and copy-out** of current settings.
- **Readable stage**: camera presets + free orbit, ground/scale reference, pause / slow-mo for
  temporal algorithms.
- **No production leakage**: global state restored on exit; a test pins production parity.

## When working on such an algorithm

1. Check whether `scenes/playground/` already has its playground; extend it with the new
   variant/knob rather than adding constants in code.
2. If none exists, creating it is part of the task — file/attach a bead for it before
   (or together with) the algorithm change.
3. One implementation: production reads the same params the playground edits. No demo forks.
4. Hand the playground to the user for the feel judgement; agents supply screenshots and
   parity tests, not the verdict.

# Slow GUT tests

Mesh-backed integration tests excluded from the default `res://test/` run (ivy-c7e.2).

| Script | Gate | Why slow |
|---|---|---|
| `test_mesh_sdf.gd` | SG-2 / SD-MESH | Loads `square_sim.sdf` (~10.5 MB); ≥200 stratified raycast samples |
| `test_scenario_seeding.gd` | SG-3 / SG-5 | 30-game-day mesh scenario simulation (720 ticks) |

Invoke via the **slow suite** in `.cursor/skills/run-tests/SKILL.md` (`-gdir=res://test/slow`).

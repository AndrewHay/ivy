# Slow GUT tests

Mesh-backed integration tests excluded from the default `res://test/` run (ivy-c7e.2).

| Script | Gate | Why slow |
|---|---|---|
| `test_mesh_sdf.gd` | SG-2 / SD-MESH | Loads `square_sim.sdf` (~10.5 MB); ≥200 stratified raycast samples |
| `test_scenario_seeding.gd` | SG-3 / SG-5 | 30-game-day mesh scenario simulation (720 ticks) |
| `test_change_building.gd` | ivy-gyf | Full `main.tscn` picker sessions; building switch can trigger coarse light bake |
| `test_sg8_interior_light.gd` | SG-8 | `surface_wall_sim` + full `LightBake.bake()` |
| `test_interior_leak.gd` | W-096 | Same mesh + bake as SG-8 interior leak checks |

Invoke via the **slow suite** in `.cursor/skills/run-tests/SKILL.md` (`-gdir=res://test/slow`).

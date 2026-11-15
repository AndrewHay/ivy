# Slow GUT tests

Mesh-backed integration tests excluded from the default `res://test/` run (ivy-c7e.2).

| Script | Gate | Why slow |
|---|---|---|
| `test_mesh_sdf.gd` | SG-2 / SD-MESH | Loads `square_sim.sdf` (~10.5 MB); ≥200 stratified raycast samples |
| `test_sg9_sdf_collision.gd` | SG-9(c) | All four playable mesh structures; 400 collision rays each, \|Φ\| ≤ 0.01 m + interior sign at 0.10 m |
| `test_scenario_seeding.gd` | SG-3 / SG-5 | 30-game-day mesh scenario simulation (720 ticks) |
| `test_change_building.gd` | ivy-gyf | Full `main.tscn` picker sessions; building switch can trigger coarse light bake |
| `test_sg8_interior_light.gd` | SG-8 | `surface_wall_sim` + full `LightBake.bake()` |
| `test_interior_leak.gd` | W-096 | Same mesh + bake as SG-8 interior leak checks |
| `test_relief_article_probe.gd` | SG-9(d) | Four 30-game-day growth runs on the relief article: sharp (D0-D4, D5 against the recorded separate-process fingerprint), box (D6: must fail D1 or D2), two fillet variants (reported). D1 and D2 as ratified in ivy-b1e.21: D1 = >= 95 % of floor-zone nodes within 0.045 m and median <= 0.02 m; D2 = no far footprint node attached to the growth surface (floating ones reported). About 7-9 min each for the sharp and box tests and about 15 min for the fillet test (two grows); run each with `-gunit_test_name` |

Invoke via the **slow suite** in `.cursor/skills/run-tests/SKILL.md` (`-gdir=res://test/slow`).

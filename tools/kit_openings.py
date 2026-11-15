"""Real openings in the megakit's door / window wall pieces (ivy-b1e.19).

Measured from the kit glTFs as the outline of the hole on both plaster planes
(exterior y = 0 and interior y = 0.2, Blender-local: x along the wall, z up),
rounded outward to the millimetre. The simulation panel that seals an aperture is
sized from these plus SEAL_TUCK on every edge, so no strip of the opening is left
open to growth. The hero visuals keep their own sizes (APERTURE_SPECS / cottage
specs); only the growth surface uses these.

Arched holes are stored as their bounding rectangle: the panel then also overlaps
the solid spandrels above the arch, which is harmless.
"""

from __future__ import annotations

from typing import Dict

KIT_HOLES: Dict[str, Dict[str, float]] = {
    # Ring buildings (square, tower)
    "Wall_UnevenBrick_Door_Round": {"x0": -0.656, "x1": 0.656, "z0": 0.0, "z1": 2.474},
    "Wall_UnevenBrick_Window_Thin_Round": {"x0": -0.322, "x1": 0.322, "z0": 1.048, "z1": 2.523},
    "Wall_UnevenBrick_Window_Wide_Round": {"x0": -0.600, "x1": 0.600, "z0": 1.045, "z1": 2.706},
    # Cottage (ivy)
    "Wall_Plaster_Door_Flat": {"x0": -0.648, "x1": 0.648, "z0": 0.0, "z1": 2.196},
    "Wall_Plaster_Window_Wide_Flat": {"x0": -0.600, "x1": 0.600, "z0": 1.040, "z1": 2.318},
}

# Panel overlap into the surrounding solid wall on every edge.
SEAL_TUCK = 0.03


def seal_spec(piece: str) -> Dict[str, float]:
    """Sim panel extent for ``piece``: its kit hole grown by SEAL_TUCK on every edge.

    Raises KeyError for a door / window piece that has not been measured, so a new
    kit piece cannot silently get an undersized seal.
    """
    hole = KIT_HOLES[piece]
    return {
        "x0": hole["x0"] - SEAL_TUCK,
        "x1": hole["x1"] + SEAL_TUCK,
        "z0": hole["z0"] - SEAL_TUCK,
        "z1": hole["z1"] + SEAL_TUCK,
    }


def coverage_probe_points(piece: str, inset: float = 0.015):
    """(x, z) points just inside the kit hole: 4 corners, 4 edge midpoints, centre."""
    hole = KIT_HOLES[piece]
    x0, x1 = hole["x0"] + inset, hole["x1"] - inset
    z0, z1 = hole["z0"] + inset, hole["z1"] - inset
    xm, zm = (x0 + x1) / 2.0, (z0 + z1) / 2.0
    return [(x, z) for x in (x0, xm, x1) for z in (z0, zm, z1)]

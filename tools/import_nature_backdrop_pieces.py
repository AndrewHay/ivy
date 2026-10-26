#!/usr/bin/env python3
"""Copy Quaternius nature kit glTF pieces into assets/backdrop/ with URI rewrite.

Usage (from repo root):
  python3 tools/import_nature_backdrop_pieces.py Fern_1 Clover_2
  python3 tools/import_nature_backdrop_pieces.py --all-flora

Rewrites bare image URIs to ../textures/ and copies missing textures from the
local kit (assets/_local/stylized_nature_megakit/).
"""

from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
KIT_GLTF = REPO / "assets/_local/stylized_nature_megakit/glTF"
KIT_TEX = REPO / "assets/_local/stylized_nature_megakit/Textures"
OUT_PIECES = REPO / "assets/backdrop/pieces"
OUT_TEX = REPO / "assets/backdrop/textures"

ALL_FLORA = [
    "Bush_Common",
    "Bush_Common_Flowers",
    "Clover_1",
    "Clover_2",
    "Fern_1",
    "Flower_3_Group",
    "Flower_3_Single",
    "Flower_4_Group",
    "Flower_4_Single",
    "Grass_Common_Short",
    "Grass_Common_Tall",
    "Grass_Wispy_Short",
    "Grass_Wispy_Tall",
    "Mushroom_Common",
    "Mushroom_Laetiporus",
    "Petal_1",
    "Petal_2",
    "Petal_3",
    "Petal_4",
    "Petal_5",
    "Plant_1",
    "Plant_1_Big",
    "Plant_7",
    "Plant_7_Big",
]


def _find_texture(name: str) -> Path | None:
    for base in (KIT_GLTF, KIT_TEX):
        p = base / name
        if p.is_file():
            return p
    return None


def import_piece(basename: str) -> None:
    src_gltf = KIT_GLTF / f"{basename}.gltf"
    src_bin = KIT_GLTF / f"{basename}.bin"
    if not src_gltf.is_file():
        raise SystemExit(f"missing kit glTF: {src_gltf}")
    if not src_bin.is_file():
        raise SystemExit(f"missing kit bin: {src_bin}")

    data = json.loads(src_gltf.read_text(encoding="utf-8"))
    textures_needed: set[str] = set()
    for img in data.get("images", []):
        if not isinstance(img, dict) or "uri" not in img:
            continue
        uri: str = img["uri"]
        if uri.startswith("../textures/"):
            tex_name = Path(uri).name
        else:
            tex_name = Path(uri).name
            img["uri"] = f"../textures/{tex_name}"
        textures_needed.add(tex_name)

    OUT_PIECES.mkdir(parents=True, exist_ok=True)
    OUT_TEX.mkdir(parents=True, exist_ok=True)

    dst_gltf = OUT_PIECES / f"{basename}.gltf"
    dst_bin = OUT_PIECES / f"{basename}.bin"
    dst_gltf.write_text(json.dumps(data, separators=(",", ":")), encoding="utf-8")
    shutil.copy2(src_bin, dst_bin)

    for tex_name in sorted(textures_needed):
        dst_tex = OUT_TEX / tex_name
        if dst_tex.is_file():
            continue
        src_tex = _find_texture(tex_name)
        if src_tex is None:
            raise SystemExit(f"{basename}: texture not found in kit: {tex_name}")
        shutil.copy2(src_tex, dst_tex)
        print(f"  texture + {tex_name}")

    print(f"imported {basename}")


def main() -> None:
    if not KIT_GLTF.is_dir():
        raise SystemExit(f"local kit missing: {KIT_GLTF}")

    args = sys.argv[1:]
    if not args:
        raise SystemExit(__doc__)
    if args == ["--all-flora"]:
        names = ALL_FLORA
    else:
        names = args

    for name in names:
        import_piece(name)


if __name__ == "__main__":
    main()

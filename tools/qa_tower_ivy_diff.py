#!/usr/bin/env python3
"""Bare-tower pixel diff for ivy-4f5 / ivy-2p0.6 / ivy-kys corner QA.

Compares a growth capture against the bare-tower baseline. Quoin ROIs are derived
from the bare shade frame's stone silhouette (not fixed pixel bands that drift with
camera framing — ivy-kys).
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image, ImageChops
except ImportError:
    raise SystemExit("PIL (Pillow) is required: pip install Pillow")

SIG_THRESHOLD = 1
QUOIN_FRAC = 0.15
QUOIN_MIN_PX = 120


def _is_stone(r: int, g: int, b: int) -> bool:
    return b < 180 and g < 200


def _stone_span_row(img: Image.Image, y: int) -> tuple[int, int] | None:
    w, _h = img.size
    px = img.load()
    xs = [x for x in range(w) if _is_stone(*px[x, y])]
    if not xs:
        return None
    return min(xs), max(xs)


def quoin_rois_from_bare(bare: Image.Image) -> dict[str, tuple[int, int, int, int]]:
    """Return left/right quoin ROIs (x0, y0, x1, y1) from bare shade framing."""
    w, h = bare.size
    spans: list[tuple[int, int]] = []
    for y in range(int(h * 0.15), int(h * 0.72), 24):
        span = _stone_span_row(bare, y)
        if span is not None:
            spans.append(span)
    if not spans:
        raise SystemExit("could not find stone silhouette in bare shade frame")
    # Narrowest horizontal span = tower body without ground shadow bleed.
    x0, x1 = min(spans, key=lambda s: s[1] - s[0])
    quoin_w = max(QUOIN_MIN_PX, int((x1 - x0) * QUOIN_FRAC))
    return {
        "left_quoin": (x0, 0, x0 + quoin_w, h),
        "right_quoin": (x1 - quoin_w, 0, x1, h),
    }


def _roi_stats(px, w: int, h: int, x0: int, y0: int, x1: int, y1: int) -> dict:
    x0 = max(0, x0)
    y0 = max(0, y0)
    x1 = min(w, x1)
    y1 = min(h, y1)
    total = 0
    sig = 0
    max_delta = 0
    for y in range(y0, y1):
        for x in range(x0, x1):
            r1, g1, b1 = px[x, y]
            total += 1
            d = max(abs(r1), abs(g1), abs(b1))
            max_delta = max(max_delta, d)
            if d >= SIG_THRESHOLD:
                sig += 1
    return {"pixels": total, "sig_pixels": sig, "max_channel_delta": max_delta}


def diff_image(bare_path: Path, grown_path: Path) -> dict:
    bare = Image.open(bare_path).convert("RGB")
    grown = Image.open(grown_path).convert("RGB")
    if bare.size != grown.size:
        raise SystemExit(f"size mismatch: {bare.size} vs {grown.size}")
    w, h = bare.size
    diff = ImageChops.difference(bare, grown)
    px = diff.load()
    global_stats = _roi_stats(px, w, h, 0, 0, w, h)
    rois = quoin_rois_from_bare(bare)
    roi_stats = {
        name: _roi_stats(px, w, h, *box) for name, box in rois.items()
    }
    return {
        "size": (w, h),
        "global": global_stats,
        "rois": roi_stats,
        "roi_boxes": rois,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bare_png", type=Path)
    parser.add_argument("grown_png", type=Path)
    args = parser.parse_args()
    stats = diff_image(args.bare_png, args.grown_png)
    g = stats["global"]
    print(f"image={args.grown_png.name} size={stats['size']}")
    print(
        f"global max_delta={g['max_channel_delta']} sig_pixels={g['sig_pixels']}"
        f" / {g['pixels']}"
    )
    for name, box in stats["roi_boxes"].items():
        r = stats["rois"][name]
        print(
            f"{name} x[{box[0]},{box[2]}] max_delta={r['max_channel_delta']}"
            f" sig_pixels={r['sig_pixels']} / {r['pixels']}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

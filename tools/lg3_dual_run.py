#!/usr/bin/env python3
"""LG-3 dual-run comparison tool.

Usage (from the Ivy project root):
    python3 tools/lg3_dual_run.py

Options:
    --godot PATH   Godot binary  (default: /Applications/Godot.app/Contents/MacOS/Godot)
    --script PATH  Canonical .txt script  (default: tools/ui_scripts/qa_m25_canonical.txt)
    --outdir PATH  Root output dir for both runs  (default: .tmp/lg3)

Runs tools/ui_scripts/qa_m25_canonical.txt twice in serial (each run in its own
sub-directory: outdir/run1 and outdir/run2), then verifies both LG-3 halves:

  Half 1 — Simulation determinism (exact, INV-7 scope)
      Every [ui-script] output line must be identical between the two runs,
      excluding the header line and SCREENSHOT-save lines (which embed the
      run-specific output directory).  Any difference is a hard FAIL — no
      tolerance.

  Half 2 — Image stability (toleranced, SD-OPEN-11 ratified 2026-08-11)
      For each of the 4 canonical PNGs, BOTH of the following must hold:
        · Differing-pixel fraction ≤ 0.05%  (pixels where any channel has
          integer delta > 1, i.e., more than 1/255 in normalised [0,1] space)
        · RGB RMSE ≤ 1e-4
      Both conditions are required (conjunctive).

Requires: Python 3.x, Pillow (PIL) 11.3.0+.  numpy is not used.
Exit code 0 = PASS, 1 = FAIL or error.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

try:
    from PIL import Image, ImageChops
except ImportError:
    raise SystemExit("PIL (Pillow) is required: pip install Pillow")

# ---------------------------------------------------------------------------
# LG-3 image-tolerance ceilings (SD-OPEN-11, ratified 2026-08-11)
# ---------------------------------------------------------------------------
# "Differing pixel" = any channel has integer delta > 1 (more than 1/255).
DIFF_PIXEL_FRACTION_CEILING = 0.0005   # 0.05 %
RGB_RMSE_CEILING = 1e-4

_CANONICAL_IMAGES = [
    "m25_cam_sun.png",
    "m25_cam_shade.png",
    "m25_cam_top.png",
    "m25_cam_silhouette.png",
]

_PROJECT_ROOT = Path(__file__).resolve().parent.parent
_DEFAULT_GODOT = Path("/Applications/Godot.app/Contents/MacOS/Godot")
_DEFAULT_SCRIPT = _PROJECT_ROOT / "tools" / "ui_scripts" / "qa_m25_canonical.txt"
_DEFAULT_OUTDIR = _PROJECT_ROOT / ".tmp" / "lg3"


# ---------------------------------------------------------------------------
# Pure functions (tested by test/test_lg3_compare.py)
# ---------------------------------------------------------------------------

def normalize_stdout_lines(text: str) -> list[str]:
    """Return the comparable subset of [ui-script] lines from a run's stdout.

    Strips:
      - Non-[ui-script] lines (Godot engine start-up noise, timestamps, etc.).
      - The header line ``[ui-script] script=…`` (contains run-specific paths).
      - Every ``[ui-script]   saved …`` line (contains the run-specific outdir).

    The remaining lines encode simulation and rendering state and must be
    bit-identical between two deterministic runs.
    """
    result = []
    for line in text.splitlines():
        if not line.startswith("[ui-script]"):
            continue
        if line.startswith("[ui-script] script="):
            continue
        if "   saved " in line:
            continue
        result.append(line)
    return result


def compare_sim_state(text1: str, text2: str) -> tuple[bool, str]:
    """Compare two runs' simulation-state output for exact equality.

    Returns ``(passed, message)``.  On failure the message identifies the
    first differing line so the caller can narrow down the divergence.
    """
    lines1 = normalize_stdout_lines(text1)
    lines2 = normalize_stdout_lines(text2)

    for i, (l1, l2) in enumerate(zip(lines1, lines2), start=1):
        if l1 != l2:
            return False, (
                f"Simulation state FAIL — first difference at comparable line {i}:\n"
                f"  run1: {l1}\n"
                f"  run2: {l2}"
            )

    if len(lines1) != len(lines2):
        return False, (
            f"Simulation state FAIL — line count differs: "
            f"run1={len(lines1)}  run2={len(lines2)}"
        )

    return True, f"Simulation state PASS — {len(lines1)} comparable lines identical"


def compute_png_diff(path1: Path, path2: Path) -> dict:
    """Compute LG-3 image-diff metrics between two PNG files using PIL only.

    Returns a dict with:
      ``diff_pixel_fraction``   fraction of pixels where any channel has
                                integer delta > 1 (the LG-3 gate metric)
      ``nonzero_pixel_count``   pixels with any non-zero delta (≥ 1), for
                                reference (the W-073 "600 pixels" metric)
      ``nonzero_pixel_fraction`` same, as a fraction
      ``max_channel_delta``     maximum absolute per-channel integer delta
      ``rgb_rmse``              sqrt(mean squared error per channel, channels
                                normalised to [0, 1])
      ``total_pixels``          image pixel count
    """
    img1 = Image.open(path1).convert("RGB")
    img2 = Image.open(path2).convert("RGB")

    if img1.size != img2.size:
        raise ValueError(
            f"Image size mismatch: {path1.name} {img1.size} vs "
            f"{path2.name} {img2.size}"
        )

    total_pixels = img1.size[0] * img1.size[1]

    # Use ImageChops.difference for a fast per-pixel absolute-difference image,
    # then iterate getdata() (faster than nested load() loops for large images).
    diff_img = ImageChops.difference(img1, img2)
    diff_data = diff_img.getdata()  # sequence of (R, G, B) integer tuples

    gate_diff_count = 0   # pixels with max channel delta > 1
    nonzero_count = 0     # pixels with max channel delta ≥ 1
    max_delta = 0
    sse = 0.0             # sum of squared errors, channels normalised to [0,1]

    for r, g, b in diff_data:
        mx = r if r >= g and r >= b else (g if g >= b else b)
        if mx > 1:
            gate_diff_count += 1
        if mx > 0:
            nonzero_count += 1
        if mx > max_delta:
            max_delta = mx
        sse += (r * r + g * g + b * b) / 65025.0  # 255^2 = 65025

    diff_frac = gate_diff_count / total_pixels
    nonzero_frac = nonzero_count / total_pixels
    rmse = (sse / (total_pixels * 3)) ** 0.5

    return {
        "diff_pixel_fraction": diff_frac,
        "nonzero_pixel_fraction": nonzero_frac,
        "nonzero_pixel_count": nonzero_count,
        "max_channel_delta": max_delta,
        "rgb_rmse": rmse,
        "total_pixels": total_pixels,
    }


def check_image_tolerances(stats: dict) -> tuple[bool, list[str]]:
    """Check image diff stats against LG-3 ceilings (SD-OPEN-11).

    Returns ``(passed, reasons)`` where *reasons* is empty on pass and
    lists each violated ceiling on failure.
    """
    reasons: list[str] = []
    frac = stats["diff_pixel_fraction"]
    rmse = stats["rgb_rmse"]

    if frac > DIFF_PIXEL_FRACTION_CEILING:
        reasons.append(
            f"diff_pixel_fraction {frac:.6%} > ceiling "
            f"{DIFF_PIXEL_FRACTION_CEILING:.4%}"
        )
    if rmse > RGB_RMSE_CEILING:
        reasons.append(
            f"rgb_rmse {rmse:.3e} > ceiling {RGB_RMSE_CEILING:.0e}"
        )

    return len(reasons) == 0, reasons


def extract_summary_fields(text: str) -> dict:
    """Extract a handful of key fields for the human-readable summary.

    Returns a dict containing any of ``total_stem_length`` (float),
    ``leaves`` (int), ``segments`` (int), ``coverage_overall_pct`` (float)
    that appear in the text; absent fields are simply not included.
    """
    fields: dict = {}
    for line in text.splitlines():
        m = re.search(
            r"TOTAL_STEM_LENGTH=([\d.]+) m\s+leaves=(\d+)\s+segments=(\d+)",
            line,
        )
        if m:
            fields["total_stem_length"] = float(m.group(1))
            fields["leaves"] = int(m.group(2))
            fields["segments"] = int(m.group(3))
        m = re.search(r"COVERAGE overall=([\d.]+)%", line)
        if m:
            fields["coverage_overall_pct"] = float(m.group(1))
    return fields


# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------

def run_canonical(
    godot: Path,
    script: Path,
    run_outdir: Path,
    project_root: Path,
) -> tuple[int, str]:
    """Run the canonical script once into *run_outdir*.

    Returns ``(exit_code, combined_stdout_stderr_text)``.
    """
    run_outdir.mkdir(parents=True, exist_ok=True)
    res_outdir = "res://" + str(run_outdir.relative_to(project_root))

    cmd = [
        str(godot),
        "res://tools/run_ui_script.tscn",
        "--",
        f"--script={script}",
        f"--outdir={res_outdir}",
    ]
    print(f"[lg3]   cmd: {' '.join(cmd)}")
    result = subprocess.run(
        cmd,
        cwd=str(project_root),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    # Combine both streams; [ui-script] lines come from print() → stdout, but
    # some Godot builds route them differently.
    combined = result.stdout + result.stderr
    return result.returncode, combined


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--godot", type=Path, default=_DEFAULT_GODOT,
                    help="Path to the Godot binary")
    ap.add_argument("--script", type=Path, default=_DEFAULT_SCRIPT,
                    help="Canonical UI script (.txt) to run twice")
    ap.add_argument("--outdir", type=Path, default=_DEFAULT_OUTDIR,
                    help="Root directory for run1/ and run2/ output sub-dirs")
    args = ap.parse_args(argv)

    godot: Path = args.godot
    script: Path = args.script
    outdir: Path = args.outdir
    project_root = _PROJECT_ROOT

    if not godot.exists():
        print(f"[lg3] ERROR: Godot binary not found: {godot}", file=sys.stderr)
        return 1
    if not script.exists():
        print(f"[lg3] ERROR: Script not found: {script}", file=sys.stderr)
        return 1

    sep = "=" * 70
    print(sep)
    print("[lg3] LG-3 Dual-Run Comparison Tool")
    print(f"[lg3] script : {script}")
    print(f"[lg3] outdir : {outdir}")
    print(sep)

    # ------------------------------------------------------------------ Run 1
    run1_dir = outdir / "run1"
    print(f"\n[lg3] === Run 1  (outdir: {run1_dir}) ===")
    rc1, stdout1 = run_canonical(godot, script, run1_dir, project_root)
    # Echo a tail of the output so the user can see progress.
    for line in stdout1.splitlines()[-10:]:
        print(f"[lg3]   {line}")
    if rc1 != 0:
        print(f"\n[lg3] ERROR: Run 1 exited with code {rc1}", file=sys.stderr)
        return 1
    print(f"[lg3] Run 1 completed (exit 0)")

    # ------------------------------------------------------------------ Run 2
    run2_dir = outdir / "run2"
    print(f"\n[lg3] === Run 2  (outdir: {run2_dir}) ===")
    rc2, stdout2 = run_canonical(godot, script, run2_dir, project_root)
    for line in stdout2.splitlines()[-10:]:
        print(f"[lg3]   {line}")
    if rc2 != 0:
        print(f"\n[lg3] ERROR: Run 2 exited with code {rc2}", file=sys.stderr)
        return 1
    print(f"[lg3] Run 2 completed (exit 0)")

    # ---------------------------------------------------------- Summary fields
    f1 = extract_summary_fields(stdout1)
    f2 = extract_summary_fields(stdout2)
    print(f"\n[lg3] Run 1: segments={f1.get('segments','?')}  "
          f"leaves={f1.get('leaves','?')}  "
          f"stem={f1.get('total_stem_length','?')} m  "
          f"coverage={f1.get('coverage_overall_pct','?')}%")
    print(f"[lg3] Run 2: segments={f2.get('segments','?')}  "
          f"leaves={f2.get('leaves','?')}  "
          f"stem={f2.get('total_stem_length','?')} m  "
          f"coverage={f2.get('coverage_overall_pct','?')}%")

    # ------------------------------------------- Half 1: Simulation determinism
    print(f"\n[lg3] {'─'*60}")
    print("[lg3] Half 1: Simulation determinism")
    print(f"[lg3] {'─'*60}")
    sim_passed, sim_msg = compare_sim_state(stdout1, stdout2)
    print(f"[lg3] {sim_msg}")

    # ----------------------------------------------- Half 2: Image stability
    print(f"\n[lg3] {'─'*60}")
    print("[lg3] Half 2: Image stability")
    print(f"[lg3] {'─'*60}")
    print(f"[lg3] Ceilings: diff_pixel_fraction ≤ {DIFF_PIXEL_FRACTION_CEILING:.4%}, "
          f"rgb_rmse ≤ {RGB_RMSE_CEILING:.0e}")

    all_images_passed = True
    for name in _CANONICAL_IMAGES:
        p1 = run1_dir / name
        p2 = run2_dir / name
        if not p1.exists() or not p2.exists():
            print(f"[lg3] SKIP  {name}: file missing "
                  f"(run1={p1.exists()} run2={p2.exists()})")
            all_images_passed = False
            continue
        stats = compute_png_diff(p1, p2)
        img_passed, reasons = check_image_tolerances(stats)
        if not img_passed:
            all_images_passed = False
        status = "PASS" if img_passed else "FAIL"
        nonzero_pct = stats["nonzero_pixel_fraction"] * 100
        print(
            f"[lg3] {status}  {name}: "
            f"diff_frac={stats['diff_pixel_fraction']:.6%}  "
            f"nonzero={stats['nonzero_pixel_count']}"
            f"({nonzero_pct:.4f}%)  "
            f"max_delta={stats['max_channel_delta']}  "
            f"rmse={stats['rgb_rmse']:.3e}"
        )
        for r in reasons:
            print(f"[lg3]       >> FAIL reason: {r}")

    # --------------------------------------------------------- Overall verdict
    overall = sim_passed and all_images_passed
    status_str = "PASS" if overall else "FAIL"
    print(f"\n{sep}")
    print(f"[lg3] LG-3 OVERALL: {status_str}")
    print(f"[lg3]   Half 1 (sim determinism): {'PASS' if sim_passed else 'FAIL'}")
    print(f"[lg3]   Half 2 (image stability): {'PASS' if all_images_passed else 'FAIL'}")
    print(sep)

    return 0 if overall else 1


if __name__ == "__main__":
    raise SystemExit(main())

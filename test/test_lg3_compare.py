#!/usr/bin/env python3
"""Unit tests for LG-3 dual-run comparison pure functions (TDD).

TDD order (each was RED before the corresponding implementation existed):
  1. test_normalize_strips_header_line
  2. test_normalize_strips_saved_lines
  3. test_normalize_strips_non_ui_script_lines
  4. test_normalize_keeps_metric_lines
  5. test_compare_sim_state_passes_identical
  6. test_compare_sim_state_passes_despite_different_outdirs
  7. test_compare_sim_state_fails_on_first_differing_line
  8. test_compare_sim_state_fails_on_line_count_mismatch
  9. test_compute_png_diff_identical_images_all_zero
 10. test_compute_png_diff_one_differing_pixel_by_two
 11. test_compute_png_diff_delta_one_not_counted_as_differing
 12. test_compute_png_diff_rmse_matches_manual_calculation
 13. test_check_tolerances_passes_below_all_ceilings
 14. test_check_tolerances_exact_ceiling_values_pass
 15. test_check_tolerances_fails_on_high_pixel_fraction
 16. test_check_tolerances_fails_on_high_rmse
 17. test_extract_summary_fields_parses_stem_leaves_segments
 18. test_extract_summary_fields_parses_coverage

Run with:
    python3 test/test_lg3_compare.py
or:
    python3 -m unittest test.test_lg3_compare
"""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

# Make tools/ importable without installing anything.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))

from lg3_dual_run import (
    check_image_tolerances,
    compare_sim_state,
    compute_png_diff,
    extract_summary_fields,
    normalize_stdout_lines,
)

try:
    from PIL import Image
except ImportError:
    raise SystemExit("PIL (Pillow) is required: pip install Pillow")


# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------

def _solid_png(width: int, height: int, color: tuple[int, int, int]) -> Path:
    """Write a solid-colour PNG to a temp file; caller must unlink when done."""
    img = Image.new("RGB", (width, height), color)
    tmp = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
    img.save(tmp.name)
    return Path(tmp.name)


def _edited_png(base_color, width, height, edits: list[tuple[int, int, tuple[int, int, int]]]) -> Path:
    """Create a PNG like _solid_png but with per-pixel colour overrides.

    edits is a list of ((x, y), (r, g, b)) tuples.
    """
    img = Image.new("RGB", (width, height), base_color)
    px = img.load()
    for (x, y), color in edits:
        px[x, y] = color
    tmp = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
    img.save(tmp.name)
    return Path(tmp.name)


# ---------------------------------------------------------------------------
# TestNormalizeStdoutLines
# ---------------------------------------------------------------------------

_SAMPLE_RUN = (
    "Godot Engine v4.4  -- https://godotengine.org\n"
    "[ui-script] script=/path/run.txt  outdir=res://.tmp/lg3/run1/  steps=12\n"
    "[ui-script]   CAMERA sun (index=0)\n"
    "[ui-script]   saved /path/.tmp/lg3/run1/m25_cam_sun.png size=(1920, 1080)\n"
    "[ui-script]   COVERAGE overall=84.35% (target >=70%)\n"
    "[ui-script]   TOTAL_STEM_LENGTH=1288.816543 m  leaves=18390  segments=43870\n"
    "[ui-script]   LIP_REACHED=true\n"
)


class TestNormalizeStdoutLines(unittest.TestCase):
    def test_strips_header_line(self):
        lines = normalize_stdout_lines(_SAMPLE_RUN)
        self.assertFalse(any("script=" in l for l in lines))

    def test_strips_saved_lines(self):
        lines = normalize_stdout_lines(_SAMPLE_RUN)
        self.assertFalse(any("saved" in l for l in lines))

    def test_strips_non_ui_script_lines(self):
        lines = normalize_stdout_lines(_SAMPLE_RUN)
        self.assertFalse(any("Godot Engine" in l for l in lines))

    def test_keeps_metric_lines(self):
        lines = normalize_stdout_lines(_SAMPLE_RUN)
        tags = [l.split()[1] for l in lines if len(l.split()) > 1]
        self.assertIn("CAMERA", " ".join(tags))
        self.assertIn("COVERAGE", " ".join(lines))
        self.assertIn("TOTAL_STEM_LENGTH", " ".join(lines))
        self.assertIn("LIP_REACHED", " ".join(lines))

    def test_empty_input_returns_empty_list(self):
        self.assertEqual(normalize_stdout_lines(""), [])


# ---------------------------------------------------------------------------
# TestCompareSimState
# ---------------------------------------------------------------------------

def _run_text(outdir_tag: str = "run1") -> str:
    return (
        f"[ui-script] script=foo.txt  outdir=res://.tmp/lg3/{outdir_tag}/  steps=5\n"
        "[ui-script]   COVERAGE overall=84.35% (target >=70%)\n"
        "[ui-script]   TOTAL_STEM_LENGTH=1288.816543 m  leaves=18390  segments=43870\n"
        f"[ui-script]   saved /path/.tmp/lg3/{outdir_tag}/m25_cam_sun.png size=(1920, 1080)\n"
    )


class TestCompareSimState(unittest.TestCase):
    def test_passes_identical_runs(self):
        t = _run_text()
        passed, msg = compare_sim_state(t, t)
        self.assertTrue(passed, msg)

    def test_passes_despite_different_outdirs(self):
        t1 = _run_text("run1")
        t2 = _run_text("run2")
        passed, msg = compare_sim_state(t1, t2)
        self.assertTrue(passed, msg)

    def test_fails_on_first_differing_line(self):
        t1 = _run_text()
        t2 = t1.replace("1288.816543", "1288.816544")
        passed, msg = compare_sim_state(t1, t2)
        self.assertFalse(passed)
        # Message should mention both versions so the caller can diff them.
        self.assertIn("1288.816543", msg)
        self.assertIn("1288.816544", msg)

    def test_fails_on_line_count_mismatch(self):
        t1 = _run_text()
        t2 = t1 + "[ui-script]   EXTRA line\n"
        passed, msg = compare_sim_state(t1, t2)
        self.assertFalse(passed)
        self.assertIn("line count", msg.lower())

    def test_message_includes_line_number_on_diff(self):
        t1 = _run_text()
        t2 = t1.replace("84.35", "84.36")
        passed, msg = compare_sim_state(t1, t2)
        self.assertFalse(passed)
        # The message should mention which line differed.
        self.assertRegex(msg, r"line \d+")


# ---------------------------------------------------------------------------
# TestComputePngDiff
# ---------------------------------------------------------------------------

class TestComputePngDiff(unittest.TestCase):
    def setUp(self):
        self._tmp_files: list[Path] = []

    def tearDown(self):
        for p in self._tmp_files:
            try:
                p.unlink()
            except FileNotFoundError:
                pass

    def _png(self, w, h, color):
        p = _solid_png(w, h, color)
        self._tmp_files.append(p)
        return p

    def _edited(self, base, w, h, edits):
        p = _edited_png(base, w, h, edits)
        self._tmp_files.append(p)
        return p

    def test_identical_images_all_zero(self):
        p = self._png(8, 8, (100, 150, 200))
        stats = compute_png_diff(p, p)
        self.assertEqual(stats["diff_pixel_fraction"], 0.0)
        self.assertEqual(stats["max_channel_delta"], 0)
        self.assertAlmostEqual(stats["rgb_rmse"], 0.0)

    def test_pixel_delta_two_counts_as_differing(self):
        # 4×4 = 16 pixels; 1 pixel has red delta=2 → should count as 1 differing
        p1 = self._png(4, 4, (100, 100, 100))
        p2 = self._edited((100, 100, 100), 4, 4, [((0, 0), (102, 100, 100))])
        stats = compute_png_diff(p1, p2)
        self.assertAlmostEqual(stats["diff_pixel_fraction"], 1 / 16, places=8)
        self.assertEqual(stats["max_channel_delta"], 2)

    def test_pixel_delta_one_does_not_count_as_differing(self):
        # Delta of exactly 1 is NOT "more than 1/255" — should NOT be counted
        p1 = self._png(4, 4, (100, 100, 100))
        p2 = self._edited((100, 100, 100), 4, 4, [((0, 0), (101, 100, 100))])
        stats = compute_png_diff(p1, p2)
        self.assertEqual(stats["diff_pixel_fraction"], 0.0)
        self.assertEqual(stats["max_channel_delta"], 1)

    def test_nonzero_pixel_count_includes_delta_one(self):
        # A pixel with delta=1 doesn't count toward diff_pixel_fraction but
        # should appear in nonzero_pixel_count.
        p1 = self._png(4, 4, (128, 128, 128))
        p2 = self._edited((128, 128, 128), 4, 4, [((0, 0), (129, 128, 128))])
        stats = compute_png_diff(p1, p2)
        self.assertEqual(stats["nonzero_pixel_count"], 1)
        self.assertEqual(stats["diff_pixel_fraction"], 0.0)

    def test_rmse_matches_manual_calculation(self):
        # 2×2 = 4 pixels; pixel (0,0) has red delta=4, all others identical.
        # SSE (across all 3 channels, normalised to [0,1]):
        #   = (4/255)^2  (one channel of one pixel)
        # RMSE = sqrt(SSE / (4 pixels × 3 channels))
        p1 = self._png(2, 2, (100, 100, 100))
        p2 = self._edited((100, 100, 100), 2, 2, [((0, 0), (104, 100, 100))])
        stats = compute_png_diff(p1, p2)
        expected_rmse = ((4 / 255) ** 2 / (4 * 3)) ** 0.5
        self.assertAlmostEqual(stats["rgb_rmse"], expected_rmse, places=12)

    def test_max_channel_delta_across_all_channels(self):
        p1 = self._png(4, 4, (100, 100, 100))
        # pixel (0,0): dr=3, dg=1, db=5 → max_channel_delta should be 5
        p2 = self._edited((100, 100, 100), 4, 4, [((0, 0), (103, 101, 105))])
        stats = compute_png_diff(p1, p2)
        self.assertEqual(stats["max_channel_delta"], 5)

    def test_size_mismatch_raises(self):
        p1 = self._png(4, 4, (0, 0, 0))
        p2 = self._png(8, 4, (0, 0, 0))
        with self.assertRaises(ValueError):
            compute_png_diff(p1, p2)


# ---------------------------------------------------------------------------
# TestCheckImageTolerances
# ---------------------------------------------------------------------------

_PASSING_STATS = {
    "diff_pixel_fraction": 0.0003,   # 0.03% < ceiling 0.05%
    "max_channel_delta": 1,           # ≤ 1/255
    "rgb_rmse": 4.2e-6,              # < 1e-4
    "nonzero_pixel_fraction": 0.0003,
    "nonzero_pixel_count": 600,
    "total_pixels": 2_073_600,
}


class TestCheckImageTolerances(unittest.TestCase):
    def test_passes_below_all_ceilings(self):
        passed, reasons = check_image_tolerances(_PASSING_STATS)
        self.assertTrue(passed, reasons)
        self.assertEqual(reasons, [])

    def test_exact_ceiling_values_pass(self):
        stats = {**_PASSING_STATS, "diff_pixel_fraction": 0.0005, "rgb_rmse": 1e-4}
        passed, reasons = check_image_tolerances(stats)
        self.assertTrue(passed, reasons)

    def test_fails_on_high_pixel_fraction(self):
        stats = {**_PASSING_STATS, "diff_pixel_fraction": 0.00051}
        passed, reasons = check_image_tolerances(stats)
        self.assertFalse(passed)
        self.assertTrue(any("diff_pixel_fraction" in r for r in reasons), reasons)

    def test_fails_on_high_rmse(self):
        stats = {**_PASSING_STATS, "rgb_rmse": 1.001e-4}
        passed, reasons = check_image_tolerances(stats)
        self.assertFalse(passed)
        self.assertTrue(any("rgb_rmse" in r for r in reasons), reasons)

    def test_both_checks_fail_reports_both_reasons(self):
        stats = {**_PASSING_STATS, "diff_pixel_fraction": 0.001, "rgb_rmse": 5e-4}
        passed, reasons = check_image_tolerances(stats)
        self.assertFalse(passed)
        self.assertEqual(len(reasons), 2)


# ---------------------------------------------------------------------------
# TestExtractSummaryFields
# ---------------------------------------------------------------------------

_SAMPLE_STDOUT = (
    "[ui-script]   TOTAL_STEM_LENGTH=1288.816543 m  leaves=18390  segments=43870\n"
    "[ui-script]   COVERAGE overall=84.35% (target >=70%)\n"
    "[ui-script]   LIP_REACHED=true\n"
)


class TestExtractSummaryFields(unittest.TestCase):
    def test_parses_stem_leaves_segments(self):
        f = extract_summary_fields(_SAMPLE_STDOUT)
        self.assertAlmostEqual(f["total_stem_length"], 1288.816543, places=6)
        self.assertEqual(f["leaves"], 18390)
        self.assertEqual(f["segments"], 43870)

    def test_parses_coverage(self):
        f = extract_summary_fields(_SAMPLE_STDOUT)
        self.assertAlmostEqual(f["coverage_overall_pct"], 84.35, places=2)

    def test_missing_fields_absent(self):
        f = extract_summary_fields("")
        self.assertNotIn("segments", f)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    unittest.main()

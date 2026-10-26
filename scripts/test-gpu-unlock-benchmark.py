#!/usr/bin/env python3
"""Test saved-result comparison without importing CUDA or PyTorch."""

import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


BENCHMARK = Path(__file__).resolve().parents[1] / "apps/gpu-unlock/benchmark.py"


class ComparisonTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.before = {
            "gpu": "test GPU", "uuid": "test-uuid", "visible_devices": "GPU-test-uuid",
            "torch": "2.8.0+cu128", "cuda": "12.8", "kernel": "test-kernel",
            "driver_settings": {"driver": "test", "power_limit_w": "320"},
            "size": 8192, "samples": 5, "iterations_per_sample": 50,
            "warmup_iterations": 20, "reduced_precision_reduction": False,
            "boot_requested_targets": None,
            "results": {"bf16": {"median_tflops": 80.0, "finite_output": True,
                                   "spotcheck_relative_l2_error": 0.002}},
        }
        self.after = copy.deepcopy(self.before)
        self.after["boot_requested_targets"] = "all"
        self.after["results"]["bf16"]["median_tflops"] = 120.0

    def compare(self):
        before = Path(self.directory.name) / "before.json"
        after = Path(self.directory.name) / "after.json"
        before.write_text(json.dumps(self.before))
        after.write_text(json.dumps(self.after))
        return subprocess.run(
            [sys.executable, str(BENCHMARK), "compare", str(before), str(after)],
            text=True, capture_output=True,
        )

    def test_gain_and_different_boot_state(self):
        result = self.compare()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("+50.0%, 1.50x", result.stdout)
        self.assertIn("numerical spot-check", result.stdout)

    def test_mismatched_configuration(self):
        for key in ("uuid", "torch", "cuda", "kernel", "driver_settings", "size", "samples"):
            with self.subTest(key=key):
                saved = self.after[key]
                self.after[key] = "different"
                result = self.compare()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("incomparable reports", result.stderr)
                self.after[key] = saved

    def test_nonfinite_output_is_rejected(self):
        self.after["results"]["bf16"]["finite_output"] = False
        result = self.compare()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("nonfinite output", result.stderr)

    def test_different_dtypes_are_rejected(self):
        self.after["results"]["tf32"] = self.after["results"]["bf16"]
        self.assertNotEqual(self.compare().returncode, 0)

    def test_invalid_size_fails_before_cuda_import(self):
        result = subprocess.run(
            [sys.executable, str(BENCHMARK), "--size", "0"], capture_output=True, text=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must be positive", result.stderr)


if __name__ == "__main__":
    unittest.main()

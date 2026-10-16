"""Regression tests for fail-closed CLI argument validation (no network)."""
import subprocess
import sys
import unittest
from pathlib import Path

ENTRY = Path(__file__).with_name("job.py")


class ActionsDispatchArgumentTests(unittest.TestCase):
    def call_dispatch(self, *args):
        return subprocess.run(
            [sys.executable, str(ENTRY), "actions", "dispatch", *args],
            capture_output=True,
            text=True,
            timeout=5,
        )

    def test_missing_parallelism_reports_usage_not_traceback(self):
        result = self.call_dispatch("dummy.yml", "0123456", "demo", "3")
        self.assertEqual(result.returncode, 2)
        self.assertIn("<maxparallel>", result.stdout)
        self.assertNotIn("Traceback", result.stdout + result.stderr)

    def test_invalid_parallelism_reports_error_not_traceback(self):
        result = self.call_dispatch("dummy.yml", "0123456", "demo", "3", "bad")
        self.assertEqual(result.returncode, 2)
        self.assertIn("positive integers", result.stderr)
        self.assertNotIn("Traceback", result.stdout + result.stderr)

    def test_nonpositive_values_are_rejected(self):
        for shards, parallel in [("0", "2"), ("3", "-1"), ("-2", "1")]:
            with self.subTest(shards=shards, parallel=parallel):
                result = self.call_dispatch("dummy.yml", "0123456", "demo", shards, parallel)
                self.assertEqual(result.returncode, 2)
                self.assertIn("positive integers", result.stderr)
                self.assertNotIn("Traceback", result.stdout + result.stderr)

    def test_invalid_shards_reports_error_not_traceback(self):
        result = self.call_dispatch("dummy.yml", "0123456", "demo", "bad", "2")
        self.assertEqual(result.returncode, 2)
        self.assertIn("positive integers", result.stderr)
        self.assertNotIn("Traceback", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()

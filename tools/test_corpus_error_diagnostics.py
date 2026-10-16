"""An accept summary never overrides an error diagnostic."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "corpus_harness", Path(__file__).with_name("corpus_harness.py")
)
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)


class ErrorDiagnosticTests(unittest.TestCase):
    def agrees(self, expected, diagnostics):
        got = harness.classify_got({"verdict": "accept"}, diagnostics)
        return harness.agree((expected, None), got)[0]

    def test_accept_with_unclassified_error_fails(self):
        for rule in (None, ""):
            with self.subTest(rule=rule):
                self.assertFalse(self.agrees("ACCEPT", [
                    {"severity": "error", "code": "HYB-E4001", "tier0_rule": rule}
                ]))

    def test_managed_accept_with_unclassified_error_fails(self):
        self.assertFalse(self.agrees("ACCEPT-MANAGED", [
            {"severity": "warning", "code": "HYB-E8001"},
            {"severity": "error", "code": "HYB-E0002"},
        ]))

    def test_clean_accept_and_managed_accept_still_pass(self):
        self.assertTrue(self.agrees("ACCEPT", []))
        self.assertTrue(self.agrees("ACCEPT-MANAGED", [
            {"severity": "warning", "code": "HYB-E8001"}
        ]))

    def test_matching_reject_rule_still_passes(self):
        got = harness.classify_got({"verdict": "reject"}, [
            {"severity": "error", "tier0_rule": "A1b"}
        ])
        self.assertTrue(harness.agree(("REJECT", "A1b"), got)[0])


if __name__ == "__main__":
    unittest.main()

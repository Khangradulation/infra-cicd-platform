"""Offline tests for scripts/pr-gate.py, including the real workflow files."""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("pr_gate", ROOT / "scripts" / "pr-gate.py")
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


def workflow_paths(name: str) -> list[str] | None:
    return gate.pull_request_paths((ROOT / ".github" / "workflows" / f"{name}.yml").read_text())


class PathParsingTest(unittest.TestCase):
    def test_reads_pull_request_paths_not_push_paths(self):
        paths = workflow_paths("app-ci")
        self.assertIn("application/**", paths)
        self.assertIn("scripts/container-smoke-test.sh", paths)  # listed under pull_request only

    def test_workflow_without_a_filter(self):
        self.assertIsNone(workflow_paths("lint"))

    def test_every_real_pattern_is_supported(self):
        for name in gate.WORKFLOWS:
            for pattern in workflow_paths(name):
                gate.matches(pattern, "some/file")  # raises on an unsupported shape


class MatchingTest(unittest.TestCase):
    def test_real_workflows(self):
        app, tf = workflow_paths("app-ci"), workflow_paths("terraform-pr")
        self.assertTrue(gate.applies(app, ["application/src/app/__init__.py"]))
        self.assertFalse(gate.applies(tf, ["application/src/app/__init__.py"]))
        self.assertTrue(gate.applies(tf, ["terraform/modules/ecr/main.tf"]))
        self.assertFalse(gate.applies(app, ["docs/setup.md"]))
        self.assertFalse(gate.applies(tf, ["docs/setup.md"]))

    def test_prefix_needs_a_directory_boundary(self):
        self.assertFalse(gate.matches("application/**", "application-notes.md"))

    def test_unsupported_pattern_fails_closed(self):
        for pattern in ("**/*.tf", "!docs/**", "src/*.py"):
            with self.assertRaises(ValueError):
                gate.matches(pattern, "x")


class EvaluateTest(unittest.TestCase):
    DONE = {"status": "completed", "conclusion": "success"}

    def test_not_triggered_passes(self):
        self.assertEqual(gate.evaluate(False, None, 0, 300), "pass")

    def test_expected_but_not_started_waits_then_fails(self):
        self.assertEqual(gate.evaluate(True, None, 10, 300), "wait")
        self.assertIn("never started", gate.evaluate(True, None, 301, 300))

    def test_in_progress_waits(self):
        self.assertEqual(gate.evaluate(True, {"status": "in_progress", "conclusion": None}, 0, 300), "wait")

    def test_success_passes(self):
        self.assertEqual(gate.evaluate(True, self.DONE, 0, 300), "pass")

    def test_any_other_conclusion_fails(self):
        for conclusion in ("failure", "cancelled", "timed_out", "skipped"):
            run = {"status": "completed", "conclusion": conclusion}
            self.assertIn(conclusion, gate.evaluate(True, run, 0, 300))

    def test_unexpected_run_still_counts(self):
        run = {"status": "completed", "conclusion": "failure"}
        self.assertIn("failure", gate.evaluate(False, run, 0, 300))


if __name__ == "__main__":
    unittest.main()

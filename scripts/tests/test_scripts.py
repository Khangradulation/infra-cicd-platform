"""Offline tests for CI helper scripts.

  python3 -m unittest discover -s scripts/tests -v

deploy-ecs.sh is driven against a fake `aws` CLI (fake_aws.py) to prove the
rollback / verification logic fails the job in every bad scenario.
"""

from __future__ import annotations

import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
DIGEST = "sha256:" + "1" * 64


def run_summary(plan: dict) -> tuple[str, str, str]:
    with tempfile.TemporaryDirectory() as d:
        md, fp = Path(d, "s.md"), Path(d, "fp.txt")
        res = subprocess.run(
            [sys.executable, str(SCRIPTS / "tf-plan-summary.py"), "--env", "dev",
             "--markdown", str(md), "--fingerprint-file", str(fp)],
            input=json.dumps(plan), capture_output=True, text=True, check=True,
        )
        return res.stdout, md.read_text(), fp.read_text()


class PlanSummaryTest(unittest.TestCase):
    PLAN = {
        "resource_changes": [
            {"address": "module.x.aws_vpc.this", "change": {"actions": ["create"],
             "after": {"cidr_block": "10.0.0.0/16", "secret_value": "hunter2"}}},
            {"address": "aws_iam_role.r", "change": {"actions": ["delete", "create"]}},
            {"address": "aws_s3_bucket.b", "change": {"actions": ["no-op"]}},
            {"address": "data.aws_region.r", "change": {"actions": ["read"]}},
        ],
        "output_changes": {"app_url": {"actions": ["update"]}},
    }

    def test_counts_and_no_values(self):
        out, md, _ = run_summary(self.PLAN)
        self.assertIn("has_changes=true", out)
        self.assertIn("1 to add, 0 to change, 0 to destroy, 1 to replace", md)
        self.assertIn("module.x.aws_vpc.this", md)
        self.assertNotIn("aws_s3_bucket.b", md, "no-op resources must be omitted")
        self.assertNotIn("hunter2", md, "attribute values must never be printed")
        self.assertNotIn("10.0.0.0/16", md)
        self.assertIn("WARNING", md)

    def test_fingerprint_is_order_independent_and_change_sensitive(self):
        _, _, fp1 = run_summary(self.PLAN)
        reordered = dict(self.PLAN, resource_changes=list(reversed(self.PLAN["resource_changes"])))
        _, _, fp2 = run_summary(reordered)
        self.assertEqual(fp1, fp2)
        changed = json.loads(json.dumps(self.PLAN))
        changed["resource_changes"][1]["change"]["actions"] = ["update"]
        _, _, fp3 = run_summary(changed)
        self.assertNotEqual(fp1, fp3)

    def test_empty_plan(self):
        out, md, _ = run_summary({"resource_changes": []})
        self.assertIn("has_changes=false", out)
        self.assertIn("No infrastructure changes", md)


@unittest.skipUnless(shutil.which("jq"), "jq required")
class DeployScriptTest(unittest.TestCase):
    def run_deploy(self, scenario: str, timeout: str = "60") -> tuple[subprocess.CompletedProcess, dict, str]:
        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, tmp)
        bindir = tmp / "bin"
        bindir.mkdir()
        fake = bindir / "aws"
        fake.write_text(f"#!/bin/sh\nexec {sys.executable} {SCRIPTS / 'tests' / 'fake_aws.py'} \"$@\"\n")
        fake.chmod(fake.stat().st_mode | stat.S_IEXEC)
        sleep = bindir / "sleep"  # make polling instant
        sleep.write_text("#!/bin/sh\nexit 0\n")
        sleep.chmod(0o755)
        gh_out = tmp / "gh_output"
        env = {
            **os.environ,
            "PATH": f"{bindir}:{os.environ['PATH']}",
            "AWS_REGION": "us-east-1",
            "FAKE_AWS_SCENARIO": scenario,
            "FAKE_AWS_STATE": str(tmp / "state.json"),
            "FAKE_AWS_DIGEST": DIGEST,
            "DEPLOY_TIMEOUT_SECONDS": timeout,
            "GITHUB_OUTPUT": str(gh_out),
            "RUNNER_TEMP": str(tmp),
        }
        res = subprocess.run(["bash", str(SCRIPTS / "deploy-ecs.sh"), "dev", DIGEST],
                             env=env, capture_output=True, text=True, timeout=120)
        state = json.loads((tmp / "state.json").read_text()) if (tmp / "state.json").exists() else {}
        return res, state, gh_out.read_text() if gh_out.exists() else ""

    def test_success_registers_digest_pinned_image_and_verifies(self):
        res, state, outputs = self.run_deploy("success")
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertEqual(state["registered_image"],
                         f"111111111111.dkr.ecr.us-east-1.amazonaws.com/icp/app@{DIGEST}")
        for k in ("taskDefinitionArn", "revision", "status", "requiresAttributes", "compatibilities"):
            self.assertNotIn(k, state["registered_keys"], f"read-only field {k} must be stripped")
        self.assertIn("verified 1 running task(s)", res.stdout)
        self.assertIn("url=http://icp-dev-alb-123.us-east-1.elb.amazonaws.com", outputs)
        self.assertIn("previous_task_definition_arn=", outputs)

    def test_circuit_breaker_rollback_fails_the_job(self):
        res, _, _ = self.run_deploy("rollback")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("circuit breaker rolled", res.stdout)

    def test_failed_rollout_fails_the_job(self):
        res, _, _ = self.run_deploy("failed")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("deployment FAILED", res.stdout)

    def test_wrong_running_digest_fails_the_job(self):
        res, _, _ = self.run_deploy("wrong_digest")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("running tasks are not on", res.stdout)

    def test_digest_missing_from_ecr_fails_before_any_change(self):
        res, state, _ = self.run_deploy("missing_image")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("not found in ECR", res.stdout)
        self.assertNotIn("ecs update-service", state.get("calls", []))

    def test_stuck_rollout_times_out(self):
        res, _, _ = self.run_deploy("stuck", timeout="0")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("timed out", res.stdout)

    def test_rejects_malformed_digest(self):
        res = subprocess.run(["bash", str(SCRIPTS / "deploy-ecs.sh"), "dev", "latest"],
                             env={**os.environ, "AWS_REGION": "us-east-1"}, capture_output=True, text=True)
        self.assertEqual(res.returncode, 2)


if __name__ == "__main__":
    unittest.main()

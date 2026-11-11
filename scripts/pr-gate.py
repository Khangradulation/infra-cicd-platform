#!/usr/bin/env python3
"""Single required status check for workflows that use `paths:` filters.

GitHub never starts a path-filtered workflow on a PR that doesn't match it, so
requiring it directly would leave that PR waiting forever. This gate works out
which workflows apply to the PR (from their own `paths:` lists, so nothing is
duplicated here), waits for them, and fails unless each one succeeded.

Env: GITHUB_REPOSITORY, PR_NUMBER, HEAD_SHA, GH_TOKEN.
Optional: GATE_TIMEOUT_SECONDS (default 2400), GATE_START_GRACE_SECONDS (default 300).
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

WORKFLOWS = ("app-ci", "terraform-pr")
POLL_SECONDS = 15


def pull_request_paths(workflow_text: str) -> list[str] | None:
    """Return on.pull_request.paths from a workflow, or None if it has no filter."""
    paths: list[str] | None = None
    in_on = in_pr = in_paths = False
    for raw in workflow_text.splitlines():
        line = raw.split(" #")[0].rstrip()
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())
        if indent == 0:
            in_on, in_pr, in_paths = stripped == "on:", False, False
        elif in_on and indent == 2:
            in_pr, in_paths = stripped == "pull_request:", False
        elif in_pr and indent == 4:
            in_paths = stripped == "paths:"
            if in_paths:
                paths = []
        elif in_paths and paths is not None and stripped.startswith("- "):
            paths.append(stripped[2:].strip().strip("\"'"))
    return paths


def matches(pattern: str, path: str) -> bool:
    """Match the two pattern shapes these workflows use; refuse anything else."""
    if pattern.endswith("/**") and not set(pattern[:-3]) & set("*?[]!+"):
        return path.startswith(pattern[:-2])
    if set(pattern) & set("*?[]!+"):
        raise ValueError(f"unsupported paths pattern {pattern!r}: teach scripts/pr-gate.py about it")
    return path == pattern


def applies(patterns: list[str] | None, changed: list[str]) -> bool:
    if patterns is None:
        return True
    return any(matches(p, f) for p in patterns for f in changed)


def evaluate(expected: bool, run: dict | None, waited: float, grace: float) -> str:
    """Return 'pass', 'wait' or a failure message for one workflow."""
    if run is None:
        if not expected:
            return "pass"
        return "wait" if waited < grace else "expected to run but never started"
    if run["status"] != "completed":
        return "wait"
    return "pass" if run["conclusion"] == "success" else f"concluded {run['conclusion']}"


def gh(path: str) -> list | dict:
    out = subprocess.run(["gh", "api", "--paginate", "--slurp", path],
                         capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def changed_files(repo: str, pr: str) -> list[str]:
    files: list[str] = []
    for page in gh(f"repos/{repo}/pulls/{pr}/files?per_page=100"):
        for f in page:
            files.append(f["filename"])
            if f.get("previous_filename"):
                files.append(f["previous_filename"])
    return files


def latest_run(repo: str, workflow: str, sha: str) -> dict | None:
    pages = gh(f"repos/{repo}/actions/workflows/{workflow}.yml/runs?event=pull_request&head_sha={sha}&per_page=100")
    runs = [r for page in pages for r in page["workflow_runs"]]
    return max(runs, key=lambda r: r["run_number"]) if runs else None


def main() -> int:
    repo, pr, sha = os.environ["GITHUB_REPOSITORY"], os.environ["PR_NUMBER"], os.environ["HEAD_SHA"]
    timeout = float(os.environ.get("GATE_TIMEOUT_SECONDS", "2400"))
    grace = float(os.environ.get("GATE_START_GRACE_SECONDS", "300"))

    changed = changed_files(repo, pr)
    expected = {}
    for name in WORKFLOWS:
        text = Path(f".github/workflows/{name}.yml").read_text()
        expected[name] = applies(pull_request_paths(text), changed)
        print(f"{name}: {'required' if expected[name] else 'not triggered by this PR'}", flush=True)

    start = time.monotonic()
    while True:
        waited = time.monotonic() - start
        results = {n: evaluate(expected[n], latest_run(repo, n, sha), waited, grace) for n in WORKFLOWS}
        failures = {n: r for n, r in results.items() if r not in ("pass", "wait")}
        if failures:
            for n, r in failures.items():
                print(f"::error::{n} {r}. Fix it or re-run it, then re-run this gate.")
            return 1
        if all(r == "pass" for r in results.values()):
            print("gate passed", flush=True)
            return 0
        if waited >= timeout:
            print(f"::error::timed out waiting for {[n for n, r in results.items() if r == 'wait']}")
            return 1
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    sys.exit(main())

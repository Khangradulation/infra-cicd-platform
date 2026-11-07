"""Integration tests against a DEPLOYED environment (run by deploy.yml on staging).

    BASE_URL=http://<alb-dns> EXPECTED_GIT_SHA=<sha> \
        pytest -m integration tests/integration --no-cov

Stdlib-only HTTP so the test runner needs nothing beyond pytest.
"""

from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.request

import pytest

pytestmark = pytest.mark.integration

BASE_URL = os.environ.get("BASE_URL", "").rstrip("/")
EXPECTED_SHA = os.environ.get("EXPECTED_GIT_SHA")
EXPECTED_ENV = os.environ.get("EXPECTED_ENV")

if not BASE_URL:
    pytest.skip("BASE_URL not set", allow_module_level=True)


def _get(path: str, timeout: float = 5.0) -> tuple[int, dict, dict]:
    req = urllib.request.Request(f"{BASE_URL}{path}", headers={"User-Agent": "icp-integration-tests"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, dict(resp.headers), json.loads(resp.read())
    except urllib.error.HTTPError as err:
        return err.code, dict(err.headers), json.loads(err.read() or b"{}")


def test_health():
    status, _, body = _get("/health")
    assert status == 200 and body == {"status": "ok"}


def test_version_matches_deployed_commit():
    status, _, body = _get("/version")
    assert status == 200
    if EXPECTED_SHA:
        assert body["git_sha"] == EXPECTED_SHA, f"serving {body['git_sha']}, expected {EXPECTED_SHA}"


def test_status_reports_environment():
    status, _, body = _get("/status")
    assert status == 200 and body["status"] == "ok"
    if EXPECTED_ENV:
        assert body["environment"] == EXPECTED_ENV


def test_unknown_route_returns_json_404_through_alb():
    status, headers, body = _get("/definitely-not-a-route")
    assert status == 404 and body["status"] == 404
    assert "X-Request-ID" in headers or "x-request-id" in {k.lower() for k in headers}


def test_latency_budget():
    samples = []
    for _ in range(10):
        t0 = time.perf_counter()
        status, _, _ = _get("/health")
        samples.append(time.perf_counter() - t0)
        assert status == 200
    samples.sort()
    p90 = samples[8]
    assert p90 < 1.0, f"p90 latency {p90:.3f}s exceeds 1s budget"

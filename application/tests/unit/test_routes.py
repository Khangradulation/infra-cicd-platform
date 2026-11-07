import json
import logging


def test_index(client):
    resp = client.get("/")
    assert resp.status_code == 200
    body = resp.get_json()
    assert body["environment"] == "test"
    assert set(body["endpoints"]) == {"/", "/health", "/version", "/status"}


def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json() == {"status": "ok"}


def test_version(client):
    assert client.get("/version").get_json() == {
        "version": "1.2.3",
        "git_sha": "abc1234",
        "build_time": "2026-01-01T00:00:00Z",
    }


def test_status(client):
    body = client.get("/status").get_json()
    assert body["status"] == "ok"
    assert body["version"] == "1.2.3"
    assert body["uptime_seconds"] >= 0
    assert body["python_version"].count(".") == 2


def test_security_headers_and_request_id(client):
    resp = client.get("/")
    assert resp.headers["X-Content-Type-Options"] == "nosniff"
    assert resp.headers["Cache-Control"] == "no-store"
    assert len(resp.headers["X-Request-ID"]) == 32


def test_incoming_request_id_is_propagated(client):
    resp = client.get("/", headers={"X-Request-ID": "trace-123"})
    assert resp.headers["X-Request-ID"] == "trace-123"


def test_oversized_request_id_is_replaced(client):
    resp = client.get("/", headers={"X-Request-ID": "x" * 500})
    assert resp.headers["X-Request-ID"] != "x" * 500


def test_404_is_json(client):
    resp = client.get("/nope")
    assert resp.status_code == 404
    body = resp.get_json()
    assert body["status"] == 404 and body["error"] == "Not Found"
    assert body["request_id"]


def test_405_is_json(client):
    resp = client.post("/health")
    assert resp.status_code == 405
    assert resp.get_json()["status"] == 405


def test_unhandled_exception_returns_generic_500_and_logs_error(client, caplog):
    with caplog.at_level(logging.ERROR, logger="app"):
        resp = client.get("/_boom")
    assert resp.status_code == 500
    body = resp.get_json()
    assert body["error"] == "Internal Server Error"
    assert "kaboom" not in json.dumps(body), "internal details must not leak to clients"
    assert any(r.levelname == "ERROR" and r.getMessage() == "unhandled_exception" for r in caplog.records)


def test_health_logged_at_debug_others_at_info(client, caplog):
    with caplog.at_level(logging.DEBUG, logger="app"):
        client.get("/health")
        client.get("/")
    levels = {r.path: r.levelname for r in caplog.records if r.getMessage() == "request"}
    assert levels == {"/health": "DEBUG", "/": "INFO"}

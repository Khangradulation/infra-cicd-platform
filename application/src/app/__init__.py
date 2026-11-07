"""Sample Flask API for the infra-cicd-platform.

Endpoints: GET /, /health, /version, /status. Every response is JSON and carries
an ``X-Request-ID`` header; every request is logged as one structured line.
"""

from __future__ import annotations

import logging
import platform
import time
import uuid

from flask import Flask, Response, g, jsonify, request
from werkzeug.exceptions import HTTPException
from werkzeug.middleware.proxy_fix import ProxyFix

from .config import Config
from .logging_config import configure_logging

__all__ = ["create_app"]

log = logging.getLogger("app")

# Paths probed by the ALB / ECS every few seconds: logged at DEBUG to keep logs useful.
_QUIET_PATHS = {"/health"}
_REQUEST_ID_MAX_LEN = 128


def create_app(config: Config | None = None) -> Flask:
    cfg = config or Config.from_env()
    configure_logging(cfg.log_level, {"service": cfg.app_name, "env": cfg.environment})

    app = Flask(__name__)
    app.config["APP"] = cfg
    app.json.sort_keys = False  # type: ignore[attr-defined]
    # Exactly one trusted proxy hop (the ALB) sets X-Forwarded-For/Proto.
    app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1)  # type: ignore[method-assign]
    started_at = time.monotonic()

    # ------------------------------------------------------------- hooks
    @app.before_request
    def _start_request() -> None:
        incoming = request.headers.get("X-Request-ID", "")
        g.request_id = (
            incoming
            if incoming and len(incoming) <= _REQUEST_ID_MAX_LEN and incoming.isprintable()
            else uuid.uuid4().hex
        )
        g.start = time.perf_counter()

    @app.after_request
    def _finish_request(response: Response) -> Response:
        response.headers["X-Request-ID"] = g.get("request_id", "")
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Cache-Control"] = "no-store"
        duration_ms = round((time.perf_counter() - g.get("start", time.perf_counter())) * 1000, 2)
        level = logging.DEBUG if request.path in _QUIET_PATHS and response.status_code < 400 else logging.INFO
        log.log(
            level,
            "request",
            extra={
                "request_id": g.get("request_id"),
                "method": request.method,
                "path": request.path,
                "status": response.status_code,
                "duration_ms": duration_ms,
                "client_ip": request.remote_addr,
                "user_agent": request.headers.get("User-Agent", "")[:200],
            },
        )
        return response

    # ------------------------------------------------------ error handling
    @app.errorhandler(HTTPException)
    def _http_error(exc: HTTPException):
        return jsonify(
            error=exc.name, message=exc.description, status=exc.code, request_id=g.get("request_id")
        ), exc.code

    @app.errorhandler(Exception)
    def _unhandled(exc: Exception):
        # Full traceback goes to the logs (ERROR -> CloudWatch metric filter); clients get no internals.
        log.exception("unhandled_exception", extra={"request_id": g.get("request_id"), "path": request.path})
        return jsonify(
            error="Internal Server Error",
            message="An unexpected error occurred.",
            status=500,
            request_id=g.get("request_id"),
        ), 500

    # ------------------------------------------------------------- routes
    @app.get("/")
    def index():
        return jsonify(
            service=cfg.app_name,
            environment=cfg.environment,
            message="infra-cicd-platform sample API",
            endpoints=["/", "/health", "/version", "/status"],
        )

    @app.get("/health")
    def health():
        # Liveness: must stay dependency-free and fast; used by ALB and container health checks.
        return jsonify(status="ok")

    @app.get("/version")
    def version():
        return jsonify(version=cfg.version, git_sha=cfg.git_sha, build_time=cfg.build_time)

    @app.get("/status")
    def status():
        return jsonify(
            status="ok",
            service=cfg.app_name,
            environment=cfg.environment,
            version=cfg.version,
            git_sha=cfg.git_sha,
            uptime_seconds=round(time.monotonic() - started_at, 3),
            python_version=platform.python_version(),
        )

    log.info("app_started", extra={"version": cfg.version, "git_sha": cfg.git_sha})
    return app

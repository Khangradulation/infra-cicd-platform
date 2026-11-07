"""Structured (JSON lines) logging.

One JSON object per line on stdout. CloudWatch Logs metric filters match on
fields such as ``level`` and ``status`` (see terraform/modules/monitoring).
"""

from __future__ import annotations

import json
import logging
import sys
from datetime import UTC, datetime
from typing import Any

# Attributes every LogRecord has; anything else passed via `extra=` is emitted as a field.
_RESERVED = set(logging.makeLogRecord({}).__dict__) | {"message", "asctime", "taskName"}

# Never emit these keys even if a caller passes them in `extra=`.
_REDACT_KEYS = {"authorization", "cookie", "password", "secret", "token", "api_key", "set-cookie"}


class JsonFormatter(logging.Formatter):
    def __init__(self, static_fields: dict[str, Any] | None = None) -> None:
        super().__init__()
        self._static = static_fields or {}

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "timestamp": datetime.fromtimestamp(record.created, tz=UTC).isoformat(timespec="milliseconds"),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            **self._static,
        }
        for key, value in record.__dict__.items():
            if key in _RESERVED or key.startswith("_"):
                continue
            payload[key] = "[REDACTED]" if key.lower() in _REDACT_KEYS else value
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload, default=str, separators=(",", ":"))


def configure_logging(level: str, static_fields: dict[str, Any] | None = None) -> None:
    """Route root and gunicorn loggers through a single JSON stdout handler."""
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter(static_fields))

    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(level)

    for name in ("gunicorn.error", "gunicorn.access", "werkzeug"):
        lg = logging.getLogger(name)
        lg.handlers[:] = []
        lg.propagate = True

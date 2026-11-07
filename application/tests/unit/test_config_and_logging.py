import json
import logging
import sys

import pytest

from app.config import Config, ConfigError
from app.logging_config import JsonFormatter


def test_defaults():
    cfg = Config.from_env({})
    assert cfg.environment == "local"
    assert cfg.log_level == "INFO"
    assert cfg.version == "0.0.0-dev"


def test_normalises_values():
    cfg = Config.from_env({"APP_ENV": " Staging ", "LOG_LEVEL": "debug"})
    assert cfg.environment == "staging"
    assert cfg.log_level == "DEBUG"


@pytest.mark.parametrize("bad", ["verbose", "TRACE", ""])
def test_rejects_invalid_log_level(bad):
    with pytest.raises(ConfigError):
        Config.from_env({"LOG_LEVEL": bad})


def test_rejects_invalid_environment():
    with pytest.raises(ConfigError):
        Config.from_env({"APP_ENV": "prod; rm -rf"})


def test_from_os_environ(monkeypatch):
    monkeypatch.setenv("APP_ENV", "dev")
    monkeypatch.setenv("APP_VERSION", "9.9.9")
    assert Config.from_env().version == "9.9.9"


def _record(**extra):
    rec = logging.LogRecord("app", logging.INFO, __file__, 1, "hello %s", ("world",), None)
    for k, v in extra.items():
        setattr(rec, k, v)
    return rec


def test_json_formatter_emits_one_json_object_with_extras():
    line = JsonFormatter({"service": "svc"}).format(_record(status=200, path="/"))
    payload = json.loads(line)
    assert payload["message"] == "hello world"
    assert payload["level"] == "INFO"
    assert payload["service"] == "svc"
    assert payload["status"] == 200
    assert "\n" not in line


def test_json_formatter_redacts_sensitive_keys():
    payload = json.loads(JsonFormatter().format(_record(authorization="Bearer x", token="t")))
    assert payload["authorization"] == "[REDACTED]"
    assert payload["token"] == "[REDACTED]"


def test_json_formatter_includes_exception():
    try:
        raise ValueError("bad")
    except ValueError:
        rec = logging.LogRecord("app", logging.ERROR, __file__, 1, "oops", (), sys.exc_info())
    payload = json.loads(JsonFormatter().format(rec))
    assert "ValueError: bad" in payload["exception"]

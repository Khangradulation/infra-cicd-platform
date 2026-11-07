"""Environment-based configuration.

All settings come from environment variables so the same image runs unchanged in
every environment; ECS injects per-environment values from the task definition.
"""

from __future__ import annotations

import os
from dataclasses import dataclass

_VALID_LOG_LEVELS = {"DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"}


class ConfigError(ValueError):
    """Raised when an environment variable holds an invalid value."""


@dataclass(frozen=True)
class Config:
    app_name: str
    environment: str
    log_level: str
    version: str
    git_sha: str
    build_time: str

    @classmethod
    def from_env(cls, env: dict[str, str] | None = None) -> Config:
        source = os.environ if env is None else env

        log_level = source.get("LOG_LEVEL", "INFO").strip().upper()
        if log_level not in _VALID_LOG_LEVELS:
            raise ConfigError(f"LOG_LEVEL must be one of {sorted(_VALID_LOG_LEVELS)}, got {log_level!r}")

        environment = source.get("APP_ENV", "local").strip().lower()
        if not environment or not environment.replace("-", "").isalnum():
            raise ConfigError(f"APP_ENV must be alphanumeric (hyphens allowed), got {environment!r}")

        return cls(
            app_name=source.get("APP_NAME", "icp-api").strip() or "icp-api",
            environment=environment,
            log_level=log_level,
            version=source.get("APP_VERSION", "0.0.0-dev").strip() or "0.0.0-dev",
            git_sha=source.get("GIT_SHA", "unknown").strip() or "unknown",
            build_time=source.get("BUILD_TIME", "unknown").strip() or "unknown",
        )

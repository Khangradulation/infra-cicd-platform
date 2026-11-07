import pytest

from app import create_app
from app.config import Config


@pytest.fixture
def config() -> Config:
    return Config.from_env(
        {
            "APP_ENV": "test",
            "LOG_LEVEL": "DEBUG",
            "APP_VERSION": "1.2.3",
            "GIT_SHA": "abc1234",
            "BUILD_TIME": "2026-01-01T00:00:00Z",
        }
    )


@pytest.fixture
def app(config):
    application = create_app(config)

    # Test-only route to exercise the unhandled-exception path.
    @application.get("/_boom")
    def boom():
        raise RuntimeError("kaboom secret-internal-detail")

    application.config.update(TESTING=False, PROPAGATE_EXCEPTIONS=False)
    return application


@pytest.fixture
def client(app):
    return app.test_client()

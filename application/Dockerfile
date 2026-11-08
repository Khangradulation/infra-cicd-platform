# syntax=docker/dockerfile:1
#
# Multi-stage build:
#   build   - create a venv and install hash-locked dependencies
#   runtime - same digest-pinned slim base, venv + source only, no pip, non-root
#
# The base image is pinned by digest for reproducibility; Dependabot (docker
# ecosystem) proposes digest bumps. See docs/upgrades.md.
ARG PYTHON_IMAGE=python:3.14-slim-trixie@sha256:9aaa474097d094040649f2162a627c0049b408f52138d980916788d80f04802f

# --------------------------------------------------------------- build
FROM ${PYTHON_IMAGE} AS build

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /build
COPY requirements.txt .

# --require-hashes: every wheel must match the lock file; --no-deps: nothing unlisted sneaks in.
RUN python -m venv /opt/venv \
 && /opt/venv/bin/pip install --require-hashes --no-deps -r requirements.txt \
 && /opt/venv/bin/pip uninstall -y pip \
 && find /opt/venv -type d -name __pycache__ -prune -exec rm -rf {} +

# ------------------------------------------------------------- runtime
FROM ${PYTHON_IMAGE} AS runtime

ARG APP_VERSION=0.0.0-dev
ARG GIT_SHA=unknown
ARG BUILD_TIME=unknown

LABEL org.opencontainers.image.title="icp-api" \
      org.opencontainers.image.description="infra-cicd-platform sample Flask API" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.created="${BUILD_TIME}"

ENV PATH="/opt/venv/bin:${PATH}" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080 \
    APP_VERSION="${APP_VERSION}" \
    GIT_SHA="${GIT_SHA}" \
    BUILD_TIME="${BUILD_TIME}"

# Unprivileged user with a fixed UID (matches nothing on the host); remove the
# system pip/setuptools so the runtime image can't install anything.
RUN groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin app \
 && { python -m pip uninstall -y pip setuptools wheel 2>/dev/null || true; } \
 && rm -rf /root/.cache /usr/local/lib/python3*/ensurepip

COPY --from=build /opt/venv /opt/venv

# ECS mounts an ephemeral volume at /tmp (the root FS is read-only). Fargate
# copies the image directory's ownership/mode onto that volume only when the
# path is declared as a VOLUME; without this it is root:root 0755 and the
# non-root app cannot write (gunicorn worker heartbeat files live there).
RUN chmod 1777 /tmp
VOLUME ["/tmp"]

WORKDIR /app
COPY --chown=root:root gunicorn.conf.py ./
COPY --chown=root:root src/ ./src/
RUN chmod -R a+rX,go-w /app

USER 10001:10001
EXPOSE 8080

# Same probe ECS uses (container health check in the task definition).
HEALTHCHECK --interval=15s --timeout=5s --start-period=15s --retries=3 \
  CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=3)"]

ENTRYPOINT ["gunicorn", "--config", "/app/gunicorn.conf.py", "--chdir", "/app/src", "app:create_app()"]

# icp-api: sample Flask application

| Endpoint | Purpose | Example response |
|---|---|---|
| `GET /` | Service info | `{"service":"icp-api","environment":"dev",...}` |
| `GET /health` | Liveness for ALB and container health checks. Dependency-free, logged at DEBUG. | `{"status":"ok"}` |
| `GET /version` | Build identity, used by deploys to verify which commit is serving | `{"version":"…","git_sha":"…","build_time":"…"}` |
| `GET /status` | Runtime status | `{"status":"ok","uptime_seconds":12.3,...}` |

Errors are JSON (`404`, `405`, and a generic `500` that never leaks internals). Every
response carries `X-Request-ID`. That's the incoming header if it's sane, otherwise a
generated one.

## Configuration (environment variables)

| Variable | Default | Notes |
|---|---|---|
| `APP_ENV` | `local` | Set by Terraform per environment |
| `LOG_LEVEL` | `INFO` | `DEBUG` / `INFO` / `WARNING` / `ERROR` / `CRITICAL`. An invalid value fails startup. |
| `APP_NAME` | `icp-api` | |
| `APP_VERSION`, `GIT_SHA`, `BUILD_TIME` | dev values | Baked in at build time (`--build-arg`) |
| `PORT` | `8080` | gunicorn bind port |
| `GUNICORN_WORKERS` / `GUNICORN_THREADS` | `2` / `4` | |

## Logging

The app writes one JSON object per line to stdout. ECS ships it to CloudWatch, where
metric filters count `level=ERROR|CRITICAL` and `status>=500`:

```json
{"timestamp":"2026-11-07T04:39:46.120+00:00","level":"INFO","logger":"app","message":"request","service":"icp-api","env":"dev","request_id":"…","method":"GET","path":"/","status":200,"duration_ms":0.41}
```

Keys such as `authorization`, `token`, and `password` are redacted if they're passed as log fields.

## Local development

```bash
make venv          # python3 -m venv + hash-locked dev deps
make app-lint      # ruff check + format check
make app-test      # pytest, coverage gate 90%
make app-run       # flask dev server on http://127.0.0.1:8080
```

Container (same hardening as ECS: read-only root FS, `/tmp` tmpfs, all capabilities
dropped, UID 10001):

```bash
make docker-build docker-smoke trivy
```

Integration tests run against a deployed URL (deploy.yml runs them on staging):

```bash
BASE_URL=http://<alb-dns> EXPECTED_GIT_SHA=<sha> .venv/bin/pytest tests/integration -m integration --no-cov
```

## Dependencies

Direct dependencies are in `requirements.in` and `requirements-dev.in`. They're locked with
hashes using [uv](https://github.com/astral-sh/uv):

```bash
uv pip compile --generate-hashes --python-version 3.14 requirements.in -o requirements.txt
uv pip compile --generate-hashes --python-version 3.14 requirements-dev.in -o requirements-dev.txt
```

The Docker build installs with `--require-hashes --no-deps`, so an unlocked or tampered
package fails the build.
<!-- temporary: pr-gate test -->

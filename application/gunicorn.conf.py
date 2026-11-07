"""Gunicorn settings (production server inside the container)."""

import os

bind = f"0.0.0.0:{os.environ.get('PORT', '8080')}"
workers = int(os.environ.get("GUNICORN_WORKERS", "2"))
threads = int(os.environ.get("GUNICORN_THREADS", "4"))
worker_class = "gthread"
timeout = 30
# ECS sends SIGTERM and waits stopTimeout (30s default) before SIGKILL; finish in-flight requests first.
graceful_timeout = 20
keepalive = 75  # > ALB idle timeout (60s) avoids 502s from connections closed under the ALB
worker_tmp_dir = "/tmp"  # noqa: S108 - root FS is read-only; /tmp is an ephemeral volume
accesslog = None  # the app logs each request as structured JSON
errorlog = "-"
loglevel = os.environ.get("LOG_LEVEL", "info").lower()
forwarded_allow_ips = "*"  # only the ALB can reach the task (security group)
max_requests = 5000
max_requests_jitter = 500

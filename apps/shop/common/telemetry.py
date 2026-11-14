"""Shared Prometheus metrics middleware + helpers for the shop services.

Tracing is done by OpenTelemetry auto-instrumentation (`opentelemetry-instrument` in the
Dockerfile). It is OFF by default (OTEL_TRACES_EXPORTER=none) and switched on in L300 by
setting OTEL_TRACES_EXPORTER=otlp and OTEL_EXPORTER_OTLP_ENDPOINT.
"""
import os
import time

from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

SERVICE = os.getenv("OTEL_SERVICE_NAME", "shop")
VERSION = os.getenv("APP_VERSION", "v1")

REQUESTS = Counter(
    "http_requests_total", "HTTP requests", ["service", "route", "method", "status"]
)
LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency",
    ["service", "route", "method"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5),
)


class MetricsMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        start = time.perf_counter()
        status = 500
        try:
            response = await call_next(request)
            status = response.status_code
            return response
        finally:
            route = request.scope.get("route")
            path = getattr(route, "path", "unmatched")
            if path not in ("/metrics", "/healthz", "/readyz"):
                LATENCY.labels(SERVICE, path, request.method).observe(time.perf_counter() - start)
                REQUESTS.labels(SERVICE, path, request.method, str(status)).inc()


def metrics_response() -> Response:
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


def pod_info() -> dict:
    """Values injected with the Downward API (see k8s/apps/shop/base)."""
    return {
        "service": SERVICE,
        "version": VERSION,
        "pod": os.getenv("POD_NAME", os.uname().nodename),
        "namespace": os.getenv("POD_NAMESPACE", "unknown"),
        "node": os.getenv("NODE_NAME", "unknown"),
        "pod_ip": os.getenv("POD_IP", "unknown"),
    }

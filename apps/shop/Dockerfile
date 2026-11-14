# One Dockerfile for all three services:  docker build --build-arg SERVICE=api .
FROM python:3.13-slim AS base

ARG SERVICE=api
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    OTEL_SERVICE_NAME=shop-${SERVICE} \
    OTEL_TRACES_EXPORTER=none \
    OTEL_METRICS_EXPORTER=none \
    OTEL_LOGS_EXPORTER=none \
    OTEL_PYTHON_EXCLUDED_URLS="healthz,readyz,metrics" \
    SERVICE=${SERVICE}

WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt

COPY common/ ./
COPY ${SERVICE}/ ./

# Non-root, numeric UID so PodSecurity "restricted" + runAsNonRoot work (L400)
RUN useradd --uid 10001 --no-create-home app
USER 10001
EXPOSE 8080

# exec form via sh so ${SERVICE} expands; `exec` makes the app PID 1 for clean SIGTERM handling
CMD ["sh", "-c", "if [ \"$SERVICE\" = worker ]; then exec opentelemetry-instrument python main.py; else exec opentelemetry-instrument uvicorn main:app --host 0.0.0.0 --port 8080 --timeout-graceful-shutdown 20; fi"]

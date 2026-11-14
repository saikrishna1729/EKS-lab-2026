# Sample app: shop

```
 browser ──► shop-web ──► shop-api ──► SQS (from L300) ──► shop-worker
                              │
                              └──► S3 (Pod Identity demo, L200)
```

| Service | Port | Notes |
|---|---|---|
| `shop-web` | 8080 | Server-rendered page that shows which pod/node/version answered |
| `shop-api` | 8080 | Items/orders API + lab helpers (`/api/burn`, `/api/slow`, `/api/s3check`, `ERROR_RATE`, `EXTRA_LATENCY_MS`) |
| `shop-worker` | 8080 (metrics only) | Consumes the SQS queue; graceful SIGTERM handling |

All services expose `/healthz`, `/readyz`, and `/metrics` (Prometheus). Tracing uses OpenTelemetry
auto-instrumentation; it is off until L300 switches it on with environment variables.

Run locally:
```bash
cd apps/shop
docker build --build-arg SERVICE=api -t shop-api . && docker run --rm -p 8080:8080 shop-api
curl localhost:8080/api/whoami
```

Build and push all three to ECR (multi-arch, so they run on Graviton and x86 nodes):
```bash
make images            # tag = git short SHA (or a timestamp before the first commit)
```

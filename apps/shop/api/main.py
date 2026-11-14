"""shop-api: the backend used throughout the lab.

Endpoints are deliberately "lab-friendly": some exist only so you can practise
autoscaling, SLO alerts, canary analysis, Pod Identity and failure handling.
"""
import json
import logging
import os
import random
import threading
import time
import uuid

import boto3
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from telemetry import MetricsMiddleware, metrics_response, pod_info

logging.basicConfig(level=logging.INFO, format='{"level":"%(levelname)s","msg":"%(message)s"}')
log = logging.getLogger("shop-api")

QUEUE_URL = os.getenv("QUEUE_URL", "")
S3_BUCKET = os.getenv("S3_BUCKET", "")
# Fraction of /api/* requests that fail with 500 — used to make a canary fail analysis.
ERROR_RATE = float(os.getenv("ERROR_RATE", "0"))
# Extra latency added to /api/* requests (ms) — used for latency SLO exercises.
EXTRA_LATENCY_MS = int(os.getenv("EXTRA_LATENCY_MS", "0"))

app = FastAPI(title="shop-api")
app.add_middleware(MetricsMiddleware)

_items: list[dict] = [{"id": "1", "name": "kubernetes sticker", "price": 2.5}]
_lock = threading.Lock()
_ready = {"ok": True}
_sqs = boto3.client("sqs") if QUEUE_URL else None


class Item(BaseModel):
    name: str
    price: float


class Order(BaseModel):
    item_id: str
    quantity: int = 1


def _chaos():
    if EXTRA_LATENCY_MS:
        time.sleep(EXTRA_LATENCY_MS / 1000)
    if ERROR_RATE and random.random() < ERROR_RATE:
        raise HTTPException(status_code=500, detail="injected error (ERROR_RATE)")


# ---- probes & metrics -------------------------------------------------------
@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/readyz")
def readyz():
    if not _ready["ok"]:
        return JSONResponse({"status": "not-ready"}, status_code=503)
    return {"status": "ready"}


@app.get("/metrics")
def metrics():
    return metrics_response()


# ---- business endpoints ------------------------------------------------------
@app.get("/api/whoami")
def whoami():
    return pod_info()


@app.get("/api/items")
def list_items():
    _chaos()
    with _lock:
        return list(_items)


@app.post("/api/items", status_code=201)
def add_item(item: Item):
    _chaos()
    new = {"id": str(uuid.uuid4())[:8], **item.model_dump()}
    with _lock:
        _items.append(new)
    log.info(f"item added {new['id']}")
    return new


@app.post("/api/orders", status_code=202)
def create_order(order: Order):
    _chaos()
    order_id = str(uuid.uuid4())
    body = {"order_id": order_id, **order.model_dump()}
    if _sqs:
        _sqs.send_message(QueueUrl=QUEUE_URL, MessageBody=json.dumps(body))
        log.info(f"order {order_id} queued")
        return {"order_id": order_id, "status": "queued"}
    log.info(f"order {order_id} processed inline (no QUEUE_URL)")
    return {"order_id": order_id, "status": "processed-inline"}


# ---- lab helpers -------------------------------------------------------------
@app.get("/api/s3check")
def s3check():
    """L200 Pod Identity lab: succeeds only if the pod's IAM role can list the bucket."""
    if not S3_BUCKET:
        raise HTTPException(400, "S3_BUCKET not set")
    try:
        s3 = boto3.client("s3")
        resp = s3.list_objects_v2(Bucket=S3_BUCKET, MaxKeys=5)
        ident = boto3.client("sts").get_caller_identity()["Arn"]
        return {"bucket": S3_BUCKET, "identity": ident,
                "keys": [o["Key"] for o in resp.get("Contents", [])]}
    except Exception as e:  # noqa: BLE001 - surface the AWS error to the learner
        raise HTTPException(403, f"{type(e).__name__}: {e}")


@app.get("/api/burn")
def burn(seconds: float = 0.5):
    """Burn CPU so the HPA / Karpenter have something to react to."""
    end = time.time() + min(seconds, 5)
    x = 0
    while time.time() < end:
        x += random.random() ** 2
    return {"burned_seconds": seconds}


@app.get("/api/slow")
def slow(ms: int = 500):
    time.sleep(min(ms, 10000) / 1000)
    return {"slept_ms": ms}


@app.post("/admin/readiness/{state}")
def set_readiness(state: str):
    """Flip readiness to practise how Services drop not-ready endpoints."""
    _ready["ok"] = state == "on"
    return {"ready": _ready["ok"]}

"""shop-worker: consumes orders from SQS. KEDA scales it on queue depth in L300.

Exposes /healthz and /metrics on :8080 from a background HTTP server and shuts down
gracefully on SIGTERM (finishes the in-flight message) — important for Spot interruptions
and Karpenter consolidation.
"""
import json
import logging
import os
import signal
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

import boto3
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

logging.basicConfig(level=logging.INFO, format='{"level":"%(levelname)s","msg":"%(message)s"}')
log = logging.getLogger("shop-worker")

QUEUE_URL = os.getenv("QUEUE_URL", "")
PROCESS_MS = int(os.getenv("PROCESS_MS", "200"))

PROCESSED = Counter("orders_processed_total", "Orders processed", ["result"])
DURATION = Histogram("order_processing_seconds", "Order processing time")

stop = threading.Event()


def _graceful(signum, _frame):
    log.info(f"signal {signum} received, finishing current message then exiting")
    stop.set()


signal.signal(signal.SIGTERM, _graceful)
signal.signal(signal.SIGINT, _graceful)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):  # noqa: N802
        if self.path == "/metrics":
            body, ctype = generate_latest(), CONTENT_TYPE_LATEST
        elif self.path in ("/healthz", "/readyz"):
            body, ctype = b'{"status":"ok"}', "application/json"
        else:
            self.send_response(404)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


def serve_http():
    HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()


def main():
    threading.Thread(target=serve_http, daemon=True).start()
    if not QUEUE_URL:
        log.info("QUEUE_URL not set — idling (orders are processed inline by shop-api)")
        stop.wait()
        return
    sqs = boto3.client("sqs")
    log.info(f"polling {QUEUE_URL}")
    while not stop.is_set():
        resp = sqs.receive_message(QueueUrl=QUEUE_URL, MaxNumberOfMessages=1, WaitTimeSeconds=10)
        for msg in resp.get("Messages", []):
            with DURATION.time():
                try:
                    order = json.loads(msg["Body"])
                    time.sleep(PROCESS_MS / 1000)  # pretend to do work
                    sqs.delete_message(QueueUrl=QUEUE_URL, ReceiptHandle=msg["ReceiptHandle"])
                    PROCESSED.labels("ok").inc()
                    log.info(f"processed order {order.get('order_id')}")
                except Exception as e:  # noqa: BLE001
                    PROCESSED.labels("error").inc()
                    log.error(f"failed: {e}")
    log.info("worker stopped cleanly")


if __name__ == "__main__":
    main()

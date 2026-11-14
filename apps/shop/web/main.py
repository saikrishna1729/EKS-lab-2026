"""shop-web: a tiny server-rendered UI that calls shop-api.

It makes the request path web → api visible in traces and lets you see which
pod / node / version answered.
"""
import html
import os

import httpx
from fastapi import FastAPI, Form
from fastapi.responses import HTMLResponse, RedirectResponse

from telemetry import MetricsMiddleware, metrics_response, pod_info

API_URL = os.getenv("API_URL", "http://shop-api:8080")

app = FastAPI(title="shop-web")
app.add_middleware(MetricsMiddleware)
client = httpx.Client(base_url=API_URL, timeout=5.0)


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/readyz")
def readyz():
    return {"status": "ready"}


@app.get("/metrics")
def metrics():
    return metrics_response()


def _get(path):
    try:
        r = client.get(path)
        r.raise_for_status()
        return r.json(), None
    except Exception as e:  # noqa: BLE001
        return None, f"{type(e).__name__}: {e}"


@app.get("/", response_class=HTMLResponse)
def index():
    me = pod_info()
    api, api_err = _get("/api/whoami")
    items, items_err = _get("/api/items")
    rows = "".join(
        f"<tr><td>{html.escape(i['id'])}</td><td>{html.escape(i['name'])}</td>"
        f"<td>{i['price']:.2f}</td><td><form method=post action=/order>"
        f"<input type=hidden name=item_id value='{html.escape(i['id'])}'>"
        f"<button>order</button></form></td></tr>"
        for i in (items or [])
    )
    err = "".join(f"<p class=err>{html.escape(e)}</p>" for e in (api_err, items_err) if e)
    return f"""<!doctype html><html><head><meta charset=utf-8><title>EKS Lab Shop</title>
<style>body{{font-family:system-ui;max-width:760px;margin:2rem auto;padding:0 1rem}}
td,th{{padding:.3rem .6rem;border-bottom:1px solid #ddd}} .err{{color:#b00}}
code{{background:#f3f3f3;padding:.1rem .3rem}}</style></head><body>
<h1>EKS Lab Shop</h1>
<p>web: <code>{me['pod']}</code> on <code>{me['node']}</code> ({me['version']})<br>
api: <code>{(api or {}).get('pod','?')}</code> on <code>{(api or {}).get('node','?')}</code>
({(api or {}).get('version','?')})</p>{err}
<table><tr><th>id</th><th>item</th><th>price</th><th></th></tr>{rows}</table>
<h3>Add item</h3><form method=post action=/item>
<input name=name placeholder=name required> <input name=price type=number step=0.01 required>
<button>add</button></form></body></html>"""


@app.post("/item")
def add_item(name: str = Form(...), price: float = Form(...)):
    client.post("/api/items", json={"name": name, "price": price})
    return RedirectResponse("/", status_code=303)


@app.post("/order")
def order(item_id: str = Form(...)):
    client.post("/api/orders", json={"item_id": item_id})
    return RedirectResponse("/", status_code=303)

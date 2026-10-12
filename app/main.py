"""Tiny versioned service. FAIL_HEALTH=1 simulates a bad release (healthz 500)."""
import os
from fastapi import FastAPI, Response

VERSION = os.getenv("APP_VERSION", "dev")
COLOR = os.getenv("APP_COLOR", "none")
app = FastAPI()

@app.get("/healthz")
def healthz(resp: Response):
    if os.getenv("FAIL_HEALTH") == "1":
        resp.status_code = 500
        return {"ok": False, "version": VERSION}
    return {"ok": True, "version": VERSION, "color": COLOR}

@app.get("/")
def root():
    return {"service": "orders", "version": VERSION, "color": COLOR}

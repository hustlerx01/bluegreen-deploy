#!/usr/bin/env bash
STATE="${STATE_DIR:-$PWD/.bg}"
for f in "$STATE"/app-*.pid; do [[ -f $f ]] && kill "$(cat "$f")" 2>/dev/null; done
[[ -f "$STATE/nginx.pid" ]] && nginx -c "$STATE/nginx.conf" -p "$STATE" -s quit 2>/dev/null
docker rm -f app-blue app-green >/dev/null 2>&1 || true
pkill -f "uvicorn main:app --host 127.0.0.1 --port" 2>/dev/null || true
rm -rf "$STATE"

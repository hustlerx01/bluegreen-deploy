#!/usr/bin/env bash
# Blue-green deploy with health-gated switch and automatic rollback.
# Usage: deploy.sh <version> [--fail-health]
# MODE=local (uvicorn processes, used in CI/lab) or MODE=docker (containers).
set -euo pipefail
VERSION="${1:?version}"; FAIL="${2:-}"
MODE="${MODE:-local}"
STATE="${STATE_DIR:-$PWD/.bg}"; LB_PORT="${LB_PORT:-8080}"
declare -A PORT=([blue]=${BLUE_PORT:-8001} [green]=${GREEN_PORT:-8002})
HC_RETRIES="${HC_RETRIES:-10}"; HC_INTERVAL="${HC_INTERVAL:-0.5}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$STATE/tmp"
log(){ echo "$(date -u +%H:%M:%S) [deploy] $*" | tee -a "$STATE/deploy.log"; }

render_upstream(){ printf 'upstream app_active { server 127.0.0.1:%s; }\n' "${PORT[$1]}" > "$STATE/upstream_active.conf.new"
  mv "$STATE/upstream_active.conf.new" "$STATE/upstream_active.conf"; echo "$1" > "$STATE/active"; }

ensure_nginx(){
  if [[ ! -f "$STATE/nginx.pid" ]] || ! kill -0 "$(cat "$STATE/nginx.pid")" 2>/dev/null; then
    sed -e "s#__PREFIX__#$STATE#g" -e "s#__LB_PORT__#$LB_PORT#g" "$ROOT/nginx/nginx.conf.tmpl" > "$STATE/nginx.conf"
    [[ -f "$STATE/upstream_active.conf" ]] || printf 'upstream app_active { server 127.0.0.1:%s; }\n' "${PORT[blue]}" > "$STATE/upstream_active.conf"
    nginx -c "$STATE/nginx.conf" -p "$STATE" -t -q && nginx -c "$STATE/nginx.conf" -p "$STATE"
    log "nginx started on :$LB_PORT"
  fi
}
reload_nginx(){ nginx -c "$STATE/nginx.conf" -p "$STATE" -t -q && nginx -c "$STATE/nginx.conf" -p "$STATE" -s reload 2>/dev/null; }

start_color(){ local c=$1 p=${PORT[$1]}; stop_color "$c"
  local extra=(); [[ "$FAIL" == "--fail-health" ]] && extra=(FAIL_HEALTH=1)
  if [[ "$MODE" == docker ]]; then
    docker run -d --name "app-$c" -p "127.0.0.1:$p:8000" -e APP_COLOR="$c" -e APP_VERSION="$VERSION" \
      ${extra:+-e "${extra[0]}"} "orders:$VERSION" >/dev/null
  else
    (cd "$ROOT/app"; exec env APP_COLOR="$c" APP_VERSION="$VERSION" "${extra[@]}" \
      nohup "${PYTHON:-python3}" -m uvicorn main:app --host 127.0.0.1 --port "$p" >"$STATE/app-$c.log" 2>&1 & echo $! > "$STATE/app-$c.pid")
  fi; }
stop_color(){ local c=$1
  if [[ "$MODE" == docker ]]; then docker rm -f "app-$c" >/dev/null 2>&1 || true
  elif [[ -f "$STATE/app-$c.pid" ]]; then kill "$(cat "$STATE/app-$c.pid")" 2>/dev/null || true; rm -f "$STATE/app-$c.pid"; fi
  for _ in $(seq 50); do curl -s -m 1 "127.0.0.1:${PORT[$c]}" >/dev/null || return 0; sleep 0.1; done; }  # wait until port is free

healthy(){ local url=$1 want=$2 i body
  for ((i=1;i<=HC_RETRIES;i++)); do
    body=$(curl -fsS -m 2 "$url" 2>/dev/null) && grep -q "\"version\":\"$want\"" <<<"$body" && return 0
    sleep "$HC_INTERVAL"; done; return 1; }

ensure_nginx
ACTIVE=$(cat "$STATE/active" 2>/dev/null || echo none)
if [[ "$ACTIVE" == blue ]]; then IDLE=green; else IDLE=blue; fi
[[ "$ACTIVE" == none ]] && ACTIVE=""
log "deploying $VERSION to $IDLE (active=${ACTIVE:-none})"
start_color "$IDLE"
if ! healthy "http://127.0.0.1:${PORT[$IDLE]}/healthz" "$VERSION"; then
  log "PRE-SWITCH health check FAILED for $IDLE/$VERSION -> rollback (traffic never moved)"
  stop_color "$IDLE"; echo "rollback" > "$STATE/last_result"; exit 1
fi
render_upstream "$IDLE"; reload_nginx
log "switched traffic to $IDLE"
if ! healthy "http://127.0.0.1:$LB_PORT/healthz" "$VERSION"; then
  log "POST-SWITCH smoke FAILED -> reverting to ${ACTIVE:-none}"
  [[ -n "$ACTIVE" ]] && { render_upstream "$ACTIVE"; reload_nginx; }
  stop_color "$IDLE"; echo "rollback" > "$STATE/last_result"; exit 1
fi
sleep "${DRAIN_SECONDS:-1}"   # let in-flight requests to old color finish
[[ -n "$ACTIVE" ]] && stop_color "$ACTIVE"
echo "success" > "$STATE/last_result"; log "deploy $VERSION OK, active=$IDLE"

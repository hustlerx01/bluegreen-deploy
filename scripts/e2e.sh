#!/usr/bin/env bash
# v1 -> blue, v2 -> green under load, v3 (broken) -> rollback, v4 -> blue
set -uo pipefail
cd "$(dirname "$0")/.."; export STATE_DIR=$PWD/.bg; PY="${PYTHON:-python3}"; export PYTHON=$PY
scripts/teardown.sh
fail=0; check(){ if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }
scripts/deploy.sh v1 >/dev/null;               check "v1 deployed to blue" '[[ $(cat .bg/active) == blue ]]'
$PY scripts/traffic.py http://127.0.0.1:8080/ 6 > .bg/traffic.json & T=$!
sleep 1; scripts/deploy.sh v2 >/dev/null;      check "v2 switched to green" '[[ $(cat .bg/active) == green ]]'
wait $T; cat .bg/traffic.json
check "zero failed requests during switch" '[[ $($PY -c "import json;print(json.load(open(\".bg/traffic.json\"))[\"errors\"])") == 0 ]]'
scripts/deploy.sh v3 --fail-health >/dev/null; rc=$?
check "broken v3 exits non-zero" '[[ $rc -ne 0 ]]'
check "traffic still on green/v2" 'curl -fsS localhost:8080/ | grep -q "\"version\":\"v2\""'
check "last_result=rollback" '[[ $(cat .bg/last_result) == rollback ]]'
scripts/deploy.sh v4 >/dev/null;               check "v4 to blue after rollback" 'curl -fsS localhost:8080/ | grep -q "\"version\":\"v4\""'
cp .bg/deploy.log results/deploy.log 2>/dev/null
scripts/teardown.sh; exit $fail

"""Hammer the LB during deploys; report error count and version mix (zero-downtime proof)."""
import json, sys, time, urllib.request, collections
url, seconds = sys.argv[1], float(sys.argv[2])
ok = err = 0; versions = collections.Counter(); end = time.time() + seconds
while time.time() < end:
    try:
        with urllib.request.urlopen(url, timeout=2) as r:
            versions[json.load(r)["version"]] += 1; ok += 1
    except Exception:
        err += 1
    time.sleep(0.01)
print(json.dumps({"requests": ok + err, "errors": err, "versions": versions}))

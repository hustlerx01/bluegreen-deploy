import importlib, subprocess, shutil, os, sys
from pathlib import Path
import pytest
from fastapi.testclient import TestClient
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "app"))

def client(monkeypatch, **env):
    for k, v in env.items(): monkeypatch.setenv(k, v)
    import main; importlib.reload(main); return TestClient(main.app)

def test_health_ok(monkeypatch):
    r = client(monkeypatch, APP_VERSION="v9").get("/healthz")
    assert r.status_code == 200 and r.json()["version"] == "v9"

def test_health_fail_flag(monkeypatch):
    assert client(monkeypatch, FAIL_HEALTH="1").get("/healthz").status_code == 500

@pytest.mark.skipif(not shutil.which("nginx"), reason="nginx not installed")
def test_e2e_blue_green_and_rollback():
    env = dict(os.environ, PYTHON=sys.executable)
    p = subprocess.run(["bash", "scripts/e2e.sh"], cwd=ROOT, capture_output=True, text=True, env=env, timeout=120)
    print(p.stdout)
    assert p.returncode == 0, p.stdout + p.stderr

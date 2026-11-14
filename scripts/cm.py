"""Codemagic helper: start a build, wait for it, print errors or download the IPA.

Usage:
  python scripts/cm.py build          start a build on main and wait for it
  python scripts/cm.py wait BUILD_ID  wait for an existing build

The API token is read from ~/.codemagic-token.
"""
import json
import pathlib
import re
import sys
import time
import urllib.request

APP_ID = "6af84a9375ea5dc018457195"
WORKFLOW = "ios-unsigned"
API = "https://api.codemagic.io"
TOKEN = (pathlib.Path.home() / ".codemagic-token").read_text().strip()
DIST = pathlib.Path(__file__).resolve().parent.parent / "dist"


def call(path, body=None, auth=True):
    url = path if path.startswith("http") else API + path
    headers = {"Content-Type": "application/json"}
    if auth:
        headers["x-auth-token"] = TOKEN
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers)
    with urllib.request.urlopen(req, timeout=120) as resp:
        return resp.read()


def start():
    out = json.loads(call("/builds", {"appId": APP_ID, "workflowId": WORKFLOW, "branch": "main"}))
    return out["buildId"]


def wait(build_id):
    last = None
    while True:
        build = json.loads(call(f"/builds/{build_id}"))["build"]
        status = build["status"]
        if status != last:
            print("status:", status, flush=True)
            last = status
        if status in ("finished", "failed", "canceled", "timeout", "skipped"):
            return build
        time.sleep(15)


def report(build):
    for action in build.get("buildActions", []):
        print(f"  [{action.get('status')}] {action.get('name')}")
    if build["status"] == "finished":
        DIST.mkdir(exist_ok=True)
        for art in build.get("artefacts", []):
            target = DIST / art["name"]
            try:
                target.write_bytes(call(art["url"]))
            except Exception:
                target.write_bytes(call(art["url"], auth=False))
            print("downloaded", target, target.stat().st_size, "bytes")
        return 0
    for action in build.get("buildActions", []):
        if action.get("status") == "failed" and action.get("logUrl"):
            try:
                log = call(action["logUrl"]).decode("utf-8", "replace")
            except Exception:
                log = call(action["logUrl"], auth=False).decode("utf-8", "replace")
            lines = log.splitlines()
            errors = [l for l in lines if re.search(r"error:|rror |No such|not found|FAILED", l)]
            seen = []
            for l in errors:
                if l not in seen:
                    seen.append(l)
            print(f"--- errors in '{action.get('name')}' ---")
            print("\n".join(l[:600] for l in seen[:60]) or "\n".join(lines[-40:]))
    return 1


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "build"
    build_id = start() if cmd == "build" else sys.argv[2]
    print("build", build_id, flush=True)
    sys.exit(report(wait(build_id)))

"""Use the existing Git Credential Manager login; never print or persist its token."""
import argparse
import io
import json
import os
from pathlib import Path
import subprocess
import urllib.error
import urllib.request
import zipfile

try:
    import truststore
    truststore.inject_into_ssl()
except ImportError:
    pass

OWNER = "BigLeopardCat"
REPO = "saudade-agent-ios"
ROOT = Path(__file__).resolve().parents[1]


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        redirected = super().redirect_request(req, fp, code, msg, headers, newurl)
        if redirected is not None:
            redirected.remove_header("Authorization")
        return redirected


def credential():
    env = {**os.environ, "GCM_INTERACTIVE": "never", "GIT_TERMINAL_PROMPT": "0"}
    result = subprocess.run(
        ["git", "credential", "fill"], input="protocol=https\nhost=github.com\n\n",
        text=True, capture_output=True, check=False, env=env,
    )
    fields = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)
    if result.returncode or not fields.get("password"):
        raise RuntimeError("No noninteractive GitHub login is available in Git Credential Manager.")
    return fields["password"]


def request(path, token, method="GET", payload=None, raw=False):
    body = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(
        "https://api.github.com" + path, data=body, method=method,
        headers={"Authorization": "Bearer " + token, "Accept": "application/vnd.github+json",
                 "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "Saudade-iOS-CI-setup",
                 "Content-Type": "application/json"},
    )
    with urllib.request.build_opener(SafeRedirect()).open(req, timeout=30) as response:
        data = response.read()
        return data if raw else (json.loads(data) if data else {})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["identity", "create", "runs", "jobs", "logs", "pr"])
    parser.add_argument("--run", type=int)
    parser.add_argument("--head")
    parser.add_argument("--title")
    parser.add_argument("--body-file", type=Path)
    args = parser.parse_args()
    token = credential()
    user = request("/user", token)
    if user["login"].lower() != OWNER.lower():
        raise RuntimeError("The authenticated account does not match the requested repository owner.")
    base = f"/repos/{OWNER}/{REPO}"
    if args.action == "identity":
        print(json.dumps({"login": user["login"]}))
    elif args.action == "create":
        try:
            repo = request(base, token)
            print(json.dumps({"created": False, "url": repo["html_url"], "size": repo["size"], "private": repo["private"]}))
        except urllib.error.HTTPError as error:
            if error.code != 404:
                raise
            repo = request("/user/repos", token, "POST", {
                "name": REPO, "private": False, "auto_init": False,
                "description": "泠月喵的 iOS 灵动岛伴侣 · SwiftUI / ActivityKit / Saudade Blog Agent",
            })
            print(json.dumps({"created": True, "url": repo["html_url"]}))
    elif args.action == "runs":
        runs = request(base + "/actions/runs?per_page=5", token)["workflow_runs"]
        print(json.dumps([{
            key: run[key] for key in ["id", "html_url", "head_sha", "status", "conclusion"]
        } for run in runs]))
    elif args.action == "jobs":
        jobs = request(base + f"/actions/runs/{args.run}/jobs", token)["jobs"]
        print(json.dumps([{"name": j["name"], "status": j["status"], "conclusion": j["conclusion"], "steps": [
            {key: step.get(key) for key in ["name", "status", "conclusion"]} for step in j["steps"]
        ]} for j in jobs]))
    elif args.action == "pr":
        if not args.head or not args.title or not args.body_file:
            raise ValueError("pr requires --head, --title and --body-file")
        existing = request(base + "/pulls?state=open&head=" + OWNER + ":" + args.head, token)
        payload = {"title": args.title, "body": args.body_file.read_text(encoding="utf-8"), "base": "main"}
        if existing:
            pr = request(base + "/pulls/" + str(existing[0]["number"]), token, "PATCH", payload)
        else:
            pr = request(base + "/pulls", token, "POST", {**payload, "head": args.head})
        print(json.dumps({"number": pr["number"], "url": pr["html_url"], "head": pr["head"]["sha"]}))
    else:
        data = request(base + f"/actions/runs/{args.run}/logs", token, raw=True)
        output = ROOT / "build" / "ci-logs" / str(args.run)
        output.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            for name in archive.namelist():
                if name.endswith(".txt"):
                    # Flatten server-controlled names to keep every write inside this run's directory.
                    filename = name.replace("/", "_").replace("\\", "_")
                    (output / filename).write_bytes(archive.read(name))
        print(json.dumps({"logs": str(output)}))


if __name__ == "__main__":
    try:
        main()
    except urllib.error.HTTPError as error:
        print(json.dumps({"error": "GitHub request failed", "status": error.code}))
        raise SystemExit(1)
    except Exception as error:
        print(json.dumps({"error": str(error)}))
        raise SystemExit(1)

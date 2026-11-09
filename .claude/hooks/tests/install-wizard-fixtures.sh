#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Sn4kyGit, Anna Mazurek

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
INSTALL="$REPO/install.sh"
[ -x "$INSTALL" ] || { echo "install.sh not executable at $INSTALL" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required" >&2; exit 1; }

WORK="$(mktemp -d)"
if [ "${QA_KEEP:-0}" = "1" ]; then
  printf 'work dir kept: %s\n' "$WORK"
else
  trap 'rm -rf "$WORK"' EXIT
fi

python3 - "$INSTALL" "$REPO" "$WORK" <<'PY'
import json
import os
import pty
import select
import shutil
import subprocess
import sys
import time

install, repo, work = sys.argv[1:4]
fails = 0


def ok(label):
    print(f"ok    {label}")


def fail(label, detail=""):
    global fails
    fails += 1
    print(f"FAIL  {label}")
    if detail:
        print(f"      {detail}")


def run(args, env=None, cwd=repo, inputs=None, timeout=25):
    command = ["bash", install, *args]
    environment = os.environ.copy()
    if env:
        environment.update(env)
    if inputs is None:
        result = subprocess.run(command, cwd=cwd, env=environment, text=True, capture_output=True, timeout=timeout)
        return result.returncode, result.stdout + result.stderr
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(cwd)
        os.execvpe(command[0], command, environment)
    output = b""
    start = time.time()
    sent = False
    try:
        while True:
            if not sent and inputs:
                os.write(fd, ("\n".join(inputs) + "\n").encode())
                sent = True
            ready, _, _ = select.select([fd], [], [], 0.1)
            if fd in ready:
                try:
                    chunk = os.read(fd, 4096)
                except OSError:
                    break
                if not chunk:
                    break
                output += chunk
            if time.time() - start > timeout:
                break
            if b"INSTALL REPORT" in output and b"Proceed with this plan?" not in output:
                time.sleep(0.1)
                try:
                    ready, _, _ = select.select([fd], [], [], 0)
                    if fd in ready:
                        output += os.read(fd, 4096)
                except OSError:
                    pass
                break
    finally:
        try:
            os.close(fd)
        except OSError:
            pass
        try:
            os.waitpid(pid, 0)
        except ChildProcessError:
            pass
    return 0, output.decode(errors="replace")


def read_json(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def has(output, text):
    return text in output


for mode, number, extra in [
    ("plugin", "1", []),
    ("opencode", "2", ["3"]),
    ("shared", "3", ["3"]),
    ("integrate", "4", []),
]:
    target = os.path.join(work, f"wizard-{mode}")
    os.makedirs(target)
    code, output = run(["--wizard", "--dry-run", "--target", target], inputs=[number, "1", "1", *extra, "y"])
    if code == 0 and has(output, "setup wizard") and has(output, "Proceed with this plan?") and has(output, "Dry run finished"):
        ok(f"wizard reaches {mode} and confirms the plan")
    else:
        fail(f"wizard reaches {mode} and confirms the plan", output[-1200:])

target = os.path.join(work, "explicit")
os.makedirs(target)
code, output = run(["--mode", "plugin", "--target", target, "--yes", "--dry-run"])
if code == 0 and not has(output, "setup wizard") and has(output, "INSTALL REPORT"):
    ok("--yes skips wizard and keeps automation-safe defaults")
else:
    fail("--yes skips wizard and keeps automation-safe defaults", output[-1200:])

target = os.path.join(work, "ci")
os.makedirs(target)
code, output = run(["--mode", "plugin", "--target", target, "--dry-run"], env={"CI": "1"})
if code == 0 and not has(output, "setup wizard") and has(output, "INSTALL REPORT"):
    ok("CI without --yes skips wizard without prompts")
else:
    fail("CI without --yes skips wizard without prompts", output[-1200:])

target = os.path.join(work, "cancel")
os.makedirs(target)
code, output = run(["--mode", "plugin", "--target", target], inputs=["1", "1", "1", "n"])
if code == 0 and has(output, "Wizard cancelled") and not os.listdir(target):
    ok("cancelling before confirmation writes nothing")
else:
    fail("cancelling before confirmation writes nothing", output[-1200:])

target = os.path.join(work, "headful")
os.makedirs(target)
with open(os.path.join(target, ".playwright-mcp.config.json"), "w", encoding="utf-8") as handle:
    json.dump({"browser": {"launchOptions": {"viewport": {"width": 1280}}, "isolated": False}, "custom": {"keep": True}}, handle)
code, output = run(["--mode", "plugin", "--target", target, "--yes", "--browser", "headful"])
config = read_json(os.path.join(target, ".playwright-mcp.config.json"))
if code == 0 and config["browser"]["launchOptions"]["headless"] is False and config["browser"]["launchOptions"].get("viewport") == {"width": 1280} and config.get("custom") == {"keep": True}:
    ok("browser preference preserves unrelated keys")
else:
    fail("browser preference preserves unrelated keys", output[-1200:])

target = os.path.join(work, "model-setup")
os.makedirs(target)
code, output = run([
    "--mode", "opencode", "--target", target, "--yes", "--model-setup", "now",
    "--cheap", "acme/small", "--standard", "acme/medium", "--deep", "acme/large",
    "--cheap-variant", "low", "--standard-variant", "medium", "--deep-variant", "high",
])
config = read_json(os.path.join(target, "opencode.json"))
overrides = config.get("agent", {})
if code == 0 and all(
    overrides.get(name, {}).get("model") == model
    for name, model in [
        ("test-executor-cheap", "acme/small"),
        ("test-executor", "acme/medium"),
        ("test-executor-deep", "acme/large"),
        ("test-automator-cheap", "acme/small"),
        ("test-automator", "acme/medium"),
        ("test-automator-deep", "acme/large"),
    ]
) and "model" not in config:
    ok("model setup writes only six consumer lane overrides")
else:
    fail("model setup writes only six consumer lane overrides", output[-1200:])

target = os.path.join(work, "dc")
os.makedirs(target)
code, output = run([
    "--mode", "opencode", "--target", target, "--yes",
    "--jira", "datacenter", "--jira-url", "https://jira.example.invalid",
])
config = read_json(os.path.join(target, "opencode.json"))
entry = config.get("mcp", {}).get("atlassian", {})
if code == 0 and entry.get("type") == "local" and entry.get("environment", {}).get("JIRA_URL") == "https://jira.example.invalid" and "JIRA_PERSONAL_TOKEN" not in json.dumps(config) and "DECOY_PAT" not in output:
    ok("Data Center preference writes URL without any token")
else:
    fail("Data Center preference writes URL without any token", output[-1200:])

target = os.path.join(work, "uninstall")
os.makedirs(target)
code, output = run(["--mode", "opencode", "--target", target, "--uninstall"])
if code == 0 and not has(output, "setup wizard"):
    ok("uninstall skips the wizard")
else:
    fail("uninstall skips the wizard", output[-1200:])

target = os.path.join(work, "move-source")
os.makedirs(target)
code, output = run(["--mode", "opencode", "--target", target, "--move", os.path.join(work, "move-target"), "--yes"])
if not has(output, "setup wizard") and ("opencode move" in output or code != 0):
    ok("move skips the wizard")
else:
    fail("move skips the wizard", output[-1200:])

target = os.path.join(work, "no-wizard")
os.makedirs(target)
code, output = run(["--mode", "plugin", "--target", target, "--no-wizard", "--yes", "--dry-run"])
if code == 0 and not has(output, "setup wizard"):
    ok("--no-wizard uses the plain flag-driven path")
else:
    fail("--no-wizard uses the plain flag-driven path", output[-1200:])

target = os.path.join(work, "force")
os.makedirs(target)
code, output = run(["--wizard", "--mode", "plugin", "--target", target, "--dry-run"], inputs=["1", "1", "y"])
if code == 0 and has(output, "setup wizard") and has(output, "Proceed with this plan?"):
    ok("--wizard forces the guided path even with explicit mode")
else:
    fail("--wizard forces the guided path even with explicit mode", output[-1200:])

print()
if fails:
    print(f"{fails} fixture(s) failed")
else:
    print("all fixtures passed")
sys.exit(fails)
PY

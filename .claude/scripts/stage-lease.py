#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Sn4kyGit
"""Stage coordination leases + test-data lifecycle (local backend).

Parallel sessions/humans on a shared stage stop contaminating each other. Two
complementary mechanisms (docs/retention-leases-rollup-plan.md §5, D4):
  * Namespacing (cheap, parallel-friendly) — runs create entities under a
    run-scoped prefix; recommended for everyone, enforced nowhere.
  * Leases for what cannot be namespaced — deploy, global reset, cache flush,
    and an optional coarse stage-write lease. ADAPTIVE: an absent
    "## Stage coordination" section (or "Shared stage: no") means SOLO mode —
    acquire exits 4 (off), zero friction. Team mode is opt-in.

Local backend: lease files under evidence/.leases/, fcntl.flock per environment
for the acquire critical section, TTL + heartbeat for crash safety. Waiting
happens INSIDE one process (--wait), never agent sleep-polling.

Zero-dependency (stdlib). Exit codes: 0 ok/acquired, 3 busy, 4 coordination off,
2 usage, 1 error.
"""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import re
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

DEFAULT_TTL = 900  # seconds


def now_ts():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def slug(value):
    return re.sub(r"[^A-Za-z0-9._-]", "_", str(value))[:80]


def conflicts(a, b):
    """Conflict matrix (plan §5): deploy conflicts with everything; reset with
    write/data/reset/deploy; stage-write with stage-write/deploy/reset; data:<ns>
    only with the same namespace + reset/deploy."""
    if a == "deploy" or b == "deploy":
        return True
    if a == "reset" or b == "reset":
        return True
    if a == "stage-write" and b == "stage-write":
        return True
    if a.startswith("data:") and b.startswith("data:"):
        return a == b
    return False


def coordination_enabled(project_dir: Path):
    """Solo unless PROJECT.md opts into a shared stage. Returns (enabled, write_required)."""
    md = project_dir / "PROJECT.md"
    if not md.is_file():
        return False, False
    try:
        text = md.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return False, False
    section = re.search(r"(?ms)^##\s+Stage coordination\s*$(.*?)(?=^##\s|\Z)", text)
    if not section:
        return False, False
    body = section.group(1)
    shared = re.search(r"Shared stage\*{0,2}:?\s*`?(yes|no)", body, re.IGNORECASE)
    enabled = bool(shared and shared.group(1).lower() == "yes")
    write_req = re.search(r"Write lease\*{0,2}:?\s*`?(required|off)", body, re.IGNORECASE)
    write_required = bool(write_req and write_req.group(1).lower() == "required")
    return enabled, write_required


def lease_dir(home: Path):
    d = home / "evidence" / ".leases"
    d.mkdir(parents=True, exist_ok=True)
    return d


def audit(home: Path, line):
    d = home / "evidence" / ".audit"
    d.mkdir(parents=True, exist_ok=True)
    with open(d / "lease.log", "a", encoding="utf-8") as fh:
        fh.write(f"{now_ts()} | {line}\n")


def read_leases(ld: Path, envslug):
    out = []
    for p in sorted(ld.glob(f"{envslug}__*.json")):
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if isinstance(data, dict):
            data["_path"] = str(p)
            out.append(data)
    return out


def is_stale(lease, now):
    return now >= lease.get("expires_at_epoch", 0)


def write_lease(path: Path, lease):
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(lease, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(tmp, path)


def cmd_acquire(args):
    home = Path(args.qa_home)
    enabled, _ = coordination_enabled(home / "projects" / args.project)
    if not enabled:
        print("coordination off (solo mode) — no lease needed", file=sys.stderr)
        return 4
    if not args.holder or not args.ticket:
        print("acquire requires --holder and --ticket", file=sys.stderr)
        return 2
    ld = lease_dir(home)
    envslug = slug(args.env)
    scope = args.scope
    token = uuid.uuid4().hex
    deadline = time.time() + max(0, args.wait)
    lock_path = ld / f".lock-{envslug}"
    while True:
        now = time.time()
        with open(lock_path, "w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            busy_holder = None
            for lease in read_leases(ld, envslug):
                if is_stale(lease, now):
                    Path(lease["_path"]).unlink(missing_ok=True)
                    audit(home, f"takeover | env={args.env} | scope={lease.get('scope')} | holder={lease.get('holder')} | expired")
                    continue
                if conflicts(scope, lease.get("scope", "")):
                    busy_holder = lease
                    break
            if busy_holder is None:
                lease = {
                    "token": token, "scope": scope, "env": args.env, "project": args.project,
                    "holder": args.holder, "ticket": args.ticket,
                    "acquired_at": now_ts(), "acquired_at_epoch": now,
                    "expires_at_epoch": now + args.ttl, "ttl_s": args.ttl,
                    "heartbeat_at": now_ts(),
                }
                write_lease(ld / f"{envslug}__{slug(scope)}__{token[:8]}.json", lease)
                audit(home, f"acquire | env={args.env} | scope={scope} | holder={args.holder} | ticket={args.ticket} | token={token[:8]} | ttl={args.ttl}")
                fcntl.flock(lock, fcntl.LOCK_UN)
                if args.json:
                    print(json.dumps({"token": token, "scope": scope, "expires_at_epoch": lease["expires_at_epoch"]}, sort_keys=True))
                else:
                    print(f"acquired {scope} on {args.env} (token {token[:8]}, ttl {args.ttl}s)")
                return 0
            fcntl.flock(lock, fcntl.LOCK_UN)
        if time.time() >= deadline:
            msg = f"busy: {busy_holder.get('scope')} held by {busy_holder.get('holder')} (ticket {busy_holder.get('ticket')}) until {busy_holder.get('acquired_at')}+{busy_holder.get('ttl_s')}s"
            print(msg, file=sys.stderr)
            return 3
        time.sleep(min(2, max(0.1, deadline - time.time())))


def find_by_token(ld: Path, token):
    for p in ld.glob("*.json"):
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if data.get("token") == token:
            return p, data
    return None, None


def cmd_release(args):
    home = Path(args.qa_home)
    ld = lease_dir(home)
    path, lease = find_by_token(ld, args.token)
    if not path:
        print("no lease with that token", file=sys.stderr)
        return 1
    path.unlink(missing_ok=True)
    audit(home, f"release | env={lease.get('env')} | scope={lease.get('scope')} | holder={lease.get('holder')} | token={args.token[:8]}")
    print(f"released {lease.get('scope')}")
    return 0


def cmd_heartbeat(args):
    home = Path(args.qa_home)
    ld = lease_dir(home)
    path, lease = find_by_token(ld, args.token)
    if not path:
        print("no lease with that token", file=sys.stderr)
        return 1
    now = time.time()
    lease["expires_at_epoch"] = now + lease.get("ttl_s", DEFAULT_TTL)
    lease["heartbeat_at"] = now_ts()
    write_lease(path, lease)
    print(f"heartbeat {lease.get('scope')} (expires +{lease.get('ttl_s')}s)")
    return 0


def cmd_status(args):
    home = Path(args.qa_home)
    ld = lease_dir(home)
    now = time.time()
    active = []
    for p in sorted(ld.glob("*.json")):
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if not is_stale(data, now):
            active.append(data)
    if args.json:
        print(json.dumps(active, indent=2, sort_keys=True))
    else:
        if not active:
            print("no active leases")
        for d in active:
            print(f"{d.get('env')} | {d.get('scope')} | holder={d.get('holder')} | ticket={d.get('ticket')} | token={d.get('token','')[:8]} | expires={d.get('heartbeat_at')}+{d.get('ttl_s')}s")
    return 0


def cmd_break(args):
    if not args.yes or not args.reason:
        print("break requires --reason and --yes (a human step)", file=sys.stderr)
        return 2
    home = Path(args.qa_home)
    ld = lease_dir(home)
    path, lease = find_by_token(ld, args.token)
    if not path:
        print("no lease with that token", file=sys.stderr)
        return 1
    path.unlink(missing_ok=True)
    audit(home, f"break | env={lease.get('env')} | scope={lease.get('scope')} | holder={lease.get('holder')} | token={args.token[:8]} | reason={args.reason}")
    print(f"broke lease {lease.get('scope')} (reason: {args.reason})")
    return 0


def main(argv=None):
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--qa-home", default=".", help="QA home directory")
    ap = argparse.ArgumentParser(description="Stage coordination leases (local backend, adaptive solo/team).")
    sub = ap.add_subparsers(dest="command", required=True)

    p = sub.add_parser("acquire", parents=[common])
    p.add_argument("--project", required=True)
    p.add_argument("--env", required=True, help="environment URL or name (lease namespace)")
    p.add_argument("--scope", required=True, help="deploy|reset|stage-write|data:<ns>")
    p.add_argument("--holder", help="identity (session/user@host)")
    p.add_argument("--ticket", help="ticket key")
    p.add_argument("--ttl", type=int, default=DEFAULT_TTL)
    p.add_argument("--wait", type=int, default=0, help="bounded wait seconds (inside this process)")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_acquire)

    for name in ("release", "heartbeat"):
        p = sub.add_parser(name, parents=[common])
        p.add_argument("--token", required=True)
        p.set_defaults(func=cmd_release if name == "release" else cmd_heartbeat)

    p = sub.add_parser("status", parents=[common])
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_status)

    p = sub.add_parser("break", parents=[common])
    p.add_argument("--token", required=True)
    p.add_argument("--reason")
    p.add_argument("--yes", action="store_true")
    p.set_defaults(func=cmd_break)

    args = ap.parse_args(argv)
    try:
        return args.func(args)
    except Exception as exc:  # noqa: BLE001
        print(f"lease error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())

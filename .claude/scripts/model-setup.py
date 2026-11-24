#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Sn4kyGit

import argparse
import json
import os
import re
import sys
import tempfile

LANES = (
    ("test-executor-cheap", "cheap"),
    ("test-executor", "standard"),
    ("test-executor-deep", "deep"),
    ("test-automator-cheap", "cheap"),
    ("test-automator", "standard"),
    ("test-automator-deep", "deep"),
)
# Optional judge roles (0.27.0): the adversarial verdict court. --judge sets both
# prosecutor and defender to one model; --failure-analyst is separate. These are
# additive and optional — inherit stays the working default (D6).
JUDGE_ROLES = ("verdict-prosecutor", "verdict-defender")
ANALYST_ROLE = "failure-analyst"
EXTRA_ROLES = JUDGE_ROLES + (ANALYST_ROLE,)
MODEL_PART = re.compile(r"[A-Za-z0-9][A-Za-z0-9+._:@-]*")


def valid_model(value):
    provider, separator, model = value.partition("/")
    if not separator or not MODEL_PART.fullmatch(provider) or not model:
        return False
    return all(MODEL_PART.fullmatch(part) for part in model.split("/"))


def parse_jsonc(text):
    uncommented = []
    index = 0
    in_string = False
    escaped = False
    while index < len(text):
        char = text[index]
        if in_string:
            uncommented.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
        elif char == '"':
            in_string = True
            uncommented.append(char)
            index += 1
        elif char == "/" and index + 1 < len(text) and text[index + 1] == "/":
            uncommented.extend("  ")
            index += 2
            while index < len(text) and text[index] != "\n":
                uncommented.append(" ")
                index += 1
        elif char == "/" and index + 1 < len(text) and text[index + 1] == "*":
            uncommented.extend("  ")
            index += 2
            while index < len(text):
                if text[index] == "*" and index + 1 < len(text) and text[index + 1] == "/":
                    uncommented.extend("  ")
                    index += 2
                    break
                uncommented.append("\n" if text[index] == "\n" else " ")
                index += 1
        else:
            uncommented.append(char)
            index += 1
    source = "".join(uncommented)
    cleaned = []
    index = 0
    in_string = False
    escaped = False
    while index < len(source):
        char = source[index]
        if in_string:
            cleaned.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
        elif char == '"':
            in_string = True
            cleaned.append(char)
        elif char == ",":
            following = index + 1
            while following < len(source) and source[following].isspace():
                following += 1
            if following >= len(source) or source[following] not in "]}":
                cleaned.append(char)
        else:
            cleaned.append(char)
        index += 1
    value = json.loads("".join(cleaned))
    if not isinstance(value, dict):
        raise ValueError("opencode.json must contain an object")
    return value


def load_config(path):
    if not os.path.exists(path):
        return {}, None
    if not os.path.isfile(path):
        raise ValueError("opencode.json is not a regular file")
    with open(path, "rb") as handle:
        original = handle.read()
    config = parse_jsonc(original.decode("utf-8-sig"))
    agents = config.get("agent")
    if agents is not None and not isinstance(agents, dict):
        raise ValueError("opencode.json agent must be an object")
    if isinstance(agents, dict):
        for lane, _ in LANES:
            if lane in agents and not isinstance(agents[lane], dict):
                raise ValueError("a target agent override must be an object")
        for role in EXTRA_ROLES:
            if role in agents and not isinstance(agents[role], dict):
                raise ValueError("a target agent override must be an object")
    return config, original


def show(config):
    agents = config.get("agent") or {}
    for lane, _ in LANES:
        override = agents.get(lane) or {}
        model = override.get("model")
        if not isinstance(model, str) or not model:
            print(f"agent.{lane}: <not set>")
            continue
        variant = override.get("variant")
        suffix = f" variant={variant}" if isinstance(variant, str) and variant else ""
        print(f"agent.{lane}: {model}{suffix}")
    for role in EXTRA_ROLES:
        override = agents.get(role) or {}
        model = override.get("model")
        if not isinstance(model, str) or not model:
            print(f"agent.{role}: <inherit>")
            continue
        variant = override.get("variant")
        suffix = f" variant={variant}" if isinstance(variant, str) and variant else ""
        print(f"agent.{role}: {model}{suffix}")


def write_bytes(path, data):
    directory = os.path.dirname(path)
    descriptor, temporary = tempfile.mkstemp(prefix=".model-setup-", dir=directory)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(data)
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def build_parser():
    parser = argparse.ArgumentParser(description="Set consumer opencode QA agent model overrides")
    parser.add_argument("--cwd", required=True)
    for group in ("cheap", "standard", "deep"):
        parser.add_argument("--" + group)
        parser.add_argument("--" + group + "-variant")
    parser.add_argument("--judge", help="model for both verdict-prosecutor and verdict-defender (optional)")
    parser.add_argument("--judge-variant")
    parser.add_argument("--failure-analyst", help="model for failure-analyst (optional)")
    parser.add_argument("--failure-analyst-variant")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--check", action="store_true")
    return parser


def _set_role(agents, role, model, variant):
    override = agents.setdefault(role, {})
    override["model"] = model
    variant = variant.strip() if isinstance(variant, str) else None
    if variant:
        override["variant"] = variant
    else:
        override.pop("variant", None)


def main():
    parser = build_parser()
    args = parser.parse_args()
    lanes_provided = any(getattr(args, g) is not None for g in ("cheap", "standard", "deep"))
    judge_provided = args.judge is not None
    analyst_provided = args.failure_analyst is not None
    if not args.check:
        if not (lanes_provided or judge_provided or analyst_provided):
            parser.error("specify --cheap/--standard/--deep and/or --judge (or --failure-analyst); or use --check")
        if lanes_provided:
            missing = [g for g in ("cheap", "standard", "deep") if getattr(args, g) is None]
            if missing:
                parser.error("--cheap, --standard and --deep must be set together")
            for g in ("cheap", "standard", "deep"):
                if not valid_model(getattr(args, g)):
                    parser.error("invalid model reference for --" + g + "; expected provider/model")
        if judge_provided and not valid_model(args.judge):
            parser.error("invalid model reference for --judge; expected provider/model")
        if analyst_provided and not valid_model(args.failure_analyst):
            parser.error("invalid model reference for --failure-analyst; expected provider/model")
    session = os.path.abspath(os.path.expanduser(args.cwd))
    if not os.path.isdir(session):
        raise ValueError("--cwd must name an existing session directory")
    config_path = os.path.join(session, "opencode.json")
    config, original = load_config(config_path)
    if args.check:
        show(config)
        return
    agents = config.setdefault("agent", {})
    if lanes_provided:
        for lane, group in LANES:
            _set_role(agents, lane, getattr(args, group), getattr(args, group + "_variant"))
    if judge_provided:
        for role in JUDGE_ROLES:
            _set_role(agents, role, args.judge, args.judge_variant)
    if analyst_provided:
        _set_role(agents, ANALYST_ROLE, args.failure_analyst, args.failure_analyst_variant)
    # Independence hint (advisory, never blocks): a judge on the same model as an
    # executor lane reviews its own work. Prefer a different, ideally stronger model.
    if judge_provided:
        lane_models = {getattr(args, g) for g in ("cheap", "standard", "deep") if getattr(args, g)}
        for lane, _ in LANES:
            m = (agents.get(lane) or {}).get("model")
            if isinstance(m, str) and m:
                lane_models.add(m)
        if args.judge in lane_models:
            print("WARNING: judge model equals an executor lane model — the judge reviews its "
                  "own work, so independence is reduced. Prefer a different (ideally stronger) "
                  "model for the judge.", file=sys.stderr)
    rendered = (json.dumps(config, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    if args.dry_run:
        print("Dry run: no files written")
        return
    if original is not None:
        write_bytes(config_path + ".bak", original)
    write_bytes(config_path, rendered)
    print("Updated consumer opencode.json")
    if original is not None:
        print("Backup: opencode.json.bak")


if __name__ == "__main__":
    try:
        main()
    except (OSError, UnicodeError, ValueError, json.JSONDecodeError) as error:
        print(f"model-setup: {error}", file=sys.stderr)
        sys.exit(1)

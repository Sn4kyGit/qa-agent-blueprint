#!/usr/bin/env python3
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
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--check", action="store_true")
    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()
    if not args.check:
        missing = [group for group in ("cheap", "standard", "deep") if getattr(args, group) is None]
        if missing:
            parser.error("--cheap, --standard and --deep are required unless --check is used")
        for group in ("cheap", "standard", "deep"):
            if not valid_model(getattr(args, group)):
                parser.error("invalid model reference for --" + group + "; expected provider/model")
    session = os.path.abspath(os.path.expanduser(args.cwd))
    if not os.path.isdir(session):
        raise ValueError("--cwd must name an existing session directory")
    config_path = os.path.join(session, "opencode.json")
    config, original = load_config(config_path)
    if args.check:
        show(config)
        return
    agents = config.setdefault("agent", {})
    for lane, group in LANES:
        override = agents.setdefault(lane, {})
        override["model"] = getattr(args, group)
        variant = getattr(args, group + "_variant")
        if variant is not None:
            variant = variant.strip()
        if variant:
            override["variant"] = variant
        else:
            override.pop("variant", None)
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

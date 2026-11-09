#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Sn4kyGit, Anna Mazurek

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
python3 - "$ROOT/.claude/scripts/model-setup.py" <<'PY'
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile

script = Path(sys.argv[1])
lanes = {
    "test-executor-cheap": "cheap",
    "test-executor": "standard",
    "test-executor-deep": "deep",
    "test-automator-cheap": "cheap",
    "test-automator": "standard",
    "test-automator-deep": "deep",
}
models = {
    "cheap": "openrouter/z-ai/glm-test",
    "standard": "anthropic/claude-standard",
    "deep": "openai/gpt-deep",
}
secret = "MODEL_SETUP_DECOY_SECRET_NEVER_PRINT"


def run(case, *arguments, expected=0):
    result = subprocess.run(
        [sys.executable, str(script), "--cwd", str(case), *arguments],
        capture_output=True,
        text=True,
    )
    assert result.returncode == expected, (result.returncode, result.stdout, result.stderr)
    assert secret not in result.stdout + result.stderr
    return result


def model_arguments(**variants):
    arguments = []
    for group in ("cheap", "standard", "deep"):
        arguments.extend(("--" + group, models[group]))
        if group in variants:
            arguments.extend(("--" + group + "-variant", variants[group]))
    return arguments


def snapshot(case):
    return {
        str(path.relative_to(case)): path.read_bytes()
        for path in case.rglob("*")
        if path.is_file()
    }


with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    case = root / "json"
    case.mkdir()
    original = {
        "$schema": "https://opencode.ai/config.json",
        "model": "user/primary",
        "small_model": "user/small",
        "mcp": {
            "playwright": {
                "type": "local",
                "command": ["npx", "@playwright/mcp@latest"],
                "environment": {"TOKEN": secret},
            }
        },
        "permission": {"read": {"**/.env*": "deny"}},
        "agent": {
            "qa-manager": {"model": "user/manager"},
            "test-executor": {"model": "old/standard", "variant": "old", "temperature": 0.2},
            "unrelated": {"model": "user/unrelated", "variant": "keep"},
        },
    }
    for lane in lanes:
        original["agent"].setdefault(lane, {"model": "old/model", "variant": "old"})
    before = (json.dumps(original, indent=2) + "\n").encode()
    config_path = case / "opencode.json"
    config_path.write_bytes(before)
    foreign = {
        "model": copy.deepcopy(original["model"]),
        "small_model": copy.deepcopy(original["small_model"]),
        "mcp": copy.deepcopy(original["mcp"]),
        "permission": copy.deepcopy(original["permission"]),
        "qa-manager": copy.deepcopy(original["agent"]["qa-manager"]),
        "unrelated": copy.deepcopy(original["agent"]["unrelated"]),
    }
    result = run(case, *model_arguments(cheap="fast", standard="balanced", deep="thorough"))
    assert "Backup: opencode.json.bak" in result.stdout
    assert (case / "opencode.json.bak").read_bytes() == before
    configured = json.loads(config_path.read_text())
    for lane, group in lanes.items():
        assert configured["agent"][lane]["model"] == models[group]
    assert configured["agent"]["test-executor-cheap"]["variant"] == "fast"
    assert configured["agent"]["test-executor"]["variant"] == "balanced"
    assert configured["agent"]["test-executor-deep"]["variant"] == "thorough"
    assert configured["agent"]["test-executor"]["temperature"] == 0.2
    assert configured["model"] == foreign["model"]
    assert configured["small_model"] == foreign["small_model"]
    assert configured["mcp"] == foreign["mcp"]
    assert configured["permission"] == foreign["permission"]
    assert configured["agent"]["qa-manager"] == foreign["qa-manager"]
    assert configured["agent"]["unrelated"] == foreign["unrelated"]
    print("ok    six overrides, variants, foreign values, and backup")

    checked_before = snapshot(case)
    result = run(case, "--check")
    for lane, group in lanes.items():
        assert result.stdout.count("agent." + lane + ":") == 1
        assert models[group] in result.stdout
    assert snapshot(case) == checked_before
    print("ok    check lists six lanes and is read-only")

    dry_before = snapshot(case)
    result = run(case, *model_arguments(), "--dry-run")
    assert "no files written" in result.stdout
    assert snapshot(case) == dry_before
    print("ok    dry-run leaves every byte unchanged")

    result = run(case, *model_arguments(cheap=""))
    configured = json.loads(config_path.read_text())
    for lane in lanes:
        assert "variant" not in configured["agent"][lane]
    assert configured["agent"]["unrelated"]["variant"] == "keep"
    print("ok    empty and missing variants remove only target variants")

    invalid_before = snapshot(case)
    for invalid in ("DO_NOT_ECHO_INVALID", "/DO_NOT_ECHO_PROVIDER", "DO_NOT_ECHO_MODEL/", "white space/DO_NOT_ECHO_SPACE", "provider/DO NOT ECHO", "provider//DO_NOT_ECHO_EMPTY"):
        result = run(case, "--cheap", invalid, "--standard", models["standard"], "--deep", models["deep"], expected=2)
        assert invalid not in result.stdout + result.stderr
        assert snapshot(case) == invalid_before
    print("ok    invalid provider/model input never writes or echoes input")

    jsonc_case = root / "jsonc"
    jsonc_case.mkdir()
    jsonc_source = r'''{
  // Consumer comments and https:// URLs stay out of strings.
  "$schema": "https://opencode.ai/config.json",
  "note": "escaped \"quote\", C:\\temp, // text, and /* text */",
  "agent": {
    "test-executor": {"model": "old/model", "variant": "old", "temperature": 0.1,},
  },
  "mcp": {"playwright": {"type": "local", "command": ["npx", "server",],},},
  "secretReference": "MODEL_SETUP_DECOY_SECRET_NEVER_PRINT",
}
'''
    jsonc_path = jsonc_case / "opencode.json"
    jsonc_path.write_text(jsonc_source)
    run(jsonc_case, *model_arguments(cheap="fast"))
    parsed = json.loads(jsonc_path.read_text())
    assert parsed["note"] == 'escaped "quote", C:\\temp, // text, and /* text */'
    assert parsed["$schema"] == "https://opencode.ai/config.json"
    assert parsed["mcp"]["playwright"]["command"] == ["npx", "server"]
    assert parsed["agent"]["test-executor"]["temperature"] == 0.1
    assert parsed["secretReference"] == secret
    assert (jsonc_case / "opencode.json.bak").read_text() == jsonc_source
    print("ok    JSONC comments, trailing commas, URLs, and escaped strings")

    malformed_case = root / "malformed"
    malformed_case.mkdir()
    malformed_path = malformed_case / "opencode.json"
    malformed_path.write_text('{"agent": [')
    malformed_before = snapshot(malformed_case)
    run(malformed_case, *model_arguments(), expected=1)
    assert snapshot(malformed_case) == malformed_before
    print("ok    malformed config fails without writes")

    new_case = root / "new"
    new_case.mkdir()
    run(new_case, "--check")
    assert snapshot(new_case) == {}
    run(new_case, *model_arguments(), "--dry-run")
    assert snapshot(new_case) == {}
    run(new_case, *model_arguments())
    created = json.loads((new_case / "opencode.json").read_text())
    assert set(created["agent"]) == set(lanes)
    assert not (new_case / "opencode.json.bak").exists()
    print("ok    absent config stays absent for check and dry-run")

print("all fixtures passed")
PY

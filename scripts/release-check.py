#!/usr/bin/env python3

import argparse
import json
import re
import sys
from pathlib import Path


MIXED_SKILLS = {
    "accessibility-testing",
    "api-testing",
    "bug-reproduction",
    "exploratory-testing",
    "qa-metrics",
    "release-readiness",
    "risk-based-testing",
    "security-testing",
    "test-case-management",
    "test-reliability",
    "visual-testing",
}
ALLOWED_LICENSES = {"Apache-2.0", "MIT", "MIT AND Apache-2.0", "Apache-2.0 AND MIT"}
IDAVIDOV_COMMIT = "7d4ec4f3c410b8a733fdd0056ca268444354631a"
PETR_COMMIT = "b3bb61bd268b147476252c6ed5a0440c87b97441"
ADAPTED_NOTICE_PATHS = (
    ".claude/scripts/qa-test-code-scan.mjs",
    ".claude/hooks/pre-test-code-scan.sh",
    ".claude/skills/scaffold-suite/templates/quality/",
    ".claude/skills/scaffold-suite/templates/tests/fixtures/action-journal.ts",
    "action-journal.wdio.cjs",
    ".claude/scripts/action-journal.py",
    ".claude/scripts/healing-candidate.py",
    "docs/pipeline/action-journal.md",
    "docs/pipeline/healing.md",
    "evals/lib/artifact_checks.py",
    "evals/lib/runner_policy.py",
    "evals/*/graders/checks.json",
)
ROOT_NOTICE_PATHS = (
    ".claude/scripts/qa-test-code-scan.mjs",
    ".claude/hooks/pre-test-code-scan.sh",
    ".claude/skills/scaffold-suite/templates/quality/",
    ".claude/scripts/action-journal.py",
    ".claude/scripts/healing-candidate.py",
    "docs/pipeline/action-journal.md",
    "docs/pipeline/healing.md",
    "evals/lib/",
    "evals/*/graders/checks.json",
)


class Report:
    def __init__(self):
        self.failures = 0

    def ok(self, message):
        print(f"ok    {message}")

    def fail(self, message):
        self.failures += 1
        print(f"FAIL  {message}")


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def license_fields(path):
    text = path.read_text(encoding="utf-8")
    match = re.match(r"\A---\n(.*?)\n---(?:\n|\Z)", text, re.DOTALL)
    if not match:
        return None
    return [line.split(":", 1)[1].strip() for line in match.group(1).splitlines() if line.startswith("license:")]


def check_versions(root, report):
    plugin = read_json(root / ".claude-plugin" / "plugin.json")
    marketplace = read_json(root / ".claude-plugin" / "marketplace.json")
    version = plugin.get("version")
    entries = [entry for entry in marketplace.get("plugins", []) if entry.get("name") == plugin.get("name")]
    if not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", str(version)):
        report.fail(f"plugin version is not SemVer: {version!r}")
    else:
        report.ok(f"plugin version is SemVer ({version})")
    if len(entries) != 1 or entries[0].get("version") != version:
        report.fail("plugin.json and marketplace.json versions must agree")
    else:
        report.ok("plugin and marketplace versions agree")
    template = (root / "opencode" / "opencode.template.jsonc").read_text(encoding="utf-8")
    match = re.search(r"(?m)^//\s*blueprint-version:\s*(\S+)\s*$", template)
    if not match or match.group(1) != version:
        report.fail("opencode template blueprint-version must match plugin.json")
    else:
        report.ok("opencode template version agrees")


def check_notices(root, report):
    notice_path = root / "NOTICE"
    third_path = root / ".claude" / "skills" / "THIRD_PARTY_NOTICES.md"
    if not notice_path.is_file() or not third_path.is_file():
        report.fail("NOTICE and .claude/skills/THIRD_PARTY_NOTICES.md are required")
        return
    notice = notice_path.read_text(encoding="utf-8")
    third = third_path.read_text(encoding="utf-8")
    required_notice = (
        IDAVIDOV_COMMIT,
        PETR_COMMIT,
        "Copyright (c) 2026 Ivan Davidov and Agentic Playwright contributors",
        "Copyright (c) 2026 Petr Kindlmann",
    )
    for value in required_notice:
        if value not in notice:
            report.fail(f"root NOTICE is missing {value}")
    for value in (
        IDAVIDOV_COMMIT,
        PETR_COMMIT,
        "Copyright (c) 2026 Ivan Davidov and Agentic Playwright contributors",
        "Copyright (c) 2026 Petr Kindlmann",
        "Permission is hereby granted, free of charge",
        "THE SOFTWARE IS PROVIDED \"AS IS\"",
    ):
        if value not in third:
            report.fail(f"third-party notices are missing {value}")
    if third.count("MIT License") < 2 or third.count("Permission is hereby granted, free of charge") < 2:
        report.fail("both complete upstream MIT permission notices must be preserved")
    for value in ADAPTED_NOTICE_PATHS:
        if value not in third:
            report.fail(f"third-party notices do not cover adapted path {value}")
    for value in ROOT_NOTICE_PATHS:
        if value not in notice:
            report.fail(f"root NOTICE does not cover adapted path or category {value}")
    install_path = root / "install.sh"
    integration_path = root / "docs" / "integration.md"
    if not install_path.is_file() or not integration_path.is_file():
        report.fail("install.sh and docs/integration.md are required for distribution notice checks")
    else:
        install = install_path.read_text(encoding="utf-8")
        integration = integration_path.read_text(encoding="utf-8")
        for value in (".claude/schemas", "NOTICE.qa-agent-blueprint", "opencode_notice_links", "integrate_notices"):
            if value not in install:
                report.fail(f"installer is missing distribution marker {value}")
        for value in ("NOTICE.qa-agent-blueprint", ".claude/schemas", "THIRD_PARTY_NOTICES.md"):
            if value not in integration:
                report.fail(f"integration documentation is missing distribution marker {value}")
    if report.failures == 0:
        report.ok("root and per-skill upstream notices are complete")
        report.ok("adapted paths and install-time notice distribution are covered")


def check_frontmatter(root, report):
    paths = sorted((root / ".claude" / "skills").glob("*/SKILL.md"))
    if not paths:
        report.fail("no SKILL.md files found")
        return
    valid = 0
    for path in paths:
        name = path.parent.name
        fields = license_fields(path)
        if fields is None:
            report.fail(f"{name}: missing parseable frontmatter")
            continue
        if len(fields) != 1:
            report.fail(f"{name}: expected exactly one license field, got {len(fields)}")
            continue
        value = fields[0]
        if value not in ALLOWED_LICENSES:
            report.fail(f"{name}: unsupported or malformed SPDX expression {value!r}")
            continue
        if name in MIXED_SKILLS and {part.strip() for part in value.split("AND")} != {"MIT", "Apache-2.0"}:
            report.fail(f"{name}: adapted upstream MIT and blueprint Apache-2.0 must both be declared")
            continue
        valid += 1
    if valid == len(paths):
        report.ok(f"all {len(paths)} skills have one attribution-compatible SPDX license")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    args = parser.parse_args()
    root = args.root.resolve()
    report = Report()
    try:
        check_versions(root, report)
        check_notices(root, report)
        check_frontmatter(root, report)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        report.fail(f"release check could not read inputs: {exc}")
    if report.failures:
        print(f"{report.failures} release convention check(s) failed")
        return 1
    print("release conventions passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Sn4kyGit, Anna Mazurek

import argparse
import json
import os
import shutil
import sys

OPENCODE_LINKS = {
    ".opencode/ROUTER.md": "opencode/ROUTER.md",
    ".opencode/agents": "opencode/agents",
    ".opencode/commands": "opencode/commands",
    ".opencode/plugins": "opencode/plugins",
}
CLAUDE_LINKS = {
    ".claude/agents": ".claude/agents",
    ".claude/hooks": ".claude/hooks",
    ".claude/rules": ".claude/rules",
    ".claude/scripts": ".claude/scripts",
    ".claude/skills": ".claude/skills",
}


def lexists(path):
    return os.path.lexists(path)


def read_json(path, jsonc=False):
    with open(path, "r", encoding="utf-8") as handle:
        text = handle.read()
    if jsonc:
        text = strip_jsonc(text)
    value = json.loads(text)
    if not isinstance(value, dict):
        raise ValueError("configuration root is not an object")
    return value


def strip_jsonc(text):
    out = []
    i = 0
    in_string = False
    escaped = False
    while i < len(text):
        char = text[i]
        if in_string:
            out.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            i += 1
        elif char == '"':
            in_string = True
            out.append(char)
            i += 1
        elif char == "/" and i + 1 < len(text) and text[i + 1] == "/":
            i += 2
            while i < len(text) and text[i] != "\n":
                i += 1
        elif char == "/" and i + 1 < len(text) and text[i + 1] == "*":
            end = text.find("*/", i + 2)
            i = len(text) if end < 0 else end + 2
        else:
            out.append(char)
            i += 1
    cleaned = []
    in_string = False
    escaped = False
    for char in "".join(out):
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
            cleaned.append(char)
        elif char in "]}":
            while cleaned and cleaned[-1].isspace():
                cleaned.pop()
            if cleaned and cleaned[-1] == ",":
                cleaned.pop()
            cleaned.append(char)
        else:
            cleaned.append(char)
    return "".join(cleaned)


def qa_home_of(start):
    current = start
    home = os.path.realpath(os.path.expanduser("~"))
    while True:
        marker = lexists(os.path.join(current, ".qa-home"))
        legacy = all(os.path.isdir(os.path.join(current, name)) for name in ("projects", "memory", "evidence"))
        if marker or legacy:
            return current
        parent = os.path.dirname(current)
        if current == home or parent == current:
            return start
        current = parent


def blueprint_root(session):
    router = os.path.join(session, ".opencode", "ROUTER.md")
    if os.path.islink(router) and os.path.exists(router):
        resolved = os.path.realpath(router)
        if os.path.basename(resolved) == "ROUTER.md" and os.path.basename(os.path.dirname(resolved)) == "opencode":
            return os.path.dirname(os.path.dirname(resolved))
    claude = os.path.join(session, ".claude")
    if os.path.islink(claude) and os.path.exists(claude):
        resolved = os.path.realpath(claude)
        if os.path.basename(resolved) == ".claude":
            return os.path.dirname(resolved)
    return None


def url_host(value):
    if not isinstance(value, str) or "://" not in value:
        return None
    authority = value.split("://", 1)[1].split("/", 1)[0].split("?", 1)[0]
    authority = authority.rsplit("@", 1)[-1]
    if authority.startswith("[") and "]" in authority:
        return authority[1:authority.index("]")]
    if authority.count(":") == 1:
        authority = authority.rsplit(":", 1)[0]
    return authority or None


def command_parts(entry, opencode):
    command = entry.get("command")
    if opencode:
        return [str(part) for part in command] if isinstance(command, list) else []
    args = entry.get("args") if isinstance(entry.get("args"), list) else []
    if not isinstance(command, str):
        return []
    return [command] + [str(part) for part in args]


def flag_value(parts, flag):
    value = None
    for index, part in enumerate(parts):
        if part == flag:
            value = parts[index + 1] if index + 1 < len(parts) else None
        elif part.startswith(flag + "="):
            value = part.split("=", 1)[1]
    return value


def inside_evidence(value, session, qa_home):
    if not isinstance(value, str) or not value or value.startswith("--"):
        return False
    candidate = os.path.realpath(os.path.join(session, value))
    evidence = os.path.realpath(os.path.join(qa_home, "evidence"))
    try:
        return os.path.commonpath((candidate, evidence)) == evidence
    except ValueError:
        return False


class Report:
    def __init__(self):
        self.level = 0
        self.findings = []
        self.human = []

    def add(self, level, text):
        severity = {"OK": 0, "INFO": 0, "WARN": 1, "BLOCK": 2}[level]
        self.level = max(self.level, severity)
        item = (level, text)
        if item not in self.findings:
            self.findings.append(item)

    def step(self, text):
        if text not in self.human:
            self.human.append(text)


def plugin_state(session, home, report):
    scopes = []
    paths = [(os.path.join(session, ".claude", "settings.json"), "project")]
    user_path = os.path.join(home, ".claude", "settings.json")
    if os.path.realpath(user_path) != os.path.realpath(paths[0][0]):
        paths.append((user_path, "user"))
    for path, scope in paths:
        if not os.path.isfile(path):
            continue
        try:
            settings = read_json(path)
        except (OSError, UnicodeError, ValueError, json.JSONDecodeError):
            report.add("BLOCK", scope + " Claude settings are malformed; plugin state cannot be verified")
            continue
        enabled = settings.get("enabledPlugins")
        if isinstance(enabled, dict) and enabled.get("qa-agent-blueprint@qa-agent-blueprint-marketplace") is True:
            scopes.append(scope)
    return scopes


def surface_state(session, root, report):
    state = {"missing": [], "valid": [], "opencode": False, "shared": False}
    claude_path = os.path.join(session, ".claude")
    whole_claude = os.path.islink(claude_path)
    if whole_claude:
        if not os.path.exists(claude_path):
            report.add("BLOCK", "dangling symlink: .claude")
        elif root and os.path.realpath(claude_path) != os.path.realpath(os.path.join(root, ".claude")):
            report.add("BLOCK", "foreign symlink: .claude")
    elif lexists(claude_path) and not os.path.isdir(claude_path):
        report.add("BLOCK", "real collision: .claude is not a directory")

    links = dict(OPENCODE_LINKS)
    if not whole_claude:
        links.update(CLAUDE_LINKS)
    for relative, source in links.items():
        path = os.path.join(session, relative)
        if not lexists(path):
            state["missing"].append(relative)
            continue
        if relative.startswith(".opencode/"):
            state["opencode"] = True
        if not os.path.islink(path):
            report.add("BLOCK", "real collision: " + relative + " is not a selective symlink")
            continue
        if not os.path.exists(path):
            report.add("BLOCK", "dangling symlink: " + relative)
            continue
        if root is None:
            report.add("BLOCK", "symlink root cannot be verified: " + relative)
            continue
        expected = os.path.realpath(os.path.join(root, source))
        if os.path.realpath(path) != expected:
            report.add("BLOCK", "foreign symlink: " + relative)
            continue
        state["valid"].append(relative)

    state["shared"] = (
        os.path.isdir(claude_path)
        and not whole_claude
        and root is not None
        and not state["missing"]
        and len(state["valid"]) == len(OPENCODE_LINKS) + len(CLAUDE_LINKS)
    )
    return state


def shared_claude_contract(session, root, report):
    router_path = os.path.join(session, "CLAUDE.md")
    source_router = os.path.join(root, "CLAUDE.md")
    try:
        with open(router_path, "r", encoding="utf-8") as handle:
            consumer_router = handle.read().strip()
        with open(source_router, "r", encoding="utf-8") as handle:
            blueprint_router = handle.read().strip()
        start = "<!-- >>> qa-agent-blueprint (managed, do not edit) -->"
        end = "<!-- <<< qa-agent-blueprint -->"
        managed = start in consumer_router and end in consumer_router
        managed_router = consumer_router.split(start, 1)[1].split(end, 1)[0].strip() if managed else ""
        if consumer_router != blueprint_router and managed_router != blueprint_router:
            report.add("BLOCK", "shared CLAUDE.md does not contain the current full blueprint router")
    except (OSError, UnicodeError):
        report.add("BLOCK", "shared Claude router is missing or unreadable: CLAUDE.md")
    settings_path = os.path.join(session, ".claude", "settings.json")
    source_settings = os.path.join(root, ".claude", "settings.json")
    try:
        consumer = read_json(settings_path)
        blueprint = read_json(source_settings)
        def pairs(config):
            result = set()
            hooks = config.get("hooks", {})
            if not isinstance(hooks, dict):
                raise ValueError("hooks must be an object")
            for event, entries in hooks.items():
                if not isinstance(entries, list):
                    raise ValueError("hook entries must be arrays")
                for entry in entries:
                    if not isinstance(entry, dict) or not isinstance(entry.get("hooks", []), list):
                        raise ValueError("hook entry must be an object with a hooks array")
                    for hook in entry.get("hooks", []):
                        if not isinstance(hook, dict):
                            raise ValueError("hook must be an object")
                        matcher = entry.get("matcher")
                        command = hook.get("command")
                        if matcher is not None and not isinstance(matcher, str):
                            raise ValueError("hook matcher must be a string or null")
                        if not isinstance(command, str):
                            raise ValueError("hook command must be a string")
                        result.add((event, matcher, command))
            return result
        def denies(config):
            permissions = config.get("permissions", {})
            if not isinstance(permissions, dict) or not isinstance(permissions.get("deny", []), list):
                raise ValueError("permissions.deny must be an array")
            values = permissions.get("deny", [])
            if not all(isinstance(value, str) for value in values):
                raise ValueError("permissions.deny entries must be strings")
            return set(values)
        if not pairs(blueprint).issubset(pairs(consumer)):
            report.add("BLOCK", "shared Claude settings are missing blueprint hook pairs")
        if not denies(blueprint).issubset(denies(consumer)):
            report.add("BLOCK", "shared Claude settings are missing blueprint permission denies")
    except (OSError, UnicodeError, ValueError, json.JSONDecodeError):
        report.add("BLOCK", "shared Claude settings are missing or unreadable: .claude/settings.json")


def integrated_install(session):
    if os.path.isdir(os.path.join(session, ".claude", "rules", "qa-blueprint")):
        return True
    path = os.path.join(session, "CLAUDE.md")
    if not os.path.isfile(path):
        return False
    try:
        with open(path, "r", encoding="utf-8") as handle:
            text = handle.read()
        return "<!-- >>> qa-agent-blueprint (managed, do not edit) -->" in text and ".claude/rules/qa-blueprint/" in text
    except (OSError, UnicodeError):
        return False


def optional_links(session, qa_home, root, report):
    docs = os.path.join(session, "docs")
    if os.path.islink(docs):
        if not os.path.exists(docs):
            report.add("BLOCK", "dangling symlink: docs")
        elif root and os.path.realpath(docs) != os.path.realpath(os.path.join(root, "docs")):
            report.add("BLOCK", "foreign symlink: docs")
    agents = os.path.join(qa_home, ".agents")
    if os.path.islink(agents):
        if not os.path.exists(agents):
            report.add("BLOCK", "dangling symlink: .agents")
        elif root is None or os.path.realpath(agents) != os.path.realpath(os.path.join(root, ".agents")):
            report.add("BLOCK", "foreign symlink: .agents")
        if os.path.isdir(os.path.join(agents, "qa-project-context")):
            report.add("WARN", "data preservation: .agents symlink contains project/product bridge files")


def config_paths(session, report):
    mcp = os.path.join(session, ".mcp.json")
    opencode_json = os.path.join(session, "opencode.json")
    opencode_jsonc = os.path.join(session, "opencode.jsonc")
    if lexists(opencode_json) and lexists(opencode_jsonc):
        report.add("BLOCK", "real collision: both opencode.json and opencode.jsonc exist")
    opencode = opencode_json if lexists(opencode_json) else opencode_jsonc
    return mcp, opencode


def audit_playwright(name, entry, opencode, session, qa_home, report):
    if not isinstance(entry, dict):
        report.add("WARN", name + " playwright entry is invalid")
        return
    parts = command_parts(entry, opencode)
    if not parts:
        if entry.get("url") or entry.get("type") == "remote":
            report.add("WARN", name + " playwright is remote; local evidence flags need human verification")
        else:
            report.add("WARN", name + " playwright has no local command")
        return
    report.add("OK", name + " playwright local command found")
    wrapped = any(part.endswith("qa-secrets.mjs") for part in parts) and "mcp" in parts
    if wrapped:
        wrapper_index = next(index for index, part in enumerate(parts) if part.endswith("qa-secrets.mjs"))
        wrapper = parts[wrapper_index]
        wrapper_path = os.path.join(session, wrapper)
        if not os.path.isfile(wrapper_path):
            report.add("WARN", name + " playwright secrets wrapper is missing")
        report.add("OK", name + " playwright uses the secrets wrapper")
    else:
        secrets = flag_value(parts, "--secrets")
        if not secrets:
            report.add("WARN", name + " playwright has neither --secrets nor the wrapper")
        elif not lexists(os.path.join(session, secrets)):
            report.add("WARN", name + " playwright secrets file is absent (existence only)")
        else:
            report.add("OK", name + " playwright secrets file exists (content not read)")
    config = flag_value(parts, "--config")
    if not config:
        report.add("WARN", name + " playwright --config is missing")
    elif not os.path.isfile(os.path.join(session, config)):
        report.add("WARN", name + " playwright config file is absent")
    output_dir = flag_value(parts, "--output-dir")
    if not inside_evidence(output_dir, session, qa_home):
        report.add("BLOCK", name + " playwright --output-dir must realpath inside QA-home evidence")
    if flag_value(parts, "--image-responses") != "omit":
        report.add("WARN", name + " playwright --image-responses must be omit")


def audit_atlassian(name, entry, opencode, report, deployments, dc_hosts):
    if not isinstance(entry, dict):
        report.add("WARN", name + " atlassian entry is invalid")
        return
    parts = command_parts(entry, opencode)
    url = entry.get("url")
    if parts:
        deployments.add("dc")
        environment = entry.get("environment") if isinstance(entry.get("environment"), dict) else entry.get("env")
        jira_url = environment.get("JIRA_URL") if isinstance(environment, dict) else None
        host = url_host(jira_url)
        if host:
            dc_hosts.add(host)
        report.add("OK", name + " atlassian local Data Center" + (" (host " + host + ")" if host else ""))
        return
    if isinstance(url, str):
        base, separator, query = url.partition("?")
        if base != "https://mcp.atlassian.com/v2/mcp":
            report.add("WARN", name + " atlassian remote is not the Cloud v2 endpoint")
        elif separator and any(part.split("=", 1) == ["tools", "all"] for part in query.split("&")):
            report.add("WARN", name + " atlassian Cloud v2 must not use tools=all")
        else:
            deployments.add("cloud")
            report.add("OK", name + " atlassian remote Cloud v2 without tools=all")
        return
    report.add("WARN", name + " atlassian has neither local command nor remote URL")


def audit_config(path, kind, session, qa_home, report, deployments, dc_hosts):
    label = ".mcp.json" if kind == "claude" else os.path.basename(path)
    try:
        config = read_json(path, jsonc=kind == "opencode")
    except (OSError, UnicodeError, ValueError, json.JSONDecodeError):
        report.add("BLOCK", label + " is malformed or unreadable")
        return
    servers = config.get("mcpServers") if kind == "claude" else config.get("mcp")
    if not isinstance(servers, dict):
        report.add("WARN", label + " has no MCP server map")
        return
    expected = {"playwright", "atlassian"}
    if set(servers) != expected:
        report.add("WARN", label + " MCP whitelist must contain exactly playwright and atlassian")
    for name in ("playwright", "atlassian"):
        if name not in servers:
            report.add("WARN", label + " is missing " + name)
    if "playwright" in servers:
        audit_playwright(label, servers["playwright"], kind == "opencode", session, qa_home, report)
    if "atlassian" in servers:
        audit_atlassian(label, servers["atlassian"], kind == "opencode", report, deployments, dc_hosts)


def prerequisites(target, dc_hosts, report):
    if shutil.which(target) is None:
        report.add("BLOCK", target + " CLI not found on PATH")
    else:
        report.add("OK", target + " CLI found on PATH (version not invoked)")
    if shutil.which("node") is None:
        report.add("BLOCK", "node not found on PATH; Node >=18 is required")
    else:
        report.add("OK", "node found on PATH; >=18 remains a human version check")
    if dc_hosts and shutil.which("uv") is None:
        report.add("INFO", "uv is a Data Center prerequisite hint only; no installer was run")


def common_steps(target, session, deployments, dc_hosts, report, shared):
    if shared:
        report.step("Open the " + target + " extension in " + session + "; no install or onboarding is needed")
    else:
        report.step("After human-approved migration, open " + target + " in " + session + "; do not re-onboard")
    if "cloud" in deployments:
        report.step("Atlassian Cloud: complete OAuth once in this harness if it has not been completed there")
    if "dc" in deployments:
        report.step("Data Center: reuse the existing JIRA_PAT_<jira-host> keychain entry; do not copy tokens")
    if target == "claude":
        report.step("Restart Claude Code and accept the trust dialog")
    else:
        report.step("Restart opencode, connect a provider, and choose a model")
    report.step("Use the harnesses sequentially; never run parallel stage tests")
    report.step("The regular preflight runs at the next test, not during this check")


def execute(target, cwd):
    session = os.path.realpath(os.path.abspath(cwd))
    qa_home = qa_home_of(session)
    home = os.path.realpath(os.path.expanduser("~"))
    other = "opencode" if target == "claude" else "claude"
    report = Report()
    root = blueprint_root(session)
    scopes = plugin_state(session, home, report)
    surface = surface_state(session, root, report)
    if surface["shared"]:
        shared_claude_contract(session, root, report)
    integrated = integrated_install(session)
    mcp_path, opencode_path = config_paths(session, report)
    mcp_exists = os.path.isfile(mcp_path)
    opencode_exists = os.path.isfile(opencode_path)
    shared_form = surface["shared"] and mcp_exists and opencode_exists and not integrated and report.level < 2
    claude_install = bool(scopes) or integrated or surface["shared"]
    no_op = False
    if not shared_form:
        if target == "claude" and claude_install and not surface["opencode"] and not os.path.islink(os.path.join(session, ".claude")):
            no_op = True
        elif target == "opencode" and surface["opencode"] and not claude_install:
            no_op = True
    source = target if no_op else other

    if no_op:
        report = Report()
        report.add("OK", "NO_OP: " + target + " is already the active local installation")
    else:
        if not claude_install and not surface["opencode"] and not os.path.islink(os.path.join(session, ".claude")):
            report.add("BLOCK", "no supported source installation detected")
        if integrated:
            report.add("BLOCK", "integrate installation requires manual collision review before shared migration")
        if scopes:
            report.add("INFO", "active Claude plugin scope: " + ", ".join(scopes))
            if surface["opencode"] or integrated or surface["shared"] or os.path.islink(os.path.join(session, ".claude")):
                report.add("BLOCK", "duplicate registration: active plugin plus linked/integrated harness surface")
        for relative in surface["missing"]:
            report.add("INFO", "shared surface not migrated: " + relative + " is absent")
        optional_links(session, qa_home, root, report)
        if not mcp_exists:
            report.add("INFO", ".mcp.json is not present at the session cwd")
        if not opencode_exists:
            report.add("INFO", "opencode.json/jsonc is not present at the session cwd")
        deployments = set()
        dc_hosts = set()
        if "cloud" not in deployments and scopes and not mcp_exists:
            deployments.add("cloud")
        if mcp_exists:
            audit_config(mcp_path, "claude", session, qa_home, report, deployments, dc_hosts)
        if opencode_exists:
            audit_config(opencode_path, "opencode", session, qa_home, report, deployments, dc_hosts)
        for name in ("projects", "memory", "evidence"):
            if not os.path.isdir(os.path.join(qa_home, name)):
                report.add("WARN", "QA data directory is absent: " + name)
        if shared_form:
            report.add("OK", "shared selective .claude and .opencode layout with both MCP configs")
        else:
            report.add("WARN", "installation is not migrated to the shared layout")
            report.step("Human suggestion only, never executed by this check: install.sh --mode shared --dry-run --target " + session)
        prerequisites(target, dc_hosts, report)
        common_steps(target, session, deployments, dc_hosts, report, shared_form)

    if no_op:
        prerequisites(target, set(), report)
    status = ("READY", "READY_WITH_HUMAN_STEPS", "BLOCKED")[report.level]
    print("SOURCE=" + source)
    print("TARGET=" + target)
    print("QA home=" + qa_home)
    print("STATUS=" + status)
    print("Findings:")
    for level, text in report.findings:
        print("- " + level + ": " + text)
    if report.human:
        print("Human steps:")
        for index, text in enumerate(report.human, 1):
            print(str(index) + ". " + text)
    return 2 if status == "BLOCKED" else 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("target", choices=("claude", "opencode"))
    parser.add_argument("--cwd", default=os.getcwd())
    args = parser.parse_args()
    if not os.path.isdir(args.cwd):
        parser.error("--cwd must be an existing directory")
    return execute(args.target, args.cwd)


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Sn4kyGit

#
# manifest-conventions.sh — guards the manifest against the bug class that
# killed v0.2.0 in the field: a component-path key in plugin.json pointing at
# the SAME file Claude Code already auto-discovers by convention. The loader
# then registers the component twice and the plugin fails to load at all
# ("Duplicate hooks file detected") — while `claude plugin validate` happily
# passes it. Loud failure, deterministic check: belongs to a fixture.
#
# Convention locations (plugin root, auto-discovered):
#   hooks/hooks.json, .mcp.json, .lsp.json, skills/, agents/, commands/
# Declaring any of these via plugin.json is at best redundant, at worst a
# duplicate load. Custom paths (e.g. skills → ./.claude/skills) are fine.
#
# Also asserted here: plugin.json and marketplace.json versions must agree —
# the tag command checks it, this fixture catches it earlier.
#
# Usage:  bash .claude/hooks/tests/manifest-conventions.sh
# Exit:   0 = all fixtures pass, otherwise the number of failures.
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
MANIFEST="$ROOT/.claude-plugin/plugin.json"
MARKETPLACE="$ROOT/.claude-plugin/marketplace.json"

[ -f "$MANIFEST" ] || { echo "plugin.json not found at $MANIFEST" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || { echo "python3 required" >&2; exit 1; }

python3 - "$MANIFEST" "$MARKETPLACE" <<'PY'
import json, os, re, sys

manifest_path, marketplace_path = sys.argv[1], sys.argv[2]
root = os.path.dirname(os.path.dirname(manifest_path))

with open(manifest_path) as fh:
    manifest = json.load(fh)

fails = 0

def ok(name):
    print(f"ok    {name}")

def fail(name, why):
    global fails
    fails += 1
    print(f"FAIL  {name}\n      {why}")

# key in plugin.json -> convention path (relative to plugin root) that the
# loader auto-discovers. A declared path resolving to one of these duplicates
# (hooks/mcpServers/lspServers: additive) or pointlessly restates (agents/
# commands: replace-semantics) the convention load.
CONVENTIONS = {
    "hooks": ["hooks/hooks.json"],
    "mcpServers": [".mcp.json"],
    "lspServers": [".lsp.json"],
    "skills": ["skills", "skills/"],
    "agents": ["agents", "agents/"],
    "commands": ["commands", "commands/"],
    "outputStyles": ["output-styles", "output-styles/"],
}

def norm(p):
    return os.path.normpath(p).replace(os.sep, "/")

declared_any = False
for key, conv_paths in CONVENTIONS.items():
    value = manifest.get(key)
    if value is None:
        continue
    # Inline config (object) cannot collide with a file path.
    if isinstance(value, dict):
        ok(f"'{key}' is inline config — no path collision possible")
        continue
    paths = value if isinstance(value, list) else [value]
    for p in paths:
        if not isinstance(p, str):
            continue
        declared_any = True
        n = norm(p)
        if n in [norm(c) for c in conv_paths]:
            fail(f"'{key}' must not declare convention path '{p}'",
                 f"'{n}' is auto-discovered by the loader — declaring it loads the "
                 f"component TWICE (v0.2.0 shipped 'hooks: ./hooks/hooks.json' and the "
                 f"plugin failed to load anywhere). Drop the key; keep the file.")
        else:
            ok(f"'{key}' points at custom path '{p}' (not the convention path)")

if not declared_any:
    ok("no component-path keys declare file paths (all convention loading)")

# Version agreement between the two manifests (the tag command enforces this
# at release time; catch drift earlier, here).
if os.path.exists(marketplace_path):
    with open(marketplace_path) as fh:
        marketplace = json.load(fh)
    mv = None
    for plugin in marketplace.get("plugins", []):
        if plugin.get("name") == manifest.get("name"):
            mv = plugin.get("version")
            break
    pv = manifest.get("version")
    if mv is None:
        fail("marketplace lists the plugin", f"no entry named '{manifest.get('name')}' in marketplace.json")
    elif mv != pv:
        fail("manifest versions agree", f"plugin.json={pv} but marketplace.json={mv}")
    else:
        ok(f"manifest versions agree ({pv})")

claude_models = {
    "test-executor": "sonnet",
    "test-executor-cheap": "haiku",
    "test-executor-deep": "opus",
    "test-automator": "sonnet",
    "test-automator-cheap": "haiku",
    "test-automator-deep": "opus",
    "qa-manager": "inherit",
    "failure-analyst": "inherit",
    "bug-reporter": "inherit",
}
claude_dir = os.path.join(root, ".claude", "agents")
actual_names = {name[:-3] for name in os.listdir(claude_dir) if name.endswith(".md")}
if actual_names == set(claude_models):
    ok("Claude agent inventory is exactly the 9 expected agents")
else:
    fail("Claude agent inventory is exactly the 9 expected agents",
         f"missing={sorted(set(claude_models) - actual_names)}, extra={sorted(actual_names - set(claude_models))}")
claude_texts = {}
for agent, expected in claude_models.items():
    path = os.path.join(claude_dir, agent + ".md")
    if not os.path.exists(path):
        fail(f"Claude agent {agent} model", f"{path} missing")
        continue
    with open(path) as fh:
        text = fh.read()
    claude_texts[agent] = text
    match = re.search(r"(?m)^model:\s*(\S+)\s*$", text)
    actual = match.group(1) if match else None
    name_match = re.search(r"(?m)^name:\s*(\S+)\s*$", text)
    actual_name = name_match.group(1) if name_match else None
    if actual != expected:
        fail(f"Claude agent {agent} model", f"expected {expected}, got {actual}")
    elif actual_name != agent:
        fail(f"Claude agent {agent} name", f"expected {agent}, got {actual_name}")
    else:
        ok(f"Claude agent {agent} model: {expected}")
for family in ("test-executor", "test-automator"):
    base = claude_texts.get(family, "")
    tools = re.search(r"(?m)^tools:\s*(.*)$", base)
    for lane in (family + "-cheap", family + "-deep"):
        lane_text = claude_texts.get(lane, "")
        lane_tools = re.search(r"(?m)^tools:\s*(.*)$", lane_text)
        if tools and lane_tools and tools.group(1) == lane_tools.group(1):
            ok(f"Claude {lane} permissions match {family}")
        else:
            fail(f"Claude {lane} permissions match {family}", "tools frontmatter differs")
        if base and lane_text and base.split("---\n", 2)[2] == lane_text.split("---\n", 2)[2]:
            ok(f"Claude {lane} body exactly matches {family}")
        else:
            fail(f"Claude {lane} body exactly matches {family}", "role body differs")

print()
if fails:
    print(f"{fails} fixture(s) failed")
else:
    print("all fixtures passed")
sys.exit(fails)
PY
FAILS_A=$?

# ---------------------------------------------------------------------------
# opencode conventions (docs/opencode-port-plan.md §4 layer 2). The opencode
# variant lives under opencode/ and is model-agnostic (D6); these checks guard
# its contracts. Until the port lands, they fail by design (red phase).
# ---------------------------------------------------------------------------
python3 - "$ROOT" <<'PY'
import glob, json, os, re, sys

root = sys.argv[1]
oc = os.path.join(root, "opencode")
fails = 0

def ok(name):
    print(f"ok    {name}")

def fail(name, why):
    global fails
    fails += 1
    print(f"FAIL  {name}\n      {why}")

def parse_jsonc(text):
    # strip // and /* */ comments in one pass, never inside a quoted string —
    # the template legitimately carries URLs (atlassian SSE endpoint, $schema)
    # and glob patterns (`**/evidence/**` contains /* and */). Good enough for
    # our own template — we control its shape (no escaped quotes in strings).
    out, i, n = [], 0, len(text)
    in_str = False
    while i < n:
        c = text[i]
        if in_str:
            out.append(c)
            if c == '"':
                in_str = False
            i += 1
        elif c == '"':
            in_str = True
            out.append(c)
            i += 1
        elif c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
        elif c == "/" and i + 1 < n and text[i + 1] == "*":
            end = text.find("*/", i + 2)
            i = n if end == -1 else end + 2
        else:
            out.append(c)
            i += 1
    return json.loads("".join(out))

MINI_YAML_ALLOWED = {"name", "description", "license", "compatibility", "metadata"}

def mini_yaml_frontmatter(path):
    """Parse the restricted frontmatter subset our SKILL/agent files use:
    `key: value` single-line and `key: >-` / `>` / `|-` / `|` folded blocks.
    Returns (fields_dict, error). Not a general YAML parser."""
    with open(path) as fh:
        text = fh.read()
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not m:
        return None, "no frontmatter"
    lines = m.group(1).split("\n")
    fields, i = {}, 0
    while i < len(lines):
        line = lines[i]
        if not line.strip():
            i += 1
            continue
        km = re.match(r"^([a-zA-Z_-]+):\s*(.*)$", line)
        if not km:
            return None, f"unparseable line: {line!r}"
        key, val = km.group(1), km.group(2)
        if val in (">-", ">", "|-", "|"):
            parts, i = [], i + 1
            while i < len(lines) and (lines[i].startswith("  ") or not lines[i].strip()):
                if lines[i].strip():
                    parts.append(lines[i].strip())
                i += 1
            val = " ".join(parts) if val.startswith(">") else "\n".join(parts)
            fields[key] = val
            continue
        if val == "":
            # nested block (e.g. `metadata:` followed by indented key: value
            # lines) — presence of the key is all the allowlist check needs;
            # skip the indented body.
            i += 1
            while i < len(lines) and (lines[i].startswith("  ") or not lines[i].strip()):
                i += 1
            fields[key] = ""
            continue
        fields[key] = val
        i += 1
    return fields, None

if not os.path.isdir(oc):
    fail("opencode/ directory exists", f"{oc} missing — the port has not started (expected red in phase 1)")
    print()
    print(f"{fails} fixture(s) failed")
    sys.exit(fails)

# (1) version agreement across plugin.json, marketplace.json and the opencode
#     template stamp (`// blueprint-version: X.Y.Z` comment line).
with open(os.path.join(root, ".claude-plugin", "plugin.json")) as fh:
    pv = json.load(fh)["version"]
tpl_path = os.path.join(oc, "opencode.template.jsonc")
if not os.path.exists(tpl_path):
    fail("opencode template exists with version stamp", f"{tpl_path} missing")
else:
    with open(tpl_path) as fh:
        tpl_text = fh.read()
    m = re.search(r"^//\s*blueprint-version:\s*(\S+)", tpl_text, re.M)
    if not m:
        fail("opencode template version stamp", "no `// blueprint-version: X.Y.Z` comment line")
    elif m.group(1) != pv:
        fail("opencode template version stamp", f"template={m.group(1)} but plugin.json={pv}")
    else:
        ok(f"opencode template version agrees ({pv})")

# (2) no Claude-style mcp__ tool names anywhere under opencode/ (D5). Markdown
#     is model-facing — scanned whole. In TS/JS, `//` comment lines are exempt:
#     a comment documenting the mapping is not a tool reference.
mcp_hits = []
for f in glob.glob(os.path.join(oc, "**", "*.*"), recursive=True):
    if not os.path.isfile(f):
        continue
    is_code = f.endswith((".ts", ".js", ".mts", ".cts"))
    with open(f, errors="replace") as fh:
        for n, line in enumerate(fh, 1):
            if is_code and line.lstrip().startswith("//"):
                continue
            if "mcp__" in line:
                mcp_hits.append(f"{os.path.relpath(f, root)}:{n}")
if mcp_hits:
    fail("no mcp__ tool names under opencode/", "found: " + ", ".join(mcp_hits[:5]))
else:
    ok("no mcp__ tool names under opencode/")

# (3) command <-> skill parity: every opencode/commands/<name>.md has a skill
#     of the same name, and every entry-point skill has a command wrapper.
ENTRY_POINTS = [
    "agentswitch", "bug-report", "deploy-to-stage", "exploratory-testing", "failure-analysis",
    "onboard-product", "onboard-project", "perf-analysis", "qa-help", "qa-report", "re-board",
    "recon", "report-to-jira", "retest-bug", "retro-learn", "scaffold-suite",
    "skill-review", "test-automation", "test-ticket", "whats-new", "model-setup",
]
skills = {os.path.basename(os.path.dirname(p)) for p in glob.glob(os.path.join(root, ".claude", "skills", "*", "SKILL.md"))}
cmds = {os.path.basename(p)[:-3] for p in glob.glob(os.path.join(oc, "commands", "*.md"))}
for c in sorted(cmds):
    if c not in skills:
        fail(f"command '{c}' names an existing skill", f"no .claude/skills/{c}/SKILL.md")
missing = [s for s in ENTRY_POINTS if s not in cmds]
expected_cmds = set(ENTRY_POINTS) | {"demo"}
if missing:
    fail("every entry-point skill has a command wrapper", f"missing commands: {', '.join(missing)}")
elif cmds != expected_cmds:
    fail("command inventory is exactly the 22 expected commands",
         f"missing={sorted(expected_cmds - cmds)}, extra={sorted(cmds - expected_cmds)}")
else:
    ok(f"command <-> skill parity ({len(cmds)} commands)")
for s in ENTRY_POINTS:
    if s not in skills:
        fail(f"entry-point skill '{s}' exists", "listed in ENTRY_POINTS but no such skill")

# (4) template contract: parses as JSONC, carries the MCP contract names,
#     subagent_depth 2 (D: qa-manager spawns sub-subagents), instructions (D4),
#     permission denies (D8), and NO model key (D6).
if os.path.exists(tpl_path):
    try:
        tpl = parse_jsonc(tpl_text)
    except Exception as e:
        fail("opencode template parses as JSONC", str(e))
        tpl = None
    if tpl is not None:
        ok("opencode template parses as JSONC")
        mcp = tpl.get("mcp") or {}
        for srv in ("playwright", "atlassian"):
            if srv not in mcp:
                fail(f"template keeps MCP contract name '{srv}'", "hooks and agents match on this name — docs/rules/core/token-discipline.md")
        if "mcp" in tpl and all(s in mcp for s in ("playwright", "atlassian")):
            ok("template keeps both MCP contract names")
        if tpl.get("subagent_depth") != 2:
            fail("subagent_depth is 2", "qa-manager (subagent) spawns test-executor/test-automator (subagents) — default 1 breaks that")
        else:
            ok("subagent_depth is 2")
        instr = tpl.get("instructions") or []
        if not any("ROUTER.md" in str(i) for i in instr):
            fail("instructions reference ROUTER.md", f"got {instr}")
        else:
            ok("instructions reference the router")
        if "permission" not in tpl:
            fail("template carries permission denies (D8)", "e.g. read: **/evidence/** deny — globs must match absolute paths (S4)")
        else:
            ok("template carries permission denies")
        if "model" in tpl or "small_model" in tpl:
            fail("template has no model key (D6)", "the model is the user's /models choice — the blueprint anchors nothing")
        else:
            ok("template has no model key (D6)")

# (5) agent frontmatter lint: description required, valid mode, no model pin.
agents = sorted(glob.glob(os.path.join(oc, "agents", "*.md")))
expected_agents = {
    "test-executor", "test-executor-cheap", "test-executor-deep",
    "test-automator", "test-automator-cheap", "test-automator-deep",
    "qa-manager", "failure-analyst", "bug-reporter",
}
actual_agents = {os.path.basename(a)[:-3] for a in agents}
if actual_agents == expected_agents:
    ok("opencode agent inventory is exactly the 9 expected agents")
else:
    fail("opencode agent inventory is exactly the 9 expected agents",
         f"missing={sorted(expected_agents - actual_agents)}, extra={sorted(actual_agents - expected_agents)}")
opencode_texts = {}
for a in agents:
    with open(a) as fh:
        opencode_texts[os.path.basename(a)[:-3]] = fh.read()
for a in agents:
    fields, err = mini_yaml_frontmatter(a)
    name = os.path.basename(a)
    if err:
        fail(f"agent {name} frontmatter parses", err)
        continue
    if not fields.get("description"):
        fail(f"agent {name} has a description", "required by opencode")
    elif fields.get("model") or fields.get("variant"):
        fail(f"agent {name} has no model/variant pin (D6)",
             f"model: {fields.get('model')}, variant: {fields.get('variant')}")
    elif fields.get("mode", "subagent") not in ("primary", "subagent", "all"):
        fail(f"agent {name} has a valid mode", f"mode: {fields.get('mode')}")
    else:
        ok(f"agent {name} frontmatter clean")

# (5b) delegation hardening: qa-manager may spawn ONLY the four leaf agents
#     (permission.task glob map, last match wins — "*" deny first), and the
#     leaf agents never delegate (task: deny). Raw-text check: the mini YAML
#     parser deliberately skips nested blocks.
LEAVES = [
    "test-executor", "test-executor-cheap", "test-executor-deep",
    "test-automator", "test-automator-cheap", "test-automator-deep",
    "failure-analyst", "bug-reporter",
]
qm_path = os.path.join(oc, "agents", "qa-manager.md")
qm = open(qm_path).read() if os.path.exists(qm_path) else ""
task_block = re.search(r"(?ms)^  task:\n((?:^    .*\n)+)", qm)
allowed_leaves = re.findall(r"^    ([a-z0-9-]+): allow$", task_block.group(1), re.M) if task_block else []
if task_block and '"*": deny' in task_block.group(1) and set(allowed_leaves) == set(LEAVES) and len(allowed_leaves) == 8:
    ok("qa-manager task permission whitelists exactly the 8 leaf agents")
else:
    fail("qa-manager task permission whitelists exactly the 8 leaf agents",
         f"expected '*' deny + exactly {LEAVES}, got {allowed_leaves}")
for leaf in LEAVES:
    p = os.path.join(oc, "agents", f"{leaf}.md")
    text = open(p).read() if os.path.exists(p) else ""
    if re.search(r"(?m)^  task: deny$", text):
        ok(f"{leaf} never delegates (task: deny)")
    else:
        fail(f"{leaf} never delegates (task: deny)", "leaf agents must not spawn subagents")
for family in ("test-executor", "test-automator"):
    base = opencode_texts.get(family, "")
    permission = re.search(r"(?ms)^permission:\n.*?^---$", base)
    for lane in (family + "-cheap", family + "-deep"):
        lane_text = opencode_texts.get(lane, "")
        lane_permission = re.search(r"(?ms)^permission:\n.*?^---$", lane_text)
        if permission and lane_permission and permission.group(0) == lane_permission.group(0):
            ok(f"opencode {lane} permissions match {family}")
        else:
            fail(f"opencode {lane} permissions match {family}", "permission frontmatter differs")
        if base and lane_text and base.split("---\n", 2)[2] == lane_text.split("---\n", 2)[2]:
            ok(f"opencode {lane} body exactly matches {family}")
        else:
            fail(f"opencode {lane} body exactly matches {family}", "role body differs")

# (6) every skill satisfies opencode's constraints (S1): name regex + name ==
#     directory, description 1..1024 chars, only recognized frontmatter fields.
fails_before_skills = fails
for sk in sorted(glob.glob(os.path.join(root, ".claude", "skills", "*", "SKILL.md"))):
    name = os.path.basename(os.path.dirname(sk))
    fields, err = mini_yaml_frontmatter(sk)
    if err:
        fail(f"skill {name} frontmatter parses", err)
        continue
    desc = fields.get("description") or ""
    extra = sorted(set(fields) - MINI_YAML_ALLOWED)
    if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", fields.get("name", "")) or fields.get("name") != name:
        fail(f"skill {name} name valid + matches dir", f"name={fields.get('name')!r}")
    elif not (1 <= len(desc) <= 1024):
        fail(f"skill {name} description within 1..1024", f"len={len(desc)} (opencode rejects >1024 — S1)")
    elif extra:
        fail(f"skill {name} uses only recognized frontmatter fields", f"extra: {extra}")
if fails == fails_before_skills:
    ok("all skills satisfy opencode constraints (name regex, desc ≤1024, field allowlist)")

print()
if fails:
    print(f"{fails} fixture(s) failed")
else:
    print("all fixtures passed")
sys.exit(fails)
PY
FAILS_B=$?

python3 - "$ROOT" <<'PY'
import glob, os, re, sys

root = sys.argv[1]
fails = 0

def ok(name):
    print(f"ok    {name}")

def fail(name, why):
    global fails
    fails += 1
    print(f"FAIL  {name}\n      {why}")

AGENTS = [
    "test-executor", "test-executor-cheap", "test-executor-deep",
    "test-automator", "test-automator-cheap", "test-automator-deep",
    "qa-manager", "failure-analyst", "bug-reporter",
]

def body(text):
    m = re.match(r"^---\n.*?\n---\n", text, re.S)
    return text[m.end():] if m else text

def norm_tools(s):
    return re.sub(r"mcp__(?:plugin_qa-agent-blueprint_)?(atlassian|playwright)__", r"\1_", s)

def squash(s):
    return re.sub(r"\s+", " ", s).strip()

for a in AGENTS:
    cp = os.path.join(root, ".claude", "agents", a + ".md")
    op = os.path.join(root, "opencode", "agents", a + ".md")
    if not (os.path.exists(cp) and os.path.exists(op)):
        fail(f"Claude<->opencode body parity {a}", "agent file missing on one side")
        continue
    c = squash(norm_tools(body(open(cp).read())))
    o = squash(norm_tools(body(open(op).read())))
    if c == o:
        ok(f"Claude<->opencode body parity {a}")
    else:
        i = next((j for j in range(min(len(c), len(o))) if c[j] != o[j]), min(len(c), len(o)))
        lo, hi = max(0, i - 30), i + 30
        fail(f"Claude<->opencode body parity {a}",
             f"content drift at offset {i} (tool names normalized, whitespace ignored): "
             f"claude ...{c[lo:hi]!r} vs opencode ...{o[lo:hi]!r}")

FASTPATH = {"test-ticket", "retest-bug"}
cmd_problems = []
cmd_count = 0
for p in sorted(glob.glob(os.path.join(root, "opencode", "commands", "*.md"))):
    stem = os.path.basename(p)[:-3]
    cmd_count += 1
    text = open(p).read()
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
    if not m:
        cmd_problems.append(f"{stem}: no frontmatter block")
        continue
    fm, body_text = m.group(1), m.group(2).strip()
    am = re.search(r"(?m)^agent:\s*(\S+)\s*$", fm)
    agent = am.group(1) if am else None
    if stem in FASTPATH and agent is not None:
        cmd_problems.append(f"{stem}: Fast Path — must have no agent: field (found agent: {agent})")
    if stem == "demo" and agent is not None:
        cmd_problems.append(f"{stem}: demo runs in the main session and must not delegate (found agent: {agent})")
    if stem not in FASTPATH and stem != "demo" and agent not in (None, "qa-manager"):
        cmd_problems.append(f"{stem}: agent: must be 'qa-manager' or absent (found {agent})")
    expected_body = f"Load skill {stem} and apply it to: $ARGUMENTS"
    if body_text != expected_body:
        cmd_problems.append(f"{stem}: body must be exactly {expected_body!r} (found {body_text!r})")
if cmd_problems:
    for prob in cmd_problems:
        fail("command frontmatter + body lint", prob)
else:
    ok(f"command frontmatter + body lint ({cmd_count} commands)")

skill_mcp = []
skill_plug = []
for sk in sorted(glob.glob(os.path.join(root, ".claude", "skills", "*", "SKILL.md"))):
    name = os.path.basename(os.path.dirname(sk))
    text = open(sk).read()
    for n, line in enumerate(text.splitlines(), 1):
        if "mcp__" in line:
            skill_mcp.append(f"{name}/SKILL.md:{n}: {line.strip()[:70]}")
    for m in re.finditer(r"\$CLAUDE_PLUGIN_ROOT(/[^\s`\"')]+)?", text):
        path = (m.group(1) or "").strip("/")
        if path:
            alts = [mm.start() for mm in re.finditer(re.escape(path), text)
                    if not text[max(0, mm.start() - 19):mm.start()].endswith("$CLAUDE_PLUGIN_ROOT")]
            if not alts:
                skill_plug.append(f"{name}/SKILL.md: {m.group(0)} has no bare relative `{path}`")
        else:
            s = text.rfind("\n\n", 0, m.start()) + 2
            e = text.find("\n\n", m.start())
            e = len(text) if e == -1 else e
            rels = [t for t in re.findall(r"`([^`]+)`", text[s:e]) if "/" in t and not t.startswith("$")]
            if not rels:
                skill_plug.append(f"{name}/SKILL.md: bare $CLAUDE_PLUGIN_ROOT in a paragraph without a relative path")
if skill_mcp:
    for hit in skill_mcp:
        fail("shared skills carry no mcp__ tool names", hit)
else:
    ok("shared skills carry no mcp__ tool names")
if skill_plug:
    for hit in skill_plug:
        fail("shared skills pair $CLAUDE_PLUGIN_ROOT with a relative alternative", hit)
else:
    ok("shared skills pair $CLAUDE_PLUGIN_ROOT with a relative alternative")

claude_path = os.path.join(root, "CLAUDE.md")
router_path = os.path.join(root, "opencode", "ROUTER.md")
if not (os.path.exists(claude_path) and os.path.exists(router_path)):
    fail("CLAUDE.md <-> opencode/ROUTER.md sync", "CLAUDE.md or opencode/ROUTER.md missing")
else:
    claude = open(claude_path).read()
    router = open(router_path).read()
    allowed = [
        (r"A Stop hook enforces this\.",
         r"The evidence gate enforces\s+this \(no JIRA verdict without evidence, end-of-session reminder\)\."),
        (r"The Stop hook blocks the session end without it\.",
         r"The evidence gate blocks JIRA reporting and\s+re-engages the session without it\."),
        (r"headless `claude -p` runs",
         r"headless runs \(`opencode run`, `claude -p`\)"),
    ]
    def canon(t):
        for a, b in allowed:
            t = re.sub(f"(?:{a})|(?:{b})", "<allowed>", t)
        return re.sub(r"\s+", " ", t)
    cc, rc = canon(claude), canon(router)
    if cc == rc:
        ok("CLAUDE.md <-> opencode/ROUTER.md sync (only enforcement/CLI-name hunks differ)")
    else:
        i = next((j for j in range(min(len(cc), len(rc))) if cc[j] != rc[j]), min(len(cc), len(rc)))
        lo, hi = max(0, i - 40), i + 40
        fail("CLAUDE.md <-> opencode/ROUTER.md sync",
             f"unallowed difference at offset {i} (only enforcement terminology + CLI names may differ): "
             f"claude ...{cc[lo:hi]!r} vs opencode ...{rc[lo:hi]!r}")

print()
if fails:
    print(f"{fails} fixture(s) failed")
else:
    print("all fixtures passed")
sys.exit(fails)
PY
FAILS_C=$?

# --- D: hook matcher parity — hooks.json ↔ settings.json (H12) ---
echo
echo "== hook matcher parity (hooks.json ↔ settings.json) =="
python3 - <<'PY'
import json, sys
fails = 0
with open("hooks/hooks.json") as f:
    h = json.load(f)
with open(".claude/settings.json") as f:
    s = json.load(f)

def matchers(hooks_obj, event):
    return sorted(
        hook.get("matcher", "")
        for hook in hooks_obj.get("hooks", {}).get(event, [])
    )

for event in ("PreToolUse", "PostToolUse"):
    hm = matchers(h, event)
    sm = matchers(s, event)
    if hm != sm:
        print(f"FAIL  {event}: hooks.json={hm} vs settings.json={sm}")
        fails += 1
    else:
        print(f"ok    {event}: {len(hm)} matchers agree")

# Check that the atlassian write matcher is anchored (jira_)? prefix
for source, obj in [("hooks.json", h), ("settings.json", s)]:
    for hook in obj.get("hooks", {}).get("PostToolUse", []):
        m = hook.get("matcher", "")
        if "atlassian" in m and "(jira_)?" not in m:
            print(f"FAIL  {source} PostToolUse: atlassian matcher not anchored: {m}")
            fails += 1

print()
if fails:
    print(f"{fails} fixture(s) failed")
else:
    print("all fixtures passed")
sys.exit(fails)
PY
FAILS_D=$?

# --- E: eval tier files ↔ COVERAGE.md parity (H9) ---
echo
echo "== eval tier parity (tier files are source of truth) =="
python3 - <<'PY'
import os, re, sys
fails = 0
co = open("evals/COVERAGE.md").read()
# Parse COVERAGE.md tier column: | `case-name` | ... | tier |
tier_rows = {}
for m in re.finditer(r'\|\s*`([a-z][a-z0-9-]+)`\s*\|[^|]*\|\s*(hard|variance)\s*\|', co):
    tier_rows[m.group(1)] = m.group(2)
for case_dir in sorted(os.listdir("evals")):
    path = os.path.join("evals", case_dir, "tier")
    if not os.path.isfile(path):
        continue
    tier = open(path).read().strip()
    if case_dir not in tier_rows:
        print(f"FAIL  {case_dir}: tier file says '{tier}' but COVERAGE.md has no row")
        fails += 1
    elif tier_rows[case_dir] != tier:
        print(f"FAIL  {case_dir}: tier file='{tier}' vs COVERAGE.md='{tier_rows[case_dir]}'")
        fails += 1
    else:
        print(f"ok    {case_dir}: {tier}")
for case_dir in sorted(tier_rows):
    path = os.path.join("evals", case_dir, "tier")
    if not os.path.isfile(path):
        print(f"FAIL  {case_dir}: COVERAGE.md says '{tier_rows[case_dir]}' but no tier file exists")
        fails += 1
print()
if fails:
    print(f"{fails} fixture(s) failed")
else:
    print("all fixtures passed")
sys.exit(fails)
PY
FAILS_E=$?

exit $((FAILS_A + FAILS_B + FAILS_C + FAILS_D + FAILS_E))

#!/usr/bin/env bash
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
import json, os, sys

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
    "bug-report", "deploy-to-stage", "exploratory-testing", "failure-analysis",
    "onboard-product", "onboard-project", "qa-help", "qa-report", "re-board",
    "report-to-jira", "retest-bug", "retro-learn", "scaffold-suite",
    "test-automation", "test-ticket", "whats-new",
]
skills = {os.path.basename(os.path.dirname(p)) for p in glob.glob(os.path.join(root, ".claude", "skills", "*", "SKILL.md"))}
cmds = {os.path.basename(p)[:-3] for p in glob.glob(os.path.join(oc, "commands", "*.md"))}
for c in sorted(cmds):
    if c not in skills:
        fail(f"command '{c}' names an existing skill", f"no .claude/skills/{c}/SKILL.md")
missing = [s for s in ENTRY_POINTS if s not in cmds]
if missing:
    fail("every entry-point skill has a command wrapper", f"missing commands: {', '.join(missing)}")
elif cmds:
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
if not agents:
    fail("opencode/agents/ holds the 5 agents", "none found")
for a in agents:
    fields, err = mini_yaml_frontmatter(a)
    name = os.path.basename(a)
    if err:
        fail(f"agent {name} frontmatter parses", err)
        continue
    if not fields.get("description"):
        fail(f"agent {name} has a description", "required by opencode")
    elif fields.get("model"):
        fail(f"agent {name} has no model pin (D6)", f"model: {fields['model']}")
    elif fields.get("mode", "subagent") not in ("primary", "subagent", "all"):
        fail(f"agent {name} has a valid mode", f"mode: {fields.get('mode')}")
    else:
        ok(f"agent {name} frontmatter clean")

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

exit $((FAILS_A + FAILS_B))

// guard.test.ts — opencode port of .claude/hooks/tests/guard-fixtures.sh.
//
// Same policy, different transport: the Claude hook exits 2 + stderr; the
// opencode plugin throws from "tool.execute.before". Every case below mirrors
// a bash fixture by name, so a divergence between the two suites is visible
// by diffing the case lists. Message prefix "BLOCKED by pre-tool-guard:" is
// part of the contract (docs/rules/core/security.md names the hook output).

import { describe, expect, test } from "bun:test"
import { mkdtemp, mkdir, writeFile } from "fs/promises"
import { tmpdir } from "os"
import { join } from "path"
import { qaBlueprint } from "../plugins/qa-blueprint.ts"
import { bashBefore, fakeCtx, fileBefore, unknownBefore, SESSION_ID, type BeforeCall } from "./fixtures/payloads.ts"

async function hooks() {
  const { ctx } = fakeCtx("/tmp/qa-guard-test")
  return qaBlueprint(ctx as never)
}

/** Plugin instance rooted at a fresh temp dir (for projects/<KEY>/PROJECT.md). */
async function hooksIn(dir: string) {
  const { ctx } = fakeCtx(dir)
  return qaBlueprint(ctx as never)
}

async function tempProject(projectMd?: string): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), "qa-shadow-"))
  if (projectMd !== undefined) {
    await mkdir(join(dir, "projects", "SHOP"), { recursive: true })
    await writeFile(join(dir, "projects", "SHOP", "PROJECT.md"), projectMd)
  }
  return dir
}

/** Fresh preflight pass artifact — opens the preflight gate for this dir. */
async function stampPreflight(dir: string, ageMinutes = 0): Promise<void> {
  await mkdir(join(dir, "evidence", ".preflight"), { recursive: true })
  const checkedAt = Math.floor(Date.now() / 1000) - ageMinutes * 60
  await writeFile(join(dir, "evidence", ".preflight", "ok.json"), JSON.stringify({ key: "SHOP", checked_at: checkedAt, ok: true }))
}

function jiraWrite(args: Record<string, unknown>): BeforeCall {
  return {
    input: { tool: "atlassian_editJiraIssue", sessionID: SESSION_ID, callID: "tool_fixture" },
    output: { args },
  }
}

async function run(h: Awaited<ReturnType<typeof hooks>>, call: BeforeCall) {
  return h["tool.execute.before"](call.input as never, call.output as never)
}

const blocked: Array<[string, BeforeCall]> = [
  // == secrets files (.claude/rules/core/security.md) ==
  ["Write .env", fileBefore("write", ".env")],
  ["Write .env.local", fileBefore("write", ".env.local")],
  ["Write .env.playwright-secrets", fileBefore("write", ".env.playwright-secrets")],
  ["Edit deep/.env.production", fileBefore("edit", "/srv/app/.env.production")],
  ["Write id_rsa", fileBefore("write", "/home/u/.ssh/id_rsa")],
  ["Write id_ed25519", fileBefore("write", "/home/u/.ssh/id_ed25519")],
  ["Write cert.pem", fileBefore("write", "/srv/tls/cert.pem")],
  ["Bash redirect >> .env", bashBefore("echo X >> .env")],
  ["Bash cat .env", bashBefore("cat .env")],
  // The exemption strips only the literal ".env.example": copying the template
  // INTO .env is still a write to a secrets file and must stay blocked.
  ["Bash cp template INTO .env", bashBefore("cp .env.example .env")],
  ["Bash cat .env.playwright-secrets", bashBefore("cat .env.playwright-secrets")],
  // grep/sed/awk/jq are readers too — field report 0.6.1: `grep -o '^[A-Z_]*='`
  // on the secrets file bypassed the old cat-only list.
  ["Bash grep keys from .env.playwright-secrets", bashBefore("grep -o ^[A-Z_0-9]*= .env.playwright-secrets")],
  ["Bash grep .env.local", bashBefore("grep PASSWORD .env.local")],
  ["Bash sed reads .env", bashBefore("sed -n 1p .env")],
  ["Bash awk reads .env", bashBefore("awk -F= {print$1} .env")],
  ["Bash jq reads .env", bashBefore("jq . .env")],
  // `source` loads the file into the shell — same leak as cat (audit F4).
  ["Bash source .env", bashBefore("source .env")],
  // Interpreters reading the file bypass the reader-word list (audit F4).
  ["Bash python3 open().read() .env", bashBefore(`python3 -c "print(open('.env').read())"`)],
  ["Bash ruby File.read .env", bashBefore(`ruby -e "puts File.read('.env')"`)],
  // == reserved product-key names (case-insensitive) ==
  ["Write products/SECRET/PRODUCT.md", fileBefore("write", "projects/SHOP/products/SECRET/PRODUCT.md")],
  ["Write products/CREDENTIALS/...", fileBefore("write", "projects/SHOP/products/CREDENTIALS/PRODUCT.md")],
  ["Write mixed-case Credentials dir", fileBefore("write", "/tmp/My-Credentials/notes.md")],
  ["Write lowercase secrets dir", fileBefore("write", "config/secrets/app.yml")],
  // == destructive commands ==
  ["Bash rm -rf", bashBefore("rm -rf build/")],
  ["Bash rm -fr", bashBefore("rm -fr build/")],
  ["Bash git push --force", bashBefore("git push --force origin main")],
  ["Bash git push -f", bashBefore("git push -f origin main")],
  // == fail closed: tool name missing → scan the raw args ==
  ["unknown tool, args mention cat .env", unknownBefore({ command: "cat .env" })],
  ["unknown tool, args name a secret file", unknownBefore({ filePath: ".env.production" })],
]

const allowed: Array<[string, BeforeCall]> = [
  // == the .env.example placeholder template ==
  ["Write .env.example", fileBefore("write", ".env.example")],
  ["Write /repo/.env.example", fileBefore("write", "/repo/.env.example")],
  ["Bash redirect > .env.example", bashBefore("cat > .env.example")],
  ["Bash read .env.example", bashBefore("cat .env.example")],
  ["Bash grep .env.example", bashBefore("grep KEY .env.example")],
  // == prose mentioning a secrets filename is not a read of it ==
  ["pipeline + unrelated echo naming it", bashBefore('ls projects | head -3; echo "note: the dot-env file is a template"')],
  ["grep on ordinary files is not blocked", bashBefore("grep -c KEY README.md")],
  // An interpreter with no read verb is not a secrets read (audit F4 fixture).
  ["python string mentions .env without reading", bashBefore(`python3 -c "note='.env.template'; print(note)"`)],
  // == the sanctioned resolver path stays open ==
  ["Bash resolve-secrets.sh", bashBefore("bash .claude/hooks/resolve-secrets.sh")],
  ["Bash resolve-secrets.sh arg", bashBefore("bash .claude/hooks/resolve-secrets.sh . --status")],
  ["Bash resolver --import", bashBefore("bash .claude/hooks/resolve-secrets.sh . --import")],
  ["Bash resolver --capture", bashBefore("bash .claude/hooks/resolve-secrets.sh . --capture")],
  ["Bash plugin-root resolver", bashBefore("bash $CLAUDE_PLUGIN_ROOT/.claude/hooks/resolve-secrets.sh")],
  // == reads are governed by opencode permissions, not this guard ==
  ["Read .env is not the guard's job", fileBefore("read", ".env")],
  // == ordinary work is unaffected ==
  ["Write a normal file", fileBefore("write", "README.md")],
  ["Bash normal command", bashBefore("npx playwright test")],
]

describe("pre-tool guard (opencode)", () => {
  for (const [name, call] of blocked) {
    test(`blocks: ${name}`, async () => {
      const h = await hooks()
      await expect(run(h, call)).rejects.toThrow(/^BLOCKED by pre-tool-guard:/)
    })
  }
  for (const [name, call] of allowed) {
    test(`allows: ${name}`, async () => {
      const h = await hooks()
      await expect(run(h, call)).resolves.toBeUndefined()
    })
  }
})

// Shadow gate (audit 2026-09-18 F1) — mirrors the "Shadow mode" section of
// guard-fixtures.sh. Default is closed; unlock via PROJECT.md or env var.
describe("shadow gate (opencode)", () => {
  test("blocks JIRA write, shadow default (PROJECT.md without 'off')", async () => {
    const dir = await tempProject("# SHOP\nShadow mode: on\n")
    const h = await hooksIn(dir)
    await expect(run(h, jiraWrite({ issueKey: "SHOP-1" }))).rejects.toThrow(/Shadow Mode is on/)
  })

  test("blocks JIRA write, unresolvable key → fail safe", async () => {
    const dir = await tempProject()
    const h = await hooksIn(dir)
    await expect(run(h, jiraWrite({}))).rejects.toThrow(/Shadow Mode is on/)
  })

  test("blocks unparsable call that looks like an Atlassian write", async () => {
    const dir = await tempProject()
    const h = await hooksIn(dir)
    await expect(run(h, unknownBefore({ payload: "atlassian__createJiraIssue" }))).rejects.toThrow(/Shadow Mode is on/)
  })

  // Atlassian v2 meta-tools (0.10.0): executeWrite/executeDestructive run
  // DEFERRED tools and are writes by definition; executeRead stays open.
  test("blocks executeWrite (deferred tool), shadow default", async () => {
    const dir = await tempProject("# SHOP\nShadow mode: on\n")
    const h = await hooksIn(dir)
    const call: BeforeCall = {
      input: { tool: "atlassian_executeWrite", sessionID: SESSION_ID, callID: "tool_exec" },
      output: { args: { tool: "uploadAttachmentToJiraIssue", arguments: { issueKey: "SHOP-1" } } },
    }
    await expect(run(h, call)).rejects.toThrow(/Shadow Mode is on/)
  })

  test("executeWrite resolves the nested issue key for the audit log", async () => {
    const dir = await tempProject("# SHOP\nShadow mode: off\n")
    await stampPreflight(dir)
    const h = await hooksIn(dir)
    const call: BeforeCall = {
      input: { tool: "atlassian_executeWrite", sessionID: SESSION_ID, callID: "tool_exec2" },
      output: { args: { tool: "uploadAttachmentToJiraIssue", arguments: { issueKey: "SHOP-1" } } },
    }
    await expect(run(h, call)).resolves.toBeUndefined()
  })

  test("executeRead is not a write", async () => {
    const dir = await tempProject("# SHOP\nShadow mode: on\n")
    await stampPreflight(dir)
    const h = await hooksIn(dir)
    const call: BeforeCall = {
      input: { tool: "atlassian_executeRead", sessionID: SESSION_ID, callID: "tool_execr" },
      output: { args: { tool: "listJiraIssueChangelogs", arguments: { issueKey: "SHOP-1" } } },
    }
    await expect(run(h, call)).resolves.toBeUndefined()
  })

  test("allows when PROJECT.md says 'Shadow mode: off'", async () => {
    const dir = await tempProject("# SHOP\nShadow mode: off\n")
    await stampPreflight(dir) // shadow-off fixtures still need the preflight gate open
    const h = await hooksIn(dir)
    await expect(run(h, jiraWrite({ issueKey: "SHOP-1" }))).resolves.toBeUndefined()
  })

  test("allows when QA_AGENT_SHADOW=0", async () => {
    const dir = await tempProject("# SHOP\nShadow mode: on\n")
    await stampPreflight(dir)
    const h = await hooksIn(dir)
    const prev = process.env.QA_AGENT_SHADOW
    process.env.QA_AGENT_SHADOW = "0"
    try {
      await expect(run(h, jiraWrite({ issueKey: "SHOP-1" }))).resolves.toBeUndefined()
    } finally {
      if (prev === undefined) delete process.env.QA_AGENT_SHADOW
      else process.env.QA_AGENT_SHADOW = prev
    }
  })
})

// Preflight gate — mirrors the "preflight gate" section of guard-fixtures.sh.
// No browser/JIRA MCP call until evidence/.preflight/ok.json exists and is
// younger than the TTL; only when a project is onboarded at all.
describe("preflight gate (opencode)", () => {
  const playwrightCall: BeforeCall = {
    input: { tool: "playwright_browser_navigate", sessionID: SESSION_ID, callID: "tool_pf" },
    output: { args: { url: "https://stage.corp.example.com" } },
  }
  const atlassianRead: BeforeCall = {
    input: { tool: "atlassian_getJiraIssue", sessionID: SESSION_ID, callID: "tool_pf" },
    output: { args: { issueKey: "SHOP-1" } },
  }

  test("blocks playwright call, no artifact", async () => {
    const dir = await tempProject("# SHOP\n")
    const h = await hooksIn(dir)
    await expect(run(h, playwrightCall)).rejects.toThrow(/preflight has passed/)
  })

  test("blocks atlassian READ, no artifact (reads need the gate too)", async () => {
    const dir = await tempProject("# SHOP\n")
    const h = await hooksIn(dir)
    await expect(run(h, atlassianRead)).rejects.toThrow(/preflight has passed/)
  })

  test("allows with a fresh artifact", async () => {
    const dir = await tempProject("# SHOP\n")
    await stampPreflight(dir)
    const h = await hooksIn(dir)
    await expect(run(h, playwrightCall)).resolves.toBeUndefined()
    await expect(run(h, atlassianRead)).resolves.toBeUndefined()
  })

  test("blocks a stale artifact (default TTL 60m)", async () => {
    const dir = await tempProject("# SHOP\n")
    await stampPreflight(dir, 120)
    const h = await hooksIn(dir)
    await expect(run(h, playwrightCall)).rejects.toThrow(/preflight has passed/)
  })

  test("allows a stale artifact under a wider TTL env", async () => {
    const dir = await tempProject("# SHOP\n")
    await stampPreflight(dir, 120)
    const h = await hooksIn(dir)
    const prev = process.env.QA_PREFLIGHT_TTL_MIN
    process.env.QA_PREFLIGHT_TTL_MIN = "180"
    try {
      await expect(run(h, playwrightCall)).resolves.toBeUndefined()
    } finally {
      if (prev === undefined) delete process.env.QA_PREFLIGHT_TTL_MIN
      else process.env.QA_PREFLIGHT_TTL_MIN = prev
    }
  })

  test("QA_PREFLIGHT=0 escape hatch", async () => {
    const dir = await tempProject("# SHOP\n")
    const h = await hooksIn(dir)
    const prev = process.env.QA_PREFLIGHT
    process.env.QA_PREFLIGHT = "0"
    try {
      await expect(run(h, playwrightCall)).resolves.toBeUndefined()
    } finally {
      if (prev === undefined) delete process.env.QA_PREFLIGHT
      else process.env.QA_PREFLIGHT = prev
    }
  })

  test("no projects onboarded → nothing to gate", async () => {
    const dir = await tempProject() // bare temp dir, no projects/
    const h = await hooksIn(dir)
    await expect(run(h, playwrightCall)).resolves.toBeUndefined()
  })

  test("block message names the override and the artifact", async () => {
    const dir = await tempProject("# SHOP\n")
    const h = await hooksIn(dir)
    await expect(run(h, playwrightCall)).rejects.toThrow(/QA_PREFLIGHT=0/)
    await expect(run(h, playwrightCall)).rejects.toThrow(/evidence\/\.preflight\/ok\.json/)
  })
})

// secrets_read toggle (tdd 0.11.0 §7–§11) — mirrors the "secrets_read toggle"
// section of guard-fixtures.sh. The toggle lives in the QA home's
// .qa-guard.json; default/missing/invalid = block; only "allow" opens direct
// reads — and even then only for the READER_CORE commands.
describe("secrets_read toggle (opencode)", () => {
  async function qaHome(config?: string): Promise<string> {
    const dir = await mkdtemp(join(tmpdir(), "qa-toggle-"))
    await writeFile(join(dir, ".qa-home"), "")
    if (config !== undefined) await writeFile(join(dir, ".qa-guard.json"), config)
    return dir
  }

  test("default: no config → block", async () => {
    const h = await hooksIn(await qaHome())
    await expect(run(h, bashBefore("cat .env"))).rejects.toThrow(/^BLOCKED by pre-tool-guard:/)
  })

  test("missing key / wrong value / invalid JSON → block", async () => {
    for (const cfg of ["{}", '{"secrets_read":"yes"}', "not json"]) {
      const h = await hooksIn(await qaHome(cfg))
      await expect(run(h, bashBefore("cat .env"))).rejects.toThrow(/^BLOCKED by pre-tool-guard:/)
      await expect(run(h, bashBefore("grep PASSWORD .env"))).rejects.toThrow(/^BLOCKED by pre-tool-guard:/)
    }
  })

  test("allow: READER_CORE commands follow the toggle", async () => {
    const h = await hooksIn(await qaHome('{"secrets_read":"allow"}'))
    for (const cmd of [
      "cat .env", "less .env", "head .env", "tail .env",
      "grep PASSWORD .env", "sed -n 1p .env", "awk -F= {print$1} .env",
      "jq . .env", "source .env",
    ]) {
      await expect(run(h, bashBefore(cmd)), cmd).resolves.toBeUndefined()
    }
  })

  test("allow: cp/mv/sed -i/awk -i are NOT readers — always blocked", async () => {
    const h = await hooksIn(await qaHome('{"secrets_read":"allow"}'))
    for (const cmd of [
      "cp .env /tmp/secrets", "mv .env /tmp/secrets",
      "sed -i s/a/b/ .env", "sed -i.bak s/a/b/ .env", "sed --in-place s/a/b/ .env",
      "awk -i inplace {print} .env",
    ]) {
      await expect(run(h, bashBefore(cmd)), cmd).rejects.toThrow(/^BLOCKED by pre-tool-guard:/)
    }
  })

  test("allow: writes stay blocked", async () => {
    const dir = await qaHome('{"secrets_read":"allow"}')
    const h = await hooksIn(dir)
    await expect(run(h, bashBefore("echo PASSWORD=x >> .env"))).rejects.toThrow(/^BLOCKED by pre-tool-guard:/)
    await expect(run(h, fileBefore("write", join(dir, ".env")))).rejects.toThrow(/^BLOCKED by pre-tool-guard:/)
  })

  test("allow: interpreter reads stay blocked (fail closed — read vs write indistinguishable)", async () => {
    const h = await hooksIn(await qaHome('{"secrets_read":"allow"}'))
    await expect(run(h, bashBefore(`python3 -c "print(open('.env').read())"`))).rejects.toThrow(/^BLOCKED by pre-tool-guard:/)
  })

  test("rm hardening: deleting a secrets file is a human task, both modes", async () => {
    for (const cfg of [undefined, '{"secrets_read":"allow"}']) {
      const h = await hooksIn(await qaHome(cfg))
      await expect(run(h, bashBefore("rm .env"))).rejects.toThrow(/^BLOCKED by pre-tool-guard:/)
      await expect(run(h, bashBefore("rm -f .env"))).rejects.toThrow(/^BLOCKED by pre-tool-guard:/)
      await expect(run(h, bashBefore("rm .env.local"))).rejects.toThrow(/^BLOCKED by pre-tool-guard:/)
    }
    const h = await hooksIn(await qaHome('{"secrets_read":"allow"}'))
    await expect(run(h, bashBefore("rm scratch-output.txt"))).resolves.toBeUndefined()
    await expect(run(h, bashBefore("rm .env.example"))).resolves.toBeUndefined()
  })

  test("the toggle file itself is a human task (self-escalation hole)", async () => {
    const dir = await qaHome('{"secrets_read":"allow"}')
    const h = await hooksIn(dir)
    await expect(run(h, fileBefore("write", join(dir, ".qa-guard.json")))).rejects.toThrow(/qa-guard\.json/)
    await expect(run(h, fileBefore("edit", join(dir, ".qa-guard.json")))).rejects.toThrow(/qa-guard\.json/)
    await expect(run(h, bashBefore('echo "{}" > .qa-guard.json'))).rejects.toThrow(/qa-guard\.json/)
    await expect(run(h, bashBefore("sed -i s/block/allow/ .qa-guard.json"))).rejects.toThrow(/qa-guard\.json/)
    await expect(run(h, bashBefore("rm .qa-guard.json"))).rejects.toThrow(/qa-guard\.json/)
  })
})

// Foreign MCP gate (field report 2026-09-22: a GLOBAL gitlab MCP server
// pointed at a different customer's .env — the agent nearly edited it).
// Mirrors the "foreign MCP gate" section of guard-fixtures.sh. The gate only
// fires when the server is provably global (readable global config) AND not
// declared in the project's own opencode.json.
describe("foreign MCP gate (opencode)", () => {
  async function setup(opts: { globalServers?: string[]; projectServers?: string[] }) {
    const dir = await tempProject() // bare temp dir: no projects/, preflight inactive
    const globalCfg = await mkdtemp(join(tmpdir(), "qa-globalcfg-"))
    if (opts.globalServers) {
      await mkdir(join(globalCfg, "opencode"), { recursive: true })
      await writeFile(join(globalCfg, "opencode", "opencode.json"),
        JSON.stringify({ mcp: Object.fromEntries(opts.globalServers.map((s) => [s, { type: "local", command: ["x"] }])) }))
    }
    if (opts.projectServers) {
      await writeFile(join(dir, "opencode.json"),
        JSON.stringify({ mcp: Object.fromEntries(opts.projectServers.map((s) => [s, { type: "local", command: ["x"] }])) }))
    }
    return { dir, globalCfg }
  }

  async function withEnv<T>(env: Record<string, string | undefined>, fn: () => Promise<T>): Promise<T> {
    const saved: Record<string, string | undefined> = {}
    for (const [k, v] of Object.entries(env)) {
      saved[k] = process.env[k]
      if (v === undefined) delete process.env[k]; else process.env[k] = v
    }
    try {
      return await fn()
    } finally {
      for (const [k, v] of Object.entries(saved)) {
        if (v === undefined) delete process.env[k]; else process.env[k] = v
      }
    }
  }

  function mcpCall(serverTool: string): BeforeCall {
    return {
      input: { tool: serverTool, sessionID: SESSION_ID, callID: "tool_fixture" },
      output: { args: {} },
    }
  }

  test("blocks a global-only MCP server", async () => {
    const { dir, globalCfg } = await setup({ globalServers: ["gitlab", "playwright"] })
    await withEnv({ XDG_CONFIG_HOME: globalCfg }, async () => {
      const h = await hooksIn(dir)
      await expect(run(h, mcpCall("gitlab_getIssue"))).rejects.toThrow(/MCP server 'gitlab'/)
      await expect(run(h, mcpCall("gitlab_getIssue"))).rejects.toThrow(/QA_ALLOW_GLOBAL_MCP=1/)
    })
  })

  test("allows when declared in the project's opencode.json", async () => {
    const { dir, globalCfg } = await setup({ globalServers: ["gitlab"], projectServers: ["gitlab"] })
    await withEnv({ XDG_CONFIG_HOME: globalCfg }, async () => {
      const h = await hooksIn(dir)
      await expect(run(h, mcpCall("gitlab_getIssue"))).resolves.toBeUndefined()
    })
  })

  test("allows blueprint servers without project declaration", async () => {
    const { dir, globalCfg } = await setup({ globalServers: ["playwright"] })
    await withEnv({ XDG_CONFIG_HOME: globalCfg }, async () => {
      const h = await hooksIn(dir)
      await expect(run(h, mcpCall("playwright_browser_navigate"))).resolves.toBeUndefined()
    })
  })

  test("QA_ALLOW_GLOBAL_MCP=1 escape hatch", async () => {
    const { dir, globalCfg } = await setup({ globalServers: ["gitlab"] })
    await withEnv({ XDG_CONFIG_HOME: globalCfg, QA_ALLOW_GLOBAL_MCP: "1" }, async () => {
      const h = await hooksIn(dir)
      await expect(run(h, mcpCall("gitlab_getIssue"))).resolves.toBeUndefined()
    })
  })

  test("no readable global config → nothing to gate (builtin prefixes pass)", async () => {
    const { dir, globalCfg } = await setup({}) // empty global cfg dir
    await withEnv({ XDG_CONFIG_HOME: globalCfg }, async () => {
      const h = await hooksIn(dir)
      await expect(run(h, mcpCall("websearch_query"))).resolves.toBeUndefined()
    })
  })

  test("blocks writes to global MCP config files", async () => {
    const home = await mkdtemp(join(tmpdir(), "qa-fakehome-"))
    const dir = await tempProject()
    await withEnv({ HOME: home }, async () => {
      const h = await hooksIn(dir)
      await expect(run(h, fileBefore("edit", join(home, ".claude.json")))).rejects.toThrow(/global MCP config/)
      await expect(run(h, fileBefore("write", join(home, ".config", "opencode", "opencode.json")))).rejects.toThrow(/global MCP config/)
      await expect(run(h, bashBefore(`sed -i 's/a/b/' ${home}/.claude.json`))).rejects.toThrow(/global MCP config/)
      await expect(run(h, bashBefore(`echo '{}' > ${home}/.config/opencode/opencode.json`))).rejects.toThrow(/global MCP config/)
    })
  })

  test("allows writes to the project's own MCP config", async () => {
    const home = await mkdtemp(join(tmpdir(), "qa-fakehome-"))
    const dir = await tempProject()
    await withEnv({ HOME: home }, async () => {
      const h = await hooksIn(dir)
      await expect(run(h, fileBefore("write", join(dir, ".mcp.json")))).resolves.toBeUndefined()
      await expect(run(h, bashBefore(`echo '{}' > ${dir}/opencode.json`))).resolves.toBeUndefined()
    })
  })
})

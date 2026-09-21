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

// bootstrap.test.ts — opencode port of the session-start.sh scaffolding policy
// (bootstrap_dirs/seed_browser_config in .claude/hooks/session-start.sh).
//
// Policy: on startup the plugin scaffolds the consumer QA home — copies
// memory/ and evidence/ from the blueprint root if missing, creates projects/
// EMPTY (the scaffolds _template/EXAMPLE stay in the blueprint and are read
// from there on demand), seeds .env.playwright-secrets (comment-only; the MCP
// server's --secrets flag hard-fails on ENOENT) and .playwright-mcp.config.json
// (headless+isolated defaults; same ENOENT rationale for --config). Nothing is
// ever overwritten — these files belong to the user.

import { afterEach, beforeEach, describe, expect, test } from "bun:test"
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises"
import { existsSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { spawnSync } from "node:child_process"
import { orientation, qaBlueprint, resolveQaHome } from "../plugins/qa-blueprint.ts"
import { fakeCtx } from "./fixtures/payloads.ts"

let dir: string
let savedXdg: string | undefined

beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), "qa-boot-"))
  // The MCP scan also reads the GLOBAL opencode config — point it at an empty
  // dir so the machine's real ~/.config/opencode can't leak into assertions.
  savedXdg = process.env.XDG_CONFIG_HOME
  process.env.XDG_CONFIG_HOME = join(dir, ".xdg")
})
afterEach(async () => {
  if (savedXdg === undefined) delete process.env.XDG_CONFIG_HOME
  else process.env.XDG_CONFIG_HOME = savedXdg
  await rm(dir, { recursive: true, force: true })
})

// git may be unusable on this machine (e.g. unaccepted Xcode license, rc 69) —
// skip the gitignore cases there instead of failing on the environment.
const GIT_OK = spawnSync("git", ["--version"], { stdio: "ignore" }).status === 0
const gitTest = GIT_OK ? test : test.skip

async function init(target = dir) {
  const { ctx, prompts } = fakeCtx(target)
  const hooks = await qaBlueprint(ctx as never)
  return { hooks, prompts }
}

describe("bootstrap (opencode)", () => {
  test("scaffolds memory/, evidence/, projects/ into an empty consumer", async () => {
    await init()
    expect(existsSync(join(dir, "memory", "INDEX.md"))).toBe(true)
    expect(existsSync(join(dir, "memory", "learnings", "_inbox.md"))).toBe(true)
    expect(existsSync(join(dir, "evidence"))).toBe(true)
    const proj = join(dir, "projects")
    expect(existsSync(proj)).toBe(true)
    // projects/ stays EMPTY: _template/EXAMPLE are read from the blueprint root,
    // copying them would fork scaffolds updates can no longer reach.
    expect(existsSync(join(proj, "_template"))).toBe(false)
    expect(existsSync(join(proj, "EXAMPLE"))).toBe(false)
  })

  test("never overwrites existing consumer content", async () => {
    await mkdir(join(dir, "memory"), { recursive: true })
    await writeFile(join(dir, "memory", "INDEX.md"), "MY OWN INDEX")
    await mkdir(join(dir, "projects", "SHOP"), { recursive: true })
    await writeFile(join(dir, "projects", "SHOP", "PROJECT.md"), "mine")
    await writeFile(join(dir, ".env.playwright-secrets"), "# my secrets\n")
    await writeFile(join(dir, ".playwright-mcp.config.json"), '{"browser":{"launchOptions":{"headless":false}}}')
    await init()
    expect(await readFile(join(dir, "memory", "INDEX.md"), "utf8")).toBe("MY OWN INDEX")
    expect(await readFile(join(dir, "projects", "SHOP", "PROJECT.md"), "utf8")).toBe("mine")
    expect(await readFile(join(dir, ".env.playwright-secrets"), "utf8")).toBe("# my secrets\n")
    expect(await readFile(join(dir, ".playwright-mcp.config.json"), "utf8")).toContain("false")
  })

  test("seeds .env.playwright-secrets as comment-only placeholder", async () => {
    await init()
    const content = await readFile(join(dir, ".env.playwright-secrets"), "utf8")
    expect(content).toContain("--secrets")
    // comment-only: every non-empty line starts with '#'
    const lines = content.split("\n").filter((l) => l.trim().length > 0)
    expect(lines.every((l) => l.startsWith("#"))).toBe(true)
  })

  test("seeds .playwright-mcp.config.json with headless+isolated defaults", async () => {
    await init()
    const cfg = JSON.parse(await readFile(join(dir, ".playwright-mcp.config.json"), "utf8"))
    expect(cfg.browser?.launchOptions?.headless).toBe(true)
    expect(cfg.browser?.isolated).toBe(true)
  })

  gitTest("gitignores the secrets file when the consumer is a git repo and it is not ignored", async () => {
    const init_rc = spawnSync("git", ["init", "-q"], { cwd: dir }).status
    if (init_rc !== 0) return // git --version worked but init is blocked — same env issue
    await init()
    const gi = await readFile(join(dir, ".gitignore"), "utf8")
    expect(gi).toContain(".env.playwright-secrets")
  })

  test("does not create .gitignore outside a git repo", async () => {
    await init()
    expect(existsSync(join(dir, ".gitignore"))).toBe(false)
  })

  gitTest("does not double-append the gitignore entry on repeat runs", async () => {
    const init_rc = spawnSync("git", ["init", "-q"], { cwd: dir }).status
    if (init_rc !== 0) return
    await init()
    await init()
    const gi = await readFile(join(dir, ".gitignore"), "utf8")
    expect(gi.split(".env.playwright-secrets").length - 1).toBe(1)
  })
})

// Orientation: the session-start.sh signals (project list, browser mode, MCP
// contract hints, ungroomed-learnings counter) ported to a session.created
// context injection (session.prompt noReply) — the plan's Layer-1 asserts.
describe("orientation (opencode)", () => {
  test("output shape: header, project list, router pointers, browser line", async () => {
    await init()
    const text = await orientation(dir)
    expect(text).toContain("QA Agent Blueprint — session start")
    expect(text).toContain("(none yet — run /onboard-project)")
    expect(text).toContain("Read memory/INDEX.md before anything else")
    expect(text).toContain("/qa-help")
    // bootstrap seeded the browser config → the mode is rendered from it
    expect(text).toContain("- Browser: headless, isolated")
  })

  test("lists onboarded projects with their products inline", async () => {
    await mkdir(join(dir, "projects", "SHOP", "products", "STOREFRONT"), { recursive: true })
    await mkdir(join(dir, "projects", "SHOP", "products", "ADMIN"), { recursive: true })
    await mkdir(join(dir, "projects", "_template"), { recursive: true })
    const text = await orientation(dir)
    expect(text).toContain("- SHOP (products: STOREFRONT, ADMIN)")
    expect(text).not.toContain("_template")
    // a real project exists → no first-run MCP lecture
    expect(text).not.toContain("First run")
  })

  test("counts ungroomed learnings; one entry is not a backlog", async () => {
    await init() // seeds memory/ from the blueprint
    // a single entry (the shipped example) stays silent
    await writeFile(join(dir, "memory", "learnings", "_inbox.md"), "# Inbox\n\n## 2026-09-01 — the one example\n")
    expect(await orientation(dir)).not.toContain("ungroomed learnings")
    await writeFile(
      join(dir, "memory", "learnings", "_inbox.md"),
      "# Inbox\n\n## 2026-09-01 — one\n\n## 2026-09-02 — two\n\n## 2026-09-03 — three\n",
    )
    expect(await orientation(dir)).toContain("3 ungroomed learnings in memory/learnings/_inbox.md")
  })

  test("flags a playwright entry without the contract flags", async () => {
    await writeFile(
      join(dir, "opencode.json"),
      '{ "mcp": { "playwright": { "type": "local", "command": ["npx", "@playwright/mcp@latest"] } } }',
    )
    const text = await orientation(dir)
    expect(text).toContain("no --secrets flag")
    expect(text).toContain("no --output-dir flag")
  })

  test("names the DC host and the keychain service for a Data Center entry", async () => {
    await writeFile(
      join(dir, "opencode.json"),
      '{ "mcp": { "atlassian": { "type": "local", "command": ["uvx", "mcp-atlassian"], "environment": { "JIRA_URL": "https://jira.example.com" } } } }',
    )
    const text = await orientation(dir)
    expect(text).toContain("JIRA Data Center (jira.example.com)")
    expect(text).toContain("JIRA_PAT_jira.example.com")
  })

  test("session.created injects the orientation as noReply context, once per session", async () => {
    const { hooks, prompts } = await init()
    await hooks.event({ event: { type: "session.created", properties: { info: { id: "s1" } } } } as never)
    expect(prompts.length).toBe(1)
    const body = (prompts[0] as { body: { noReply?: boolean; parts: { text: string }[] } }).body
    expect(body.noReply).toBe(true)
    expect(body.parts[0].text).toContain("QA Agent Blueprint — session start")
    // same session again → no duplicate injection
    await hooks.event({ event: { type: "session.created", properties: { info: { id: "s1" } } } } as never)
    expect(prompts.length).toBe(1)
    // a different session gets its own copy
    await hooks.event({ event: { type: "session.created", properties: { info: { id: "s2" } } } } as never)
    expect(prompts.length).toBe(2)
  })
})

// QA home resolution (0.9.1 "dual evidence scaffold" field report): a session
// starting in a SUBFOLDER of the QA home must not scaffold a second copy of
// projects//memory//evidence/ there — data lives at the workspace root.
describe("QA home resolution (walk-up)", () => {
  async function mkHome(withMarker: boolean): Promise<{ home: string; sub: string }> {
    const home = join(dir, "KPS-Development")
    const sub = join(home, "test-automation")
    await mkdir(join(home, "projects"), { recursive: true })
    await mkdir(join(home, "memory"), { recursive: true })
    await mkdir(join(home, "evidence"), { recursive: true })
    if (withMarker) await writeFile(join(home, ".qa-home"), "marker\n")
    await mkdir(sub, { recursive: true })
    return { home, sub }
  }

  test("subfolder of a marker-carrying home resolves to the home", async () => {
    const { home, sub } = await mkHome(true)
    expect(await resolveQaHome(sub)).toBe(home)
  })

  test("legacy trio without a marker resolves too", async () => {
    const { home, sub } = await mkHome(false)
    expect(await resolveQaHome(sub)).toBe(home)
  })

  test("nothing found → the directory itself (first-install behavior)", async () => {
    const bare = join(dir, "fresh")
    await mkdir(bare, { recursive: true })
    expect(await resolveQaHome(bare)).toBe(bare)
  })

  test("the walk-up never crosses $HOME", async () => {
    const boundary = join(dir, "boundary")
    const deep = join(boundary, "a", "b")
    await mkdir(deep, { recursive: true })
    const savedHome = process.env.HOME
    process.env.HOME = boundary
    try {
      expect(await resolveQaHome(deep)).toBe(deep)
    } finally {
      if (savedHome === undefined) delete process.env.HOME
      else process.env.HOME = savedHome
    }
  })

  test("plugin in a subfolder: data at the home, harness seeds at the session dir", async () => {
    const { home, sub } = await mkHome(false) // legacy trio, no marker yet
    const { ctx } = fakeCtx(sub)
    await qaBlueprint(ctx as never)
    // no dual scaffold in the subfolder
    expect(existsSync(join(sub, "projects"))).toBe(false)
    expect(existsSync(join(sub, "memory"))).toBe(false)
    expect(existsSync(join(sub, "evidence"))).toBe(false)
    // the resolved home got stamped for the next walk-up
    expect(existsSync(join(home, ".qa-home"))).toBe(true)
    // harness-scoped seeds stay with the session's cwd
    expect(existsSync(join(sub, ".env.playwright-secrets"))).toBe(true)
    expect(existsSync(join(sub, ".playwright-mcp.config.json"))).toBe(true)
    expect(existsSync(join(home, ".env.playwright-secrets"))).toBe(false)
  })

  test("orientation names the resolved home when cwd is a subfolder", async () => {
    const { home, sub } = await mkHome(true)
    const text = await orientation(home, sub)
    expect(text).toContain(`QA home: ${home}`)
    expect(text).toContain("relative to the QA home, not to cwd")
  })
})

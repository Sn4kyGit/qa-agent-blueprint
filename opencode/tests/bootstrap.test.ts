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
import { qaBlueprint } from "../plugins/qa-blueprint.ts"
import { fakeCtx } from "./fixtures/payloads.ts"

let dir: string

beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), "qa-boot-"))
})
afterEach(async () => {
  await rm(dir, { recursive: true, force: true })
})

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

  test("gitignores the secrets file when the consumer is a git repo and it is not ignored", async () => {
    spawnSync("git", ["init", "-q"], { cwd: dir })
    await init()
    const gi = await readFile(join(dir, ".gitignore"), "utf8")
    expect(gi).toContain(".env.playwright-secrets")
  })

  test("does not create .gitignore outside a git repo", async () => {
    await init()
    expect(existsSync(join(dir, ".gitignore"))).toBe(false)
  })

  test("does not double-append the gitignore entry on repeat runs", async () => {
    spawnSync("git", ["init", "-q"], { cwd: dir })
    await init()
    await init()
    const gi = await readFile(join(dir, ".gitignore"), "utf8")
    expect(gi.split(".env.playwright-secrets").length - 1).toBe(1)
  })
})

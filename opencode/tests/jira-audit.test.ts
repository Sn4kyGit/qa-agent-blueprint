// jira-audit.test.ts — opencode port of the post-jira-audit.sh policy
// (.claude/hooks/post-jira-audit.sh — the Claude side is matched by hook
// config, so its fixture coverage lived in the hook review; here the matcher
// moves INTO the plugin, so the matching itself gets tested).
//
// Contract kept identical: append-only log at evidence/.audit/jira-writes.log,
// line format `TS | tool=X | key=Y | result=Z | user=U`, never blocks, never
// logs secret values — only tool name, issue key and outcome.
//
// Tool-name mapping (D5): Claude matcher `mcp__.*atlassian__.*(create|edit|add|
// transition|update|delete).*` becomes opencode tool prefix
// `atlassian_*` + the same verb set.

import { afterEach, beforeEach, describe, expect, test } from "bun:test"
import { mkdtemp, readFile, rm } from "node:fs/promises"
import { existsSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { qaBlueprint } from "../plugins/qa-blueprint.ts"
import { fakeCtx, toolAfter } from "./fixtures/payloads.ts"

let dir: string
let logFile: string

beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), "qa-audit-"))
  logFile = join(dir, "evidence", ".audit", "jira-writes.log")
})
afterEach(async () => {
  await rm(dir, { recursive: true, force: true })
})

async function hooks() {
  const { ctx } = fakeCtx(dir)
  return qaBlueprint(ctx as never)
}

async function fire(tool: string, args: Record<string, unknown> = {}, opts: { error?: boolean } = {}) {
  const h = await hooks()
  const call = toolAfter(tool, args, opts)
  await h["tool.execute.after"](call.input as never, call.output as never)
}

async function logLines(): Promise<string[]> {
  if (!existsSync(logFile)) return []
  return (await readFile(logFile, "utf8")).trim().split("\n")
}

describe("jira audit (opencode)", () => {
  test("logs an atlassian write with issue key", async () => {
    await fire("atlassian_createJiraIssue", { issueKey: "SHOP-123" })
    const lines = await logLines()
    expect(lines).toHaveLength(1)
    expect(lines[0]).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z \| tool=atlassian_createJiraIssue \| key=SHOP-123 \| result=ok \| user=\S+$/)
  })

  test("verb set matches Claude matcher: create/edit/add/transition/update/delete", async () => {
    for (const tool of [
      "atlassian_createJiraIssue",
      "atlassian_editJiraIssue",
      "atlassian_addCommentToJiraIssue",
      "atlassian_transitionJiraIssue",
      "atlassian_updateConfluencePage",
      "atlassian_deleteJiraIssue",
    ]) {
      await fire(tool, { issueKey: "SHOP-1" })
    }
    expect(await logLines()).toHaveLength(6)
  })

  test("deferred executeWrite and executeDestructive are audited, executeRead is not", async () => {
    await fire("atlassian_executeWrite", { arguments: { issueKey: "SHOP-7" } })
    await fire("atlassian_executeDestructive", { arguments: { issueKey: "SHOP-8" } })
    await fire("atlassian_executeRead", { arguments: { issueKey: "SHOP-9" } })
    const lines = await logLines()
    expect(lines).toHaveLength(2)
    expect(lines[0]).toContain("tool=atlassian_executeWrite | key=SHOP-7")
    expect(lines[1]).toContain("tool=atlassian_executeDestructive | key=SHOP-8")
  })

  test("read-only atlassian tools are not writes", async () => {
    await fire("atlassian_getJiraIssue", { issueKey: "SHOP-1" })
    await fire("atlassian_searchJiraIssues", {})
    expect(await logLines()).toHaveLength(0)
  })

  test("non-atlassian tools are ignored", async () => {
    await fire("playwright_browser_navigate", { url: "https://example.invalid" })
    await fire("bash", { command: "echo hi" })
    expect(await logLines()).toHaveLength(0)
  })

  test("key extraction falls back through issueKey → issue_key → key → id → unknown", async () => {
    await fire("atlassian_transitionJiraIssue", { issue_key: "A-1" })
    await fire("atlassian_transitionJiraIssue", { key: "B-2" })
    await fire("atlassian_transitionJiraIssue", { id: "C-3" })
    await fire("atlassian_transitionJiraIssue", {})
    const keys = (await logLines()).map((l) => l.match(/\| key=(\S+)/)?.[1])
    expect(keys).toEqual(["A-1", "B-2", "C-3", "unknown"])
  })

  test("a failed write is logged with result=error, not dropped", async () => {
    await fire("atlassian_createJiraIssue", { issueKey: "SHOP-9" }, { error: true })
    const lines = await logLines()
    expect(lines).toHaveLength(1)
    expect(lines[0]).toContain("result=error")
  })

  test("never throws, even on malformed payloads", async () => {
    const h = await hooks()
    await expect(
      h["tool.execute.after"]({ tool: "atlassian_createJiraIssue" } as never, undefined as never),
    ).resolves.toBeUndefined()
  })

  test("appends across calls (append-only)", async () => {
    const h = await hooks()
    for (const key of ["SHOP-1", "SHOP-2"]) {
      const call = toolAfter("atlassian_editJiraIssue", { issueKey: key })
      await h["tool.execute.after"](call.input as never, call.output as never)
    }
    expect(await logLines()).toHaveLength(2)
  })
})

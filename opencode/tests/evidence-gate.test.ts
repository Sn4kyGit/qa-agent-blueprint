// evidence-gate.test.ts — opencode port of stop-evidence-fixtures.sh,
// redesigned per D3 (docs/opencode-port-plan.md §3): opencode has no
// "block the stop" primitive, so enforcement becomes
//   (a) a write-gate: tool.execute.before denies atlassian_* WRITE tools while
//       the session shows test activity but no fresh, learnings-declaring
//       execution_summary.json — the verdict cannot reach JIRA without evidence;
//   (b) an idle reminder: session.idle → client.session.prompt() with the same
//       markers the Claude hook prints (QA_EVIDENCE_MISSING:/QA_LEARNINGS_MISSING:).
//
// "Test activity" is tracked from tool.execute.after events (the plugin sees
// every call — no transcript parsing needed): any playwright_* tool, any
// atlassian_* write verb, or a bash command whose FIRST line runs the
// Playwright CLI runner (same anchored regex as the bash hook — a heredoc
// mentioning "npx playwright test" must NOT count).
//
// Gate state is derived from the filesystem, policy-identical to
// stop-evidence-check.sh: fresh = mtime < 2h; learnings = the key exists and
// exactly one of captured[] / none_because is filled; unparseable summaries
// are skipped, not flagged; the hook must NOT know the verdict vocabulary
// (NEEDS_REVIEW passes on declaration alone).

import { afterEach, beforeEach, describe, expect, test } from "bun:test"
import { mkdir, mkdtemp, rm, utimes, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { qaBlueprint } from "../plugins/qa-blueprint.ts"
import { bashBefore, fakeCtx, toolAfter, SESSION_ID } from "./fixtures/payloads.ts"

let dir: string
let prevShadow: string | undefined

beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), "qa-gate-"))
  // The shadow gate has its own suite (guard.test.ts); these tests exercise the
  // evidence gate, which sits BEHIND it — disable shadow so writes reach it.
  prevShadow = process.env.QA_AGENT_SHADOW
  process.env.QA_AGENT_SHADOW = "0"
})
afterEach(async () => {
  if (prevShadow === undefined) delete process.env.QA_AGENT_SHADOW
  else process.env.QA_AGENT_SHADOW = prevShadow
  await rm(dir, { recursive: true, force: true })
})

interface Rig {
  hooks: Awaited<ReturnType<typeof qaBlueprint>>
  prompts: unknown[]
}

async function rig(): Promise<Rig> {
  const { ctx, prompts } = fakeCtx(dir)
  const hooks = await qaBlueprint(ctx as never)
  return { hooks, prompts }
}

async function writeSummary(rel: string, body: unknown, opts: { ageHours?: number; raw?: string } = {}) {
  const d = join(dir, "evidence", rel)
  await mkdir(d, { recursive: true })
  const f = join(d, "execution_summary.json")
  await writeFile(f, opts.raw ?? JSON.stringify(body))
  if (opts.ageHours) {
    const t = new Date(Date.now() - opts.ageHours * 3600_000)
    await utimes(f, t, t)
  }
  return f
}

async function markActivity(hooks: Rig["hooks"], kind: "playwright" | "atlassianWrite" | "atlassianWriteShop2" | "atlassianRead" | "pnpmRunner" | "npmScript" | "heredoc") {
  const call = {
    playwright: () => toolAfter("playwright_browser_navigate", { url: "https://example.invalid" }),
    atlassianWrite: () => toolAfter("atlassian_transitionJiraIssue", { issueKey: "SHOP-1" }),
    atlassianWriteShop2: () => toolAfter("atlassian_transitionJiraIssue", { issueKey: "SHOP-2" }),
    atlassianRead: () => toolAfter("atlassian_getJiraIssue", { issueKey: "SHOP-1" }),
    pnpmRunner: () => toolAfter("bash", { command: "cd ../shop-web-tests && pnpm playwright test --grep @smoke" }),
    npmScript: () => toolAfter("bash", { command: "npm run test:e2e" }),
    heredoc: () => toolAfter("bash", { command: "cat > note.md <<EOF\nwe usually run npx playwright test here\nEOF" }),
  }[kind]()
  await hooks["tool.execute.after"](call.input as never, call.output as never)
}

async function idle(r: Rig) {
  await r.hooks.event({ event: { type: "session.idle", properties: { sessionID: SESSION_ID } } } as never)
}

async function jiraWrite(r: Rig) {
  const call = bashBefore("true") // placeholder shape; replaced below
  const input = { tool: "atlassian_addCommentToJiraIssue", sessionID: SESSION_ID, callID: "tool_gate" }
  const output = { args: { issueKey: "SHOP-1", body: "verdict" } }
  void call
  return r.hooks["tool.execute.before"](input as never, output as never)
}

const summary = (learnings: unknown, verdict = "PASS") => ({
  ticket: "SHOP-1",
  project: "SHOP",
  verdict,
  ...(learnings === "omit" ? {} : { learnings }),
})

describe("evidence gate (opencode) — activity classification", () => {
  test("playwright MCP tool counts", async () => {
    const r = await rig()
    await markActivity(r.hooks, "playwright")
    await idle(r)
    expect(r.prompts).toHaveLength(1)
    expect(JSON.stringify(r.prompts[0])).toContain("QA_EVIDENCE_MISSING:")
  })

  test("atlassian write verb counts", async () => {
    const r = await rig()
    await markActivity(r.hooks, "atlassianWrite")
    await idle(r)
    expect(JSON.stringify(r.prompts[0] ?? "")).toContain("QA_EVIDENCE_MISSING:")
  })

  test("atlassian read-only tool does not count", async () => {
    const r = await rig()
    await markActivity(r.hooks, "atlassianRead")
    await idle(r)
    expect(r.prompts).toHaveLength(0)
  })

  test("pnpm playwright test counts", async () => {
    const r = await rig()
    await markActivity(r.hooks, "pnpmRunner")
    await idle(r)
    expect(JSON.stringify(r.prompts[0] ?? "")).toContain("QA_EVIDENCE_MISSING:")
  })

  test("npm run test:e2e counts", async () => {
    const r = await rig()
    await markActivity(r.hooks, "npmScript")
    await idle(r)
    expect(JSON.stringify(r.prompts[0] ?? "")).toContain("QA_EVIDENCE_MISSING:")
  })

  test("heredoc merely mentioning the runner does not count", async () => {
    const r = await rig()
    await markActivity(r.hooks, "heredoc")
    await idle(r)
    expect(r.prompts).toHaveLength(0)
  })
})

describe("evidence gate (opencode) — gate evaluation", () => {
  test("no test activity → nothing enforced", async () => {
    const r = await rig()
    await idle(r)
    expect(r.prompts).toHaveLength(0)
    await expect(jiraWrite(r)).resolves.toBeUndefined()
  })

  test("activity, no evidence → write-gate throws QA_EVIDENCE_MISSING", async () => {
    const r = await rig()
    await mkdir(join(dir, "evidence"), { recursive: true })
    await markActivity(r.hooks, "playwright")
    await expect(jiraWrite(r)).rejects.toThrow(/QA_EVIDENCE_MISSING:/)
  })

  test("evidence without learnings declaration → QA_LEARNINGS_MISSING", async () => {
    const r = await rig()
    await writeSummary("SHOP/SHOP-1/run1", summary("omit"))
    await markActivity(r.hooks, "playwright")
    await expect(jiraWrite(r)).rejects.toThrow(/QA_LEARNINGS_MISSING:/)
  })

  test("learnings empty on both sides → QA_LEARNINGS_MISSING", async () => {
    const r = await rig()
    await writeSummary("SHOP/SHOP-1/run1", summary({ captured: [], none_because: null }))
    await markActivity(r.hooks, "playwright")
    await expect(jiraWrite(r)).rejects.toThrow(/QA_LEARNINGS_MISSING:/)
  })

  test("captured entries → gate green", async () => {
    const r = await rig()
    await writeSummary("SHOP/SHOP-1/run1", summary({ captured: ["stale cache after deploy"], none_because: null }))
    await markActivity(r.hooks, "playwright")
    await expect(jiraWrite(r)).resolves.toBeUndefined()
    await idle(r)
    expect(r.prompts).toHaveLength(0)
  })

  test("explicit none_because → gate green", async () => {
    const r = await rig()
    await writeSummary("SHOP/SHOP-1/run1", summary({ captured: [], none_because: "clean run, no surprises" }))
    await markActivity(r.hooks, "playwright")
    await expect(jiraWrite(r)).resolves.toBeUndefined()
  })

  test("NEEDS_REVIEW passes on declaration alone (hook does not know verdicts)", async () => {
    const r = await rig()
    await writeSummary("SHOP/SHOP-1/run1", summary({ captured: ["x"], none_because: null }, "NEEDS_REVIEW"))
    await markActivity(r.hooks, "playwright")
    await expect(jiraWrite(r)).resolves.toBeUndefined()
  })

  test("NEEDS_REVIEW without learnings → still blocked", async () => {
    const r = await rig()
    await writeSummary("SHOP/SHOP-1/run1", summary("omit", "NEEDS_REVIEW"))
    await markActivity(r.hooks, "playwright")
    await expect(jiraWrite(r)).rejects.toThrow(/QA_LEARNINGS_MISSING:/)
  })

  test("multi-product fan-out: one undeclared summary blocks", async () => {
    const r = await rig()
    await writeSummary("SHOP/SHOP-1/run1__STOREFRONT", summary({ captured: [], none_because: "clean run" }))
    await writeSummary("SHOP/SHOP-1/run1__ADMIN", summary("omit"))
    await markActivity(r.hooks, "playwright")
    await expect(jiraWrite(r)).rejects.toThrow(/QA_LEARNINGS_MISSING:/)
  })

  test("stale summary (older than 2h) counts as no evidence", async () => {
    const r = await rig()
    await writeSummary("SHOP/SHOP-1/run1", summary({ captured: ["x"], none_because: null }), { ageHours: 3 })
    await markActivity(r.hooks, "playwright")
    await expect(jiraWrite(r)).rejects.toThrow(/QA_EVIDENCE_MISSING:/)
  })

  test("unparseable summary is not flagged for learnings (separate problem)", async () => {
    const r = await rig()
    await writeSummary("SHOP/SHOP-1/run1", null, { raw: "{not json" })
    await markActivity(r.hooks, "playwright")
    await expect(jiraWrite(r)).resolves.toBeUndefined()
  })

  test("NO_TEST with reason and learnings declaration → green", async () => {
    const r = await rig()
    await writeSummary("SHOP/SHOP-1/run1", {
      ticket: "SHOP-1",
      project: "SHOP",
      verdict: "NO_TEST",
      no_test_reason: "reproduced twice, root cause not isolated",
      learnings: { captured: [], none_because: "no product knowledge gained" },
    })
    await markActivity(r.hooks, "playwright")
    await expect(jiraWrite(r)).resolves.toBeUndefined()
  })

  test("per-ticket scoping (F2): evidence for SHOP-1 does not cover a SHOP-2 run", async () => {
    const r = await rig()
    await writeSummary("SHOP/SHOP-1/run1", summary({ captured: [], none_because: "clean run" }))
    await markActivity(r.hooks, "atlassianWriteShop2")
    await expect(jiraWrite(r)).rejects.toThrow(/QA_EVIDENCE_MISSING:[\s\S]*SHOP-2/)
  })

  test("per-ticket scoping (F2): evidence for SHOP-2 covers a SHOP-2 run", async () => {
    const r = await rig()
    await writeSummary("SHOP/SHOP-2/run1", summary({ captured: [], none_because: "clean run" }))
    await markActivity(r.hooks, "atlassianWriteShop2")
    await expect(jiraWrite(r)).resolves.toBeUndefined()
  })

  test("no evidence/ directory at all → nothing to enforce", async () => {
    const r = await rig()
    // Plugin init bootstraps evidence/ into every consumer (session-start
    // parity), so undo that here to exercise the defensive no_dir path.
    await rm(join(dir, "evidence"), { recursive: true, force: true })
    await markActivity(r.hooks, "playwright")
    await idle(r)
    expect(r.prompts).toHaveLength(0)
    await expect(jiraWrite(r)).resolves.toBeUndefined()
  })
})

describe("evidence gate (opencode) — loop safety", () => {
  test("idle reminder fires once per session (stop_hook_active equivalent)", async () => {
    const r = await rig()
    await mkdir(join(dir, "evidence"), { recursive: true })
    await markActivity(r.hooks, "playwright")
    await idle(r)
    await idle(r)
    expect(r.prompts).toHaveLength(1)
  })
})

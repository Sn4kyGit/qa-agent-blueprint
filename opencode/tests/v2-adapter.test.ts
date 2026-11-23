// v2-adapter.test.ts — opencode 2.x (V2) plugin contract.
//
// 2.x rejects a V1 function export and discovers plugins only as real files;
// hooks register via ctx.tool.hook / ctx.shell.hook / ctx.event.subscribe, the
// callback receives ONE mutable event, the bash tool is named "shell", and file
// args use "path" instead of "filePath". The dual-API plugin's setup(ctx) must
// normalize all of that into the V1 shape the shared policy core speaks. These
// tests drive setup() with a fake V2 context and assert the guard still fires —
// the runtime smoke (real opencode) is the complementary proof.

import { describe, expect, test } from "bun:test"
import { mkdtemp } from "fs/promises"
import { tmpdir } from "os"
import { join } from "path"
import plugin from "../plugins/qa-blueprint.ts"

type Hook = (ev: Record<string, unknown>) => unknown

function fakeV2Ctx(directory: string) {
  const before: Hook[] = []
  const after: Hook[] = []
  const shell: Hook[] = []
  const ctx = {
    location: { directory },
    session: { prompt: async () => ({}) },
    app: { log: async () => {} },
    tool: {
      hook: async (name: string, cb: Hook) => {
        if (name === "execute.before") before.push(cb)
        if (name === "execute.after") after.push(cb)
      },
    },
    shell: { hook: async (name: string, cb: Hook) => { if (name === "create.before") shell.push(cb) } },
    event: { subscribe: () => ({ [Symbol.asyncIterator]: async function* () {} }) },
  }
  return { ctx, before, after, shell }
}

async function setup() {
  const dir = await mkdtemp(join(tmpdir(), "qa-v2-"))
  const fake = fakeV2Ctx(dir)
  await plugin.setup(fake.ctx as never)
  return fake
}

describe("opencode 2.x V2 adapter", () => {
  test("default export is a plain object with id + setup + server (dual API)", () => {
    expect(typeof plugin).toBe("object")
    expect(plugin.id).toBe("qa-agent-blueprint")
    expect(typeof plugin.setup).toBe("function")
    expect(typeof plugin.server).toBe("function")
  })

  test("setup registers execute.before/after and shell create.before", async () => {
    const { before, after, shell } = await setup()
    expect(before.length).toBe(1)
    expect(after.length).toBe(1)
    expect(shell.length).toBe(1)
  })

  test("V2 shell tool is mapped to bash and cat .env is blocked", async () => {
    const { before } = await setup()
    await expect(
      before[0]({ tool: "shell", sessionID: "ses_x", id: "c1", input: { command: "cat .env" } }),
    ).rejects.toThrow(/^BLOCKED by pre-tool-guard:/)
  })

  test("V2 write path arg is normalized and a .env write is blocked", async () => {
    const { before } = await setup()
    await expect(
      before[0]({ tool: "write", sessionID: "ses_x", id: "c1", input: { path: ".env", content: "X=1" } }),
    ).rejects.toThrow(/secrets file/)
  })

  test("V2 edit newString is normalized (human-only file write blocked)", async () => {
    const { before } = await setup()
    await expect(
      before[0]({ tool: "edit", sessionID: "ses_x", id: "c1", input: { path: "projects/SHOP/PROJECT.md", oldString: "a", newString: "Shadow mode: off" } }),
    ).rejects.toThrow(/^BLOCKED by pre-tool-guard:/)
  })

  test("V2 evidence-retention prune is blocked (S4, human-only)", async () => {
    const { before } = await setup()
    await expect(
      before[0]({ tool: "shell", sessionID: "ses_x", id: "c1", input: { command: "python3 .claude/scripts/evidence-retention.py prune --yes" } }),
    ).rejects.toThrow(/human step/)
  })

  test("V2 ordinary shell command stays allowed", async () => {
    const { before } = await setup()
    await expect(
      before[0]({ tool: "shell", sessionID: "ses_x", id: "c1", input: { command: "npx playwright test" } }),
    ).resolves.toBeUndefined()
  })

  test("V2 read of raw evidence is blocked (path normalization)", async () => {
    const { before } = await setup()
    await expect(
      before[0]({ tool: "read", sessionID: "ses_x", id: "c1", input: { path: "evidence/SHOP/SHOP-1/run/shot.png" } }),
    ).rejects.toThrow(/raw evidence/)
  })
})

// message-parity.test.ts — drift guard for the two pre-tool guards (audit
// 2026-09-18 F3).
//
// The bash guard (.claude/hooks/pre-tool-guard.sh) and the opencode plugin
// (opencode/plugins/qa-blueprint.ts) enforce the same policy; their block
// messages are part of the user-facing contract and must not drift apart —
// F3 was exactly that: the TS message lacked the resolve-secrets.sh pointer
// the bash side had. This test extracts every block message from BOTH files
// and asserts the sets are identical after normalizing the path placeholder
// (bash `$FILE_PATH` ↔ TS template `${filePath}`).

import { describe, expect, test } from "bun:test"
import { readFile } from "fs/promises"
import { join } from "path"

const ROOT = join(import.meta.dir, "..", "..")

function normalize(msg: string): string {
  return msg.replace(/\$FILE_PATH|\$\{filePath\}/g, "<PATH>")
}

async function bashMessages(): Promise<Set<string>> {
  const src = await readFile(join(ROOT, ".claude/hooks/pre-tool-guard.sh"), "utf8")
  const out = new Set<string>()
  for (const m of src.matchAll(/block "([^"]+)"/g)) out.add(normalize(m[1]))
  return out
}

async function tsMessages(): Promise<Set<string>> {
  const src = await readFile(join(ROOT, "opencode/plugins/qa-blueprint.ts"), "utf8")
  const out = new Set<string>()
  // inline: block("...") or block(`...`)
  for (const m of src.matchAll(/block\("([^"]+)"\)/g)) out.add(normalize(m[1]))
  for (const m of src.matchAll(/block\(`([^`]+)`\)/g)) out.add(normalize(m[1]))
  // named constants holding a block message (e.g. SHADOW_MSG)
  for (const m of src.matchAll(/const [A-Z_]*MSG = "([^"]+)"/g)) out.add(normalize(m[1]))
  return out
}

describe("block-message parity (bash guard ↔ opencode plugin)", () => {
  test("the message sets are identical", async () => {
    const bash = await bashMessages()
    const ts = await tsMessages()
    // M9 (0.18.5): assert minimum sizes — a refactor that renames `block(` to
    // `deny(` would shrink both sets to empty and pass vacuously.
    expect(bash.size, "bash guard must have at least 20 block messages").toBeGreaterThanOrEqual(20)
    expect(ts.size, "opencode plugin must have at least 20 block messages").toBeGreaterThanOrEqual(20)
    const onlyBash = [...bash].filter((m) => !ts.has(m))
    const onlyTs = [...ts].filter((m) => !bash.has(m))
    // Drift shows up here with the offending message(s) named explicitly.
    expect(onlyBash, `messages only in the bash guard (bash=${bash.size}, ts=${ts.size})`).toEqual([])
    expect(onlyTs, `messages only in the opencode plugin (bash=${bash.size}, ts=${ts.size})`).toEqual([])
  })

  test("both sides carry the resolve-secrets.sh pointer in the reader message (F3)", async () => {
    const bash = await bashMessages()
    const ts = await tsMessages()
    const needle = "refusing a command that reads a .env* file — secrets never enter chat or context by default. To check which keys exist: resolve-secrets.sh --status. Direct reads are a comfort opt-in: secrets_read=allow in .qa-guard.json (a human task — the guard refuses edits to it)."
    expect(bash.has(needle)).toBe(true)
    expect(ts.has(needle)).toBe(true)
  })
})

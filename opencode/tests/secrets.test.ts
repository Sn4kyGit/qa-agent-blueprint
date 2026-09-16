// secrets.test.ts — opencode port of the JIRA PAT keychain resolution
// (session-start.sh → $CLAUDE_ENV_FILE becomes the plugin's "shell.env" hook;
// docs/rules/core/security.md: the token lives in NO file and no chat).
//
// Contract:
//   - JIRA_PERSONAL_TOKEN already in the environment → the hook does nothing
//     (explicit env wins over keychain resolution, same as the bash flow).
//   - unset + resolvable (macOS keychain service JIRA_PAT_<jira-host>) →
//     injected into output.env so MCP child processes see it.
//   - unset + not resolvable → hook stays silent, never throws, never prints
//     a value anywhere.
//
// The keychain lookup itself is injected (deps.resolveJiraPat) so the suite
// never touches the real keychain.

import { afterEach, beforeEach, describe, expect, test } from "bun:test"
import { qaBlueprint } from "../plugins/qa-blueprint.ts"
import { fakeCtx } from "./fixtures/payloads.ts"

const VAR = "JIRA_PERSONAL_TOKEN"
let saved: string | undefined

beforeEach(() => {
  saved = process.env[VAR]
  delete process.env[VAR]
})
afterEach(() => {
  if (saved === undefined) delete process.env[VAR]
  else process.env[VAR] = saved
})

async function runShellEnv(deps?: { resolveJiraPat?: () => Promise<string | undefined> }) {
  const { ctx } = fakeCtx("/tmp/qa-secrets-test")
  const hooks = await qaBlueprint(ctx as never, deps as never)
  const output: { env: Record<string, string> } = { env: {} }
  await hooks["shell.env"]({ cwd: "/tmp/qa-secrets-test" } as never, output as never)
  return output.env
}

describe("secrets via shell.env (opencode)", () => {
  test("explicit env wins: resolver is not even consulted", async () => {
    process.env[VAR] = "explicit-value"
    let consulted = false
    const env = await runShellEnv({
      resolveJiraPat: async () => {
        consulted = true
        return "keychain-value"
      },
    })
    expect(consulted).toBe(false)
    expect(env[VAR]).toBeUndefined() // nothing to inject — the process env already carries it
  })

  test("unset + resolver yields a value → injected", async () => {
    const env = await runShellEnv({ resolveJiraPat: async () => "pat-from-keychain" })
    expect(env[VAR]).toBe("pat-from-keychain")
  })

  test("unset + resolver finds nothing → silent, no key, no throw", async () => {
    const env = await runShellEnv({ resolveJiraPat: async () => undefined })
    expect(env[VAR]).toBeUndefined()
  })

  test("no resolver available (non-macOS) → silent no-op", async () => {
    const env = await runShellEnv({ resolveJiraPat: undefined })
    expect(env[VAR]).toBeUndefined()
  })
})

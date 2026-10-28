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
//   - the jira host comes from JIRA_URL in the process env, falling back to
//     the DC entry in the consumer's opencode.json — that env map lands in the
//     MCP server's process, NOT in opencode's own, so the plugin reads the
//     config itself (same as the bash hook's mcp_scan).
//
// The keychain lookup itself is injected (deps.resolveJiraPat) so the suite
// never touches the real keychain.

import { afterEach, beforeEach, describe, expect, test } from "bun:test"
import { qaBlueprint, scanMcpServers } from "../plugins/qa-blueprint.ts"
import { fakeCtx } from "./fixtures/payloads.ts"
import { mkdir, mkdtemp, rm, symlink } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"

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

async function runShellEnv(deps?: { resolveJiraPat?: (directory: string) => Promise<string | undefined> }) {
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

  test("resolver receives the consumer directory (DC host is read from its opencode.json)", async () => {
    let seen = ""
    await runShellEnv({
      resolveJiraPat: async (directory) => {
        seen = directory
        return undefined
      },
    })
    expect(seen).toBe("/tmp/qa-secrets-test")
  })
})

describe("scanMcpServers — DC host + contract flags from opencode config entries", () => {
  test("DC atlassian entry yields its JIRA_URL host", () => {
    const scan = scanMcpServers({
      atlassian: { type: "local", command: ["uvx", "mcp-atlassian"], environment: { JIRA_URL: "https://jira.example.com" } },
    })
    expect(scan.hasAt).toBe(true)
    expect(scan.dcHost).toBe("jira.example.com")
  })

  test("Cloud remote atlassian has no DC host", () => {
    const scan = scanMcpServers({ atlassian: { type: "remote", url: "https://mcp.atlassian.com/v1/sse" } })
    expect(scan.hasAt).toBe(true)
    expect(scan.dcHost).toBe("")
  })

  test("local playwright without the contract flags is flagged both ways", () => {
    const scan = scanMcpServers({ playwright: { type: "local", command: ["npx", "@playwright/mcp@latest"] } })
    expect(scan.hasPw).toBe(true)
    expect(scan.pwUnmasked).toBe(true)
    expect(scan.pwNoOutdir).toBe(true)
    expect(scan.pwNoImageomit).toBe(true)
  })

  test("blueprint playwright entry with the contract flags is clean", () => {
    const scan = scanMcpServers({
      playwright: {
        type: "local",
        command: ["npx", "@playwright/mcp@latest", "--config", ".playwright-mcp.config.json", "--secrets", ".env.playwright-secrets", "--output-dir", "evidence/.mcp-out", "--image-responses", "omit"],
      },
    })
    expect(scan.pwUnmasked).toBe(false)
    expect(scan.pwNoOutdir).toBe(false)
    expect(scan.pwNoImageomit).toBe(false)
  })

  test("playwright via qa-secrets mcp wrapper satisfies the secrets contract", () => {
    const scan = scanMcpServers({
      playwright: {
        type: "local",
        command: ["node", ".claude/scripts/qa-secrets.mjs", "mcp", "STAGE_PASSWORD", "--", "npx", "@playwright/mcp@latest", "--output-dir", "evidence/.mcp-out", "--image-responses=omit"],
      },
    })
    expect(scan.pwUnmasked).toBe(false)
    expect(scan.pwNoOutdir).toBe(false)
    expect(scan.pwNoImageomit).toBe(false)
  })

  test("image-responses allow is flagged while equals omit is accepted", () => {
    const base = ["npx", "@playwright/mcp@latest", "--secrets", ".env.playwright-secrets", "--output-dir", "evidence/.mcp-out"]
    expect(scanMcpServers({ playwright: { type: "local", command: [...base, "--image-responses", "allow"] } }).pwNoImageomit).toBe(true)
    expect(scanMcpServers({ playwright: { type: "local", command: [...base, "--image-responses=omit"] } }).pwNoImageomit).toBe(false)
  })

  test("output-dir must point into evidence, including equals form", () => {
    const base = ["npx", "@playwright/mcp@latest", "--secrets", ".env.playwright-secrets", "--image-responses", "omit"]
    expect(scanMcpServers({ playwright: { type: "local", command: [...base, "--output-dir", "/tmp/pw-out"] } }).pwNoOutdir).toBe(true)
    expect(scanMcpServers({ playwright: { type: "local", command: [...base, "--output-dir=evidence/custom"] } }).pwNoOutdir).toBe(false)
    expect(scanMcpServers({ playwright: { type: "local", command: [...base, "--output-dir", "evidence/../outside"] } }).pwNoOutdir).toBe(true)
    expect(scanMcpServers({ playwright: { type: "local", command: [...base, "--output-dir", "/tmp/evidence"] } }).pwNoOutdir).toBe(true)
  })

  test("output-dir cannot escape evidence through a symlink", async () => {
    const root = await mkdtemp(join(tmpdir(), "qa-output-containment-"))
    try {
      await mkdir(join(root, "evidence"))
      await symlink(tmpdir(), join(root, "evidence", "escape"))
      const command = ["npx", "@playwright/mcp@latest", "--secrets", ".env.playwright-secrets", "--output-dir", "evidence/escape/out", "--image-responses", "omit"]
      expect(scanMcpServers({ playwright: { type: "local", command } }, root).pwNoOutdir).toBe(true)
    } finally {
      await rm(root, { recursive: true, force: true })
    }
  })

  test("complementary playwright entries never share contract health", () => {
    const scan = scanMcpServers({
      playwright: [
        { type: "local", command: ["npx", "@playwright/mcp@latest", "--secrets", ".env.playwright-secrets"] },
        { type: "local", command: ["npx", "@playwright/mcp@latest", "--output-dir", "evidence/.mcp-out", "--image-responses", "omit"] },
      ],
    })
    expect(scan.pwUnmasked).toBe(true)
    expect(scan.pwNoOutdir).toBe(true)
    expect(scan.pwNoImageomit).toBe(true)
  })

  test("remote playwright is the consumer's own setup — never flagged", () => {
    const scan = scanMcpServers({ playwright: { type: "remote", url: "http://grid.example:4444" } })
    expect(scan.hasPw).toBe(true)
    expect(scan.pwUnmasked).toBe(false)
    expect(scan.pwNoOutdir).toBe(false)
    expect(scan.pwNoImageomit).toBe(false)
  })
})

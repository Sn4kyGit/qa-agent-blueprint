// qa-blueprint.ts — the qa-agent-blueprint's opencode plugin: one thin module
// carrying the four Claude-Code hook surfaces across (D2/D3 in
// docs/opencode-port-plan.md):
//
//   Claude Code                     opencode
//   ──────────────────────────────  ─────────────────────────────────────────
//   PreToolUse guard (exit 2)    →  tool.execute.before → throw
//   PostToolUse JIRA audit       →  tool.execute.after (matcher lives here now)
//   Stop evidence check          →  write-gate on atlassian_* + session.idle
//                                   reminder (no "block stop" in opencode)
//   SessionStart bootstrap       →  plugin init (scaffolding, never overwrites)
//   $CLAUDE_ENV_FILE PAT export  →  shell.env (keychain → env, never a file)
//
// Policy is ported, not reinvented: same blocklists, same regexes, same
// markers (QA_EVIDENCE_MISSING:/QA_LEARNINGS_MISSING:), same log format as the
// bash hooks in .claude/hooks/ — the fixture suites in opencode/tests/ mirror
// .claude/hooks/tests/ case for case.

import { appendFile, cp, mkdir, readdir, readFile, stat, writeFile } from "node:fs/promises"
import { existsSync, realpathSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"
import { spawnSync } from "node:child_process"

// Resolve the blueprint root through the symlink the installer creates
// (.opencode/plugins/qa-blueprint.ts → <blueprint>/opencode/plugins/…) so
// scaffold sources are found regardless of install mode.
const BLUEPRINT_ROOT = join(dirname(realpathSync(fileURLToPath(import.meta.url))), "..", "..")

// --------------------------------------------------------------------------
// 1. Pre-tool guard (port of pre-tool-guard.sh)
// --------------------------------------------------------------------------

const GUARD_PREFIX = "BLOCKED by pre-tool-guard:"

function isSecretPath(p: string): boolean {
  // `.env.example` is the committed placeholder template — exempt, listed
  // first so it wins over the .env rules below (same ordering as the bash
  // case statement).
  if (/\.env\.example$/.test(p)) return false
  const base = p.split("/").pop() ?? p
  if (base === ".env" || base.startsWith(".env.") || base.endsWith(".env")) return true
  if (base.endsWith(".pem") || base.includes("id_rsa") || base.includes("id_ed25519")) return true
  // Lowercase: `*secret*`-style patterns must catch SECRET/ and Credentials/
  // (bash case is case-sensitive — that bug shipped once already).
  const lc = p.toLowerCase()
  return lc.includes("secret") || lc.includes("credential")
}

// Fail-closed haystack: when the tool name is missing/unrecognized we cannot
// trust the arg structure, so the whole serialized args object is matched with
// substring semantics (bash glob `*…*` equivalent). Stricter than the anchored
// path check on purpose — a payload we cannot parse is not allowed to sneak a
// secret past us.
function haystackTouchesSecret(s: string): boolean {
  const stripped = s.replaceAll(".env.example", "")
  return /\.env(\.|"|'|$)/.test(stripped)
    || /\.pem\b|id_rsa|id_ed25519/i.test(stripped)
    || /secret|credential/i.test(stripped)
}

const RM_RF = /rm\s+(-[a-zA-Z]*f[a-zA-Z]*r|-[a-zA-Z]*r[a-zA-Z]*f)\s/
const GIT_FORCE_PUSH = /git\s+push\s+.*(--force|-f\b)/
// The reader must sit at a COMMAND position and the .env file must belong to
// THAT command — otherwise a pipe followed by prose naming the file blocks
// ordinary work, and a guard that blocks ordinary work gets switched off.
const ENV_READER = /(^|[;&|(]|&&|\|\|)\s*(cat|less|more|head|tail|cp|mv)\s+[^;&|]*\.env([^a-zA-Z]|$)/
const ENV_REDIRECT = />>?\s*\.env/

// Tools whose filePath argument is a WRITE (reads are governed by opencode
// permission denies — D8 — not by this guard, same split as Claude where the
// hook matcher only covered Bash|Write|Edit|MultiEdit|NotebookEdit).
const WRITE_TOOLS = new Set(["write", "edit", "multiedit", "patch", "apply_patch", "notebook_edit"])

function block(reason: string): never {
  throw new Error(`${GUARD_PREFIX} ${reason}`)
}

function guardCheck(tool: string, args: Record<string, unknown>) {
  if (!tool) {
    // fail closed: scan the raw args as both command and path
    const raw = JSON.stringify(args ?? {})
    if (RM_RF.test(raw)) block("refusing rm -rf / rm -fr — destructive command.")
    if (GIT_FORCE_PUSH.test(raw)) block("refusing git push --force — see the git safety protocol before overriding this manually.")
    if (haystackTouchesSecret(raw)) block("refusing an unrecognized call touching a secrets path — failing closed.")
    return
  }

  const filePath = typeof args.filePath === "string" ? args.filePath : ""
  if (filePath && WRITE_TOOLS.has(tool) && isSecretPath(filePath)) {
    block(`refusing to write/edit a secrets file (${filePath}). Secrets are vault/env references only — see .claude/rules/core/security.md.`)
  }

  if (tool === "bash") {
    const command = typeof args.command === "string" ? args.command : ""
    if (RM_RF.test(command)) block("refusing rm -rf / rm -fr — destructive command.")
    if (GIT_FORCE_PUSH.test(command)) block("refusing git push --force — see the git safety protocol before overriding this manually.")
    // Strip only the literal ".env.example" before the .env checks: the
    // template must stay writable; .env/.env.local/.env.playwright-secrets
    // still match in full.
    const noExample = command.replaceAll(".env.example", "")
    if (ENV_READER.test(noExample)) block("refusing a command that reads/copies a .env* file — secrets never enter chat or context.")
    if (ENV_REDIRECT.test(noExample)) block("refusing a command that writes into a .env* file directly — use the vault/secrets workflow instead.")
  }
}

// --------------------------------------------------------------------------
// 2. JIRA write audit (port of post-jira-audit.sh)
// --------------------------------------------------------------------------

// D5 mapping: Claude matched `mcp__.*atlassian__.*(create|edit|…).*`; opencode
// tool names are `<server>_<tool>` (verified in spike S6).
const JIRA_WRITE = /^atlassian_.*(create|edit|add|transition|update|delete)/i

function issueKeyOf(args: Record<string, unknown> | undefined): string {
  for (const k of ["issueKey", "issue_key", "key", "id"]) {
    const v = args?.[k]
    if (typeof v === "string" && v) return v
  }
  return "unknown"
}

async function auditJiraWrite(directory: string, tool: string, args: Record<string, unknown> | undefined, ok: boolean) {
  const ts = new Date().toISOString().replace(/\.\d{3}Z$/, "Z") // same shape as `date -u +%Y-%m-%dT%H:%M:%SZ`
  const user = process.env.QA_AUDIT_USER ?? process.env.USER ?? "unknown"
  const line = `${ts} | tool=${tool || "unknown"} | key=${issueKeyOf(args)} | result=${ok ? "ok" : "error"} | user=${user}\n`
  const logDir = join(directory, "evidence", ".audit")
  await mkdir(logDir, { recursive: true })
  await appendFile(join(logDir, "jira-writes.log"), line)
}

// --------------------------------------------------------------------------
// 3. Evidence gate (port of stop-evidence-check.sh, redesigned per D3)
// --------------------------------------------------------------------------

const PLAYWRIGHT_TOOL = /^playwright_/
// Same anchored first-line runner regex as the bash hook: a heredoc that
// merely CONTAINS "npx playwright test" must not count as a test run.
const PLAYWRIGHT_CLI = /^\s*(?:cd\s+\S+\s*&&\s*)?(?:(?:npx|pnpm|yarn|bunx)\s+(?:--\S+\s+)*)?(?:playwright\s+test\b|(?:npm|pnpm|yarn|bun)\s+(?:run\s+)?(?:test|e2e|test:e2e|test:ui)\b)/

const FRESH_MS = 2 * 3600_000 // "roughly this session", same 2h as the bash hook

function isTestActivity(tool: string, args: Record<string, unknown> | undefined): boolean {
  if (PLAYWRIGHT_TOOL.test(tool)) return true
  if (JIRA_WRITE.test(tool)) return true
  if (tool === "bash") {
    const command = typeof args?.command === "string" ? args.command : ""
    const firstLine = command.replace(/^\n+/, "").split("\n", 1)[0]
    return PLAYWRIGHT_CLI.test(firstLine)
  }
  return false
}

interface GateResult {
  status: "ok" | "no_dir" | "evidence_missing" | "learnings_missing"
  files: string[]
}

async function findFreshSummaries(evidenceDir: string): Promise<string[]> {
  const cutoff = Date.now() - FRESH_MS
  const out: string[] = []
  const stack = [evidenceDir]
  while (stack.length) {
    const d = stack.pop()!
    let entries
    try {
      entries = await readdir(d, { withFileTypes: true })
    } catch {
      continue
    }
    for (const e of entries) {
      const p = join(d, e.name)
      if (e.isDirectory()) {
        if (e.name === "node_modules" || e.name === ".git") continue
        stack.push(p)
      } else if (e.name === "execution_summary.json") {
        try {
          const st = await stat(p)
          if (st.mtimeMs >= cutoff) out.push(p)
        } catch { /* vanished mid-scan — ignore */ }
      }
    }
  }
  return out
}

async function evaluateGate(directory: string): Promise<GateResult> {
  const evidenceDir = join(directory, "evidence")
  if (!existsSync(evidenceDir)) return { status: "no_dir", files: [] } // nothing scaffolded → nothing to enforce (bash: exit 0)

  const fresh = await findFreshSummaries(evidenceDir)
  if (fresh.length === 0) return { status: "evidence_missing", files: [] }

  const missing: string[] = []
  for (const f of fresh) {
    let d: unknown
    try {
      d = JSON.parse(await readFile(f, "utf8"))
    } catch {
      continue // unparseable summary is a separate problem; don't ALSO claim it lacks learnings
    }
    const l = (d as Record<string, unknown>)?.learnings
    if (typeof l !== "object" || l === null || Array.isArray(l)) {
      missing.push(f)
      continue
    }
    const captured = (l as Record<string, unknown>).captured
    const noneBecause = (l as Record<string, unknown>).none_because
    const hasCaptured = Array.isArray(captured) && captured.length > 0
    const hasNoneBecause = typeof noneBecause === "string" && noneBecause.trim().length > 0
    if (!hasCaptured && !hasNoneBecause) missing.push(f)
  }
  return missing.length ? { status: "learnings_missing", files: missing } : { status: "ok", files: [] }
}

const EVIDENCE_MISSING_MSG = `QA_EVIDENCE_MISSING: this session actually invoked a Playwright MCP tool, an
Atlassian write (create/edit/transition/...), or the Playwright CLI runner,
but no execution_summary.json was written under evidence/<KEY>/<TICKET>/ in
the last 2 hours.

Before reporting to JIRA or ending the session:
  - write evidence/<KEY>/<TICKET>/<YYYYMMDD-HHMMSS>/execution_summary.json
    (schema: .claude/rules/core/evidence-policy.md), or
  - if no test actually completed (still investigating, aborted), write a
    minimal summary with "verdict": "NO_TEST", a one-line "no_test_reason"
    and the usual "learnings" declaration — the explicit alternative to
    stopping silently.`

const learningsMissingMsg = (files: string[]) => `QA_LEARNINGS_MISSING: this run produced evidence, but the summary
does not declare what was learned. Affected file(s):
${files.map((f) => `  ${f}`).join("\n")}

Add a "learnings" object to each one (.claude/rules/core/evidence-policy.md):

  "learnings": {
    "captured": ["one line per entry written to memory/learnings/_inbox.md"],
    "none_because": null
  }

or, for a genuinely uneventful run, the other way round:

  "learnings": { "captured": [], "none_because": "clean run, no surprises" }`

// --------------------------------------------------------------------------
// 4. Bootstrap (port of bootstrap_dirs + seed_browser_config)
// --------------------------------------------------------------------------

const SECRETS_TEMPLATE = `# Secrets consumed by Playwright MCP via --secrets (values are masked in tool
# responses, so the agent never sees them). Gitignored — never commit.
# Reference per-project test users by the keys used in projects/<KEY>/PROJECT.md.
# Example:
# SHOP_QA_STANDARD_PASSWORD=replace-me
`

const BROWSER_CONFIG = `{
  "browser": {
    "isolated": true,
    "launchOptions": { "headless": true }
  }
}
`

async function bootstrap(directory: string) {
  // memory/ and evidence/ are copied from the blueprint root when missing —
  // never overwritten; they become the consumer's own data.
  for (const d of ["memory", "evidence"]) {
    const target = join(directory, d)
    const source = join(BLUEPRINT_ROOT, d)
    if (!existsSync(target) && existsSync(source)) {
      await cp(source, target, { recursive: true }).catch(() => {})
    }
  }
  // projects/ is created EMPTY on purpose: _template/EXAMPLE stay in the
  // blueprint and are read from there by onboard-project.
  await mkdir(join(directory, "projects"), { recursive: true }).catch(() => {})

  // --secrets is a hard fail on ENOENT → seed the comment-only placeholder.
  const secretsFile = join(directory, ".env.playwright-secrets")
  if (!existsSync(secretsFile)) {
    await writeFile(secretsFile, SECRETS_TEMPLATE).catch(() => {})
    // Only append the gitignore entry when the consumer is a git repo and the
    // file is not already ignored (same conditions as the bash hook).
    const isRepo = spawnSync("git", ["-C", directory, "rev-parse", "--git-dir"], { stdio: "ignore" }).status === 0
    const isIgnored = isRepo && spawnSync("git", ["-C", directory, "check-ignore", "-q", ".env.playwright-secrets"], { stdio: "ignore" }).status === 0
    if (isRepo && !isIgnored) {
      await appendFile(join(directory, ".gitignore"), "\n# QA Agent Blueprint — Playwright MCP secrets, never commit\n.env.playwright-secrets\n").catch(() => {})
    }
  }

  // --config is a hard fail on ENOENT too. The file is the consumer's own
  // preference dial (headful = launchOptions.headless false) — seed, never
  // overwrite, and deliberately NOT gitignored (it holds no secrets).
  const browserCfg = join(directory, ".playwright-mcp.config.json")
  if (!existsSync(browserCfg)) {
    await writeFile(browserCfg, BROWSER_CONFIG).catch(() => {})
  }
}

// --------------------------------------------------------------------------
// 5. Secrets via shell.env (replaces the $CLAUDE_ENV_FILE PAT export)
// --------------------------------------------------------------------------

interface Deps {
  // Injected in tests. Default: macOS keychain service JIRA_PAT_<jira-host>,
  // host derived from JIRA_URL — the token lives in no file and no chat
  // (docs/rules/core/security.md).
  resolveJiraPat?: () => Promise<string | undefined>
}

function defaultResolveJiraPat(): Promise<string | undefined> {
  if (process.platform !== "darwin") return Promise.resolve(undefined)
  const url = process.env.JIRA_URL
  if (!url) return Promise.resolve(undefined)
  let host: string
  try {
    host = new URL(url).hostname
  } catch {
    return Promise.resolve(undefined)
  }
  if (!host) return Promise.resolve(undefined)
  const r = spawnSync("security", ["find-generic-password", "-s", `JIRA_PAT_${host}`, "-w"], { encoding: "utf8" })
  if (r.status !== 0) return Promise.resolve(undefined)
  const value = (r.stdout ?? "").trim()
  return Promise.resolve(value || undefined)
}

// --------------------------------------------------------------------------
// Plugin assembly
// --------------------------------------------------------------------------

interface PluginCtx {
  directory: string
  client?: {
    session?: { prompt?: (args: unknown) => Promise<unknown> }
    app?: { log?: (args: unknown) => Promise<unknown> }
  }
}

export async function qaBlueprint(ctx: PluginCtx, deps: Deps = {}) {
  const directory = ctx.directory
  await bootstrap(directory)

  // Evidence-gate session state (D3): which sessions showed test activity, and
  // which already got the idle reminder (the stop_hook_active loop-breaker's
  // equivalent).
  const testActivity = new Set<string>()
  const idleReminded = new Set<string>()

  async function gateMessageFor(sessionID: string): Promise<string | null> {
    if (!testActivity.has(sessionID)) return null
    const gate = await evaluateGate(directory)
    if (gate.status === "evidence_missing") return EVIDENCE_MISSING_MSG
    if (gate.status === "learnings_missing") return learningsMissingMsg(gate.files)
    return null
  }

  return {
    "tool.execute.before": async (
      input: { tool: string; sessionID: string; callID: string },
      output: { args: Record<string, unknown> },
    ) => {
      const args = output?.args ?? {}
      guardCheck(input?.tool ?? "", args)

      // Evidence gate: the verdict must not reach JIRA without evidence.
      if (input?.tool && JIRA_WRITE.test(input.tool)) {
        const msg = await gateMessageFor(input.sessionID)
        if (msg) throw new Error(msg)
      }
    },

    "tool.execute.after": async (
      input: { tool: string; sessionID: string; callID: string; args?: Record<string, unknown> },
      output?: { title?: string; metadata?: Record<string, unknown>; output?: string },
    ) => {
      const tool = input?.tool ?? ""
      if (tool && isTestActivity(tool, input?.args)) {
        testActivity.add(input.sessionID)
      }
      // Audit: never blocks, never throws (the bash hook exits 0 always).
      if (tool && JIRA_WRITE.test(tool)) {
        try {
          const failed = Boolean(output?.metadata?.error)
          await auditJiraWrite(directory, tool, input?.args, !failed)
        } catch { /* logging must never break a session */ }
      }
    },

    event: async ({ event }: { event: { type: string; properties?: Record<string, unknown> } }) => {
      if (event?.type !== "session.idle") return
      const sessionID = String(event.properties?.sessionID ?? "")
      if (idleReminded.has(sessionID)) return
      const msg = await gateMessageFor(sessionID)
      if (!msg) return
      idleReminded.add(sessionID)
      // Re-engage the session instead of blocking a stop (opencode has no
      // exit-2 equivalent) — same markers, same demanded artifacts.
      await ctx.client?.session?.prompt?.({
        path: { id: sessionID },
        body: { parts: [{ type: "text", text: msg }] },
      } as never).catch(() => {})
    },

    "shell.env": async (_input: { cwd: string }, output: { env: Record<string, string> }) => {
      // Explicit environment wins; the keychain is only a fallback.
      if (process.env.JIRA_PERSONAL_TOKEN) return
      const resolve = deps.resolveJiraPat ?? defaultResolveJiraPat
      const pat = await resolve().catch(() => undefined)
      if (pat) output.env.JIRA_PERSONAL_TOKEN = pat
    },
  }
}

export default qaBlueprint

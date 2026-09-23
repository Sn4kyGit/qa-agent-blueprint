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
//   SessionStart orientation     →  session.created → session.prompt noReply
//                                   (projects, inbox count, MCP contract hints)
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
// grep/sed/awk/jq are readers too (0.6.1 field report: `grep -o '^[A-Z_]*='`
// on the secrets file sailed through the old list).
// 0.11.0 (tdd §8/F1): cp|mv split OUT of the reader class — movers relocate
// the file and stay blocked in BOTH toggle states; the READER_CORE class
// follows the secrets_read toggle in .qa-guard.json (default: block).
const ENV_READER = /(^|[;&|(]|&&|\|\|)\s*(cat|less|more|head|tail|grep|sed|awk|jq|source)\s+[^;&|]*\.env([^a-zA-Z]|$)/
const ENV_MOVER = /(^|[;&|(]|&&|\|\|)\s*(cp|mv)\s+[^;&|]*\.env([^a-zA-Z]|$)/
// sed -i / awk -i edit in place — a WRITE, not a read. The flag must sit
// directly after the command: -i, -i.bak, --in-place, -i inplace.
const ENV_INPLACE = /(^|[;&|(]|&&|\|\|)\s*(sed|awk)\s+(-[a-zA-Z]*i[a-zA-Z.]*|--in-place)\s[^;&|]*\.env([^a-zA-Z]|$)/
// rm hardening (tdd §9/F2): plain `rm <.env*>` used to sail through — only
// rm -rf was blocked. Deleting a secrets file is a human task.
const ENV_RM = /(^|[;&|(]|&&|\|\|)\s*rm\s+(-[a-zA-Z]+\s+)*[^;&|]*\.env([^a-zA-Z]|$)/
// The guard's own toggle file is a human task: an agent that can write
// .qa-guard.json can grant itself secrets_read=allow (self-escalation).
const GUARD_CFG_WRITER = /(sed\s+(-[a-zA-Z]*i[a-zA-Z.]*|--in-place)|tee\s|>>?|cp\s|mv\s|rm\s|truncate|dd\s)[^;&|]*\.qa-guard\.json/
// The next-most-likely bypass class: interpreter one-liners that OPEN the
// file. The open/read/load keyword is required so `python3 -c "note='.env
// template'"` — merely mentioning the name — stays allowed (audit F4: the
// false-positive rate must stay visible in fixtures). Best-effort net; the
// real guarantee is --secrets masking at the browser layer.
const ENV_INTERPRETER = /(python3?|perl|ruby|node|php)\s[^;&|]*(open|read|load|require|include|slurp)[^;&|]*\.env([^a-zA-Z]|$)/
const ENV_REDIRECT = />>?\s*\.env/

// Tools whose filePath argument is a WRITE (reads are governed by opencode
// permission denies — D8 — not by this guard, same split as Claude where the
// hook matcher only covered Bash|Write|Edit|MultiEdit|NotebookEdit).
const WRITE_TOOLS = new Set(["write", "edit", "multiedit", "patch", "apply_patch", "notebook_edit"])

// MCP config is project-scoped (field report 2026-09-22: a GLOBAL gitlab MCP
// server pointed at a different customer's .env — the agent nearly edited it,
// saved only by the secrets guard). Another project's config/data is never
// used or touched here, by design: (a) the agent never writes global MCP
// config, (b) a call to a server that exists only in global config is blocked
// until the human declares the server in the project's own config.
const FOREIGN_MCP_MSG = "refusing a call to MCP server '${SERVER}' — it is configured globally but not declared in this project's config (.mcp.json / opencode.json). Global MCP config may point at another project's credentials or data — and another project's data is never used here, by design. Declare the server in this project's own config to use it deliberately. Escape hatch: QA_ALLOW_GLOBAL_MCP=1."
const GLOBAL_MCP_WRITE_MSG = "refusing to modify global MCP config ($FILE_PATH) — MCP config is project-scoped here: a project's servers live in its own .mcp.json / opencode.json, never in global config (~/.claude.json, ~/.config/opencode). Another project's data is never used or touched — global config edits are a human task. Escape hatch: QA_ALLOW_GLOBAL_MCP=1."

function globalMcpConfigPaths(): Set<string> {
  const home = process.env.HOME ?? ""
  const cfgHome = process.env.XDG_CONFIG_HOME ?? join(home, ".config")
  return new Set([
    join(home, ".claude.json"),
    join(cfgHome, "opencode", "opencode.json"),
    join(cfgHome, "opencode", "opencode.jsonc"),
  ])
}

// A writer verb followed (in the same command segment) by a global config
// path. `.claude.json` is unique to $HOME; the opencode match requires the
// .config prefix so a PROJECT's opencode.json never trips this.
const GLOBAL_CFG_WRITER = /(?:sed\s+-i|\btee\b|>>?|\bcp\b|\bmv\b|\brm\b|truncate|dd\s)[^;&|]*(?:\.claude\.json|\.config\/opencode\/opencode\.jsonc?)/

const BLUEPRINT_MCP = new Set(["playwright", "atlassian"])

const mcpNameCache = new Map<string, { mtimeMs: number; names: Set<string> }>()
async function mcpNamesOf(path: string): Promise<Set<string>> {
  try {
    const st = await stat(path)
    const hit = mcpNameCache.get(path)
    if (hit && hit.mtimeMs === st.mtimeMs) return hit.names
    const cfg = await readJsonc(path)
    const names = new Set(Object.keys((cfg?.mcp ?? {}) as Record<string, unknown>))
    mcpNameCache.set(path, { mtimeMs: st.mtimeMs, names })
    return names
  } catch {
    return new Set<string>()
  }
}

// Returns the offending server name when `tool` is an MCP call to a server
// that exists ONLY in global config. Global-file unreadable → no gate: the
// prefix may be a builtin tool, not an MCP server at all (fail precise, not
// loud — the KPS case had the global file readable).
async function foreignMcpServer(directory: string, tool: string): Promise<string | undefined> {
  if (process.env.QA_ALLOW_GLOBAL_MCP === "1") return undefined
  const m = /^([a-zA-Z0-9-]+)_/.exec(tool)
  if (!m) return undefined
  const server = m[1]
  if (BLUEPRINT_MCP.has(server)) return undefined
  const project = new Set([...(await mcpNamesOf(join(directory, "opencode.json"))), ...(await mcpNamesOf(join(directory, "opencode.jsonc")))])
  if (project.has(server)) return undefined
  const cfgHome = process.env.XDG_CONFIG_HOME ?? join(process.env.HOME ?? "", ".config")
  const global_ = new Set([...(await mcpNamesOf(join(cfgHome, "opencode", "opencode.json"))), ...(await mcpNamesOf(join(cfgHome, "opencode", "opencode.jsonc")))])
  if (global_.has(server)) return server
  return undefined
}

// For the session-start orientation: global MCP servers not declared in this
// project (the guard blocks them — surface the trap before the agent hits it).
async function foreignGlobalMcpNames(directory: string): Promise<string[]> {
  const cfgHome = process.env.XDG_CONFIG_HOME ?? join(process.env.HOME ?? "", ".config")
  const globalNames = new Set([...(await mcpNamesOf(join(cfgHome, "opencode", "opencode.json"))), ...(await mcpNamesOf(join(cfgHome, "opencode", "opencode.jsonc")))])
  const projectNames = new Set([...(await mcpNamesOf(join(directory, "opencode.json"))), ...(await mcpNamesOf(join(directory, "opencode.jsonc")))])
  return [...globalNames].filter((n) => !projectNames.has(n) && !BLUEPRINT_MCP.has(n)).sort()
}

function block(reason: string): never {
  throw new Error(`${GUARD_PREFIX} ${reason}`)
}

function guardCheck(tool: string, args: Record<string, unknown>, secretsRead: "block" | "allow" = "block") {
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
  // The guard's own toggle file is a human task — an agent that can edit it
  // can grant itself secrets_read=allow, and the toggle would be theater.
  if (filePath && WRITE_TOOLS.has(tool) && (filePath === ".qa-guard.json" || filePath.endsWith("/.qa-guard.json"))) {
    block("refusing to modify .qa-guard.json — the guard's own toggle is a human task (an agent that can edit it can grant itself secrets_read=allow).")
  }

  if (process.env.QA_ALLOW_GLOBAL_MCP !== "1") {
    if (filePath && WRITE_TOOLS.has(tool) && globalMcpConfigPaths().has(filePath)) {
      block(GLOBAL_MCP_WRITE_MSG.replace("$FILE_PATH", filePath))
    }
    if (tool === "bash" && GLOBAL_CFG_WRITER.test(typeof args.command === "string" ? args.command : "")) {
      block(GLOBAL_MCP_WRITE_MSG.replace("$FILE_PATH", "the command line"))
    }
  }

  if (tool === "bash") {
    const command = typeof args.command === "string" ? args.command : ""
    if (RM_RF.test(command)) block("refusing rm -rf / rm -fr — destructive command.")
    if (GIT_FORCE_PUSH.test(command)) block("refusing git push --force — see the git safety protocol before overriding this manually.")
    if (GUARD_CFG_WRITER.test(command)) block("refusing to modify .qa-guard.json — the guard's own toggle is a human task (an agent that can edit it can grant itself secrets_read=allow).")
    // Strip only the literal ".env.example" before the .env checks: the
    // template must stay writable; .env/.env.local/.env.playwright-secrets
    // still match in full.
    const noExample = command.replaceAll(".env.example", "")
    if (ENV_RM.test(noExample)) block("refusing to delete a .env* file — removing a secrets file is a human task (blocked regardless of secrets_read).")
    if (ENV_MOVER.test(noExample)) block("refusing to copy/move a .env* file — secrets never leave their protected file (blocked regardless of secrets_read).")
    if (ENV_INPLACE.test(noExample)) block("refusing an in-place edit of a .env* file — sed -i / awk -i is a write, not a read (blocked regardless of secrets_read).")
    // READER_CORE follows the secrets_read toggle (tdd §7); default: block.
    if (secretsRead !== "allow" && ENV_READER.test(noExample)) block("refusing a command that reads a .env* file — secrets never enter chat or context by default. To check which keys exist: resolve-secrets.sh --status. Direct reads are a comfort opt-in: secrets_read=allow in .qa-guard.json (a human task — the guard refuses edits to it).")
    // Interpreters do NOT follow the toggle (tdd §10/§11): a regex cannot
    // tell open('.env') from open('.env','w') — allowing this class would
    // open a secret-WRITE hole, so it fails closed in both states.
    if (ENV_INTERPRETER.test(noExample)) block("refusing a command that appears to read a .env* file via an interpreter — interpreter payloads cannot be classified read-vs-write reliably, so this class stays blocked even with secrets_read=allow. To check which keys exist: resolve-secrets.sh --status.")
    if (ENV_REDIRECT.test(noExample)) block("refusing a command that writes into a .env* file directly — use the vault/secrets workflow instead.")
  }
}

// secrets_read toggle (0.11.0, tdd §7): read per call from the QA home's
// .qa-guard.json, like the bash guard — a human can flip it mid-session.
// Anything but the exact string "allow" (missing file, missing key, invalid
// JSON, other value) fails closed to "block".
async function secretsReadMode(home: string): Promise<"block" | "allow"> {
  try {
    const cfg = JSON.parse(await readFile(join(home, ".qa-guard.json"), "utf8")) as Record<string, unknown>
    return cfg.secrets_read === "allow" ? "allow" : "block"
  } catch {
    return "block"
  }
}

// --------------------------------------------------------------------------
// 2. JIRA write audit (port of post-jira-audit.sh)
// --------------------------------------------------------------------------

// D5 mapping: Claude matched `mcp__.*atlassian__.*(create|edit|…).*`; opencode
// tool names are `<server>_<tool>` (verified in spike S6). executeWrite/
// executeDestructive are the Atlassian v2 meta-tools for DEFERRED tools
// (uploadAttachmentToJiraIssue & co.) — writes by definition; executeRead is
// deliberately absent (read-only deferred tools must stay open).
const JIRA_WRITE = /^atlassian_.*(create|edit|add|transition|update|delete|executeWrite|executeDestructive)/i

function issueKeyOf(args: Record<string, unknown> | undefined): string {
  for (const k of ["issueKey", "issue_key", "key", "id"]) {
    const v = args?.[k]
    if (typeof v === "string" && v) return v
  }
  // execute-wrapped calls nest the key in the inner tool's arguments — first
  // ticket-shaped string wins (same regex as the bash hooks).
  const m = /[A-Z][A-Z0-9]+-[0-9]+/.exec(JSON.stringify(args ?? {}))
  return m ? m[0] : "unknown"
}

async function auditJiraWrite(directory: string, tool: string, args: Record<string, unknown> | undefined, ok: boolean) {
  const ts = new Date().toISOString().replace(/\.\d{3}Z$/, "Z") // same shape as `date -u +%Y-%m-%dT%H:%M:%SZ`
  const user = process.env.USER ?? "unknown" // parity with the bash hook ($USER)
  const line = `${ts} | tool=${tool || "unknown"} | key=${issueKeyOf(args)} | result=${ok ? "ok" : "error"} | user=${user}\n`
  const logDir = join(directory, "evidence", ".audit")
  await mkdir(logDir, { recursive: true })
  await appendFile(join(logDir, "jira-writes.log"), line)
}

// --------------------------------------------------------------------------
// 2b. Shadow gate (port of the guard's shadow check, audit 2026-09-18 F1)
// --------------------------------------------------------------------------

// No JIRA write leaves the building by default: verdicts are composed into
// evidence/ as proposed-report.md until the project opts out ("Shadow mode:
// off" in projects/<KEY>/PROJECT.md) or QA_AGENT_SHADOW=0 is set. Fails safe:
// an unresolvable ticket key or unreadable project file keeps the gate closed.
const SHADOW_MSG = "refusing a JIRA write while Shadow Mode is on (default). Compose the report as evidence/<KEY>/<TICKET>/<ts>/proposed-report.md instead. Unlock: 'Shadow mode: off' in projects/<KEY>/PROJECT.md, or QA_AGENT_SHADOW=0."

async function shadowGateBlocks(directory: string, tool: string, args: Record<string, unknown> | undefined): Promise<boolean> {
  if (!tool) {
    // fail closed: an unparsable call that looks like an Atlassian write is one.
    // `__?` mirrors the bash fallback (1–2 underscores: opencode tool names use
    // one, a raw Claude-style payload carries `atlassian__createJiraIssue`).
    if (!/atlassian__?[a-z]*(create|edit|add|transition|update|delete|executeWrite|executeDestructive)/i.test(JSON.stringify(args ?? {}))) return false
    tool = "atlassian_create"
  }
  if (!JIRA_WRITE.test(tool)) return false
  if ((process.env.QA_AGENT_SHADOW ?? "1") === "0") return false
  const key = issueKeyOf(args)
  if (key !== "unknown") {
    const proj = key.split("-")[0]
    try {
      const md = await readFile(join(directory, "projects", proj, "PROJECT.md"), "utf8")
      if (/shadow mode:\s*off/i.test(md)) return false
    } catch { /* unreadable → gate stays closed */ }
  }
  return true
}

// --------------------------------------------------------------------------
// 2c. Preflight gate (port of the guard's preflight check)
// --------------------------------------------------------------------------

// No browser/JIRA MCP call before a preflight has passed: the classic
// false-positive factory is a forgotten VPN — stage and JIRA are unreachable
// and the "result" describes the environment, not the product. preflight.sh
// writes evidence/.preflight/ok.json on a full pass and REMOVES it on
// failure; this gate only checks artifact freshness, never probes the
// network (a probe per tool call would tax every call).
// opencode tool names are `<server>_<tool>` (same D5 mapping as JIRA_WRITE).
const BROWSER_JIRA_TOOL = /^(playwright|atlassian)_/i

const PREFLIGHT_MSG = "refusing browser/JIRA MCP calls before a preflight has passed (evidence/.preflight/ok.json missing or older than ${TTL}m). Run the blueprint's preflight.sh <KEY> first — it probes stage/JIRA reachability (incl. VPN hints + multiple-VPN detection) and secrets status. Override: QA_PREFLIGHT=0."

async function preflightGateBlocks(directory: string, tool: string): Promise<boolean> {
  if (!tool || !BROWSER_JIRA_TOOL.test(tool)) return false
  if ((process.env.QA_PREFLIGHT ?? "1") === "0") return false
  // nothing to preflight against when no project is onboarded (parity with
  // the bash gate's `ls projects/*/PROJECT.md` existence check)
  let hasProject = false
  try {
    for (const e of await readdir(join(directory, "projects"))) {
      try {
        await stat(join(directory, "projects", e, "PROJECT.md"))
        hasProject = true
        break
      } catch { /* no PROJECT.md in this entry */ }
    }
  } catch { return false } // no projects dir at all → nothing to gate
  if (!hasProject) return false
  const ttlMin = Number(process.env.QA_PREFLIGHT_TTL_MIN ?? "60")
  try {
    const raw = await readFile(join(directory, "evidence", ".preflight", "ok.json"), "utf8")
    const m = raw.match(/"checked_at":\s*(\d+)/)
    if (m && (Date.now() / 1000 - Number(m[1])) / 60 < ttlMin) return false
  } catch { /* missing/unreadable artifact → gate stays closed */ }
  block(PREFLIGHT_MSG.replace("${TTL}", String(ttlMin)))
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
  /** Ticket keys that lack fresh evidence (F2) — empty on the global fallback. */
  missingKeys: string[]
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

// JIRA ticket keys (SHOP-123) found in a tool call's args — ties a test run to
// its ticket(s) for the per-ticket evidence check (audit 2026-09-18 F2).
const TICKET_KEY = /\b[A-Z][A-Z0-9]+-\d+\b/g

function ticketKeysOf(args: Record<string, unknown> | undefined): string[] {
  if (!args) return []
  let blob = ""
  try {
    blob = JSON.stringify(args)
  } catch {
    return []
  }
  return [...new Set(blob.match(TICKET_KEY) ?? [])]
}

async function evaluateGate(directory: string, keys: ReadonlySet<string>): Promise<GateResult> {
  const evidenceDir = join(directory, "evidence")
  if (!existsSync(evidenceDir)) return { status: "no_dir", files: [], missingKeys: [] } // nothing scaffolded → nothing to enforce (bash: exit 0)

  // Per-ticket scoping (F2): when the run named tickets, EACH needs its own
  // fresh summary — evidence for SHOP-1 must not satisfy a run against SHOP-2.
  // No keys extractable → global freshness fallback, same as the bash hook.
  if (keys.size > 0) {
    const missingKeys: string[] = []
    for (const k of keys) {
      const dir = join(evidenceDir, k.split("-")[0], k)
      if ((await findFreshSummaries(dir)).length === 0) missingKeys.push(k)
    }
    if (missingKeys.length > 0) return { status: "evidence_missing", files: [], missingKeys }
  } else {
    const fresh = await findFreshSummaries(evidenceDir)
    if (fresh.length === 0) return { status: "evidence_missing", files: [], missingKeys: [] }
  }

  const fresh = await findFreshSummaries(evidenceDir)
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
  return missing.length ? { status: "learnings_missing", files: missing, missingKeys: [] } : { status: "ok", files: [], missingKeys: [] }
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

// Per-ticket variant (F2) — same demanded artifacts, but names the tickets
// whose evidence is missing, mirroring the bash hook's keyed message.
const evidenceMissingMsg = (missingKeys: string[]) => `QA_EVIDENCE_MISSING: this session ran test activity against ticket(s):
${missingKeys.map((k) => `  ${k}`).join("\n")}
but no execution_summary.json was written under evidence/<KEY>/<TICKET>/ for
them in the last 2 hours. Evidence from another ticket does not cover this run.

Before reporting to JIRA or ending the session, per ticket:
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

// QA home discovery (0.9.1 — "dual evidence scaffold" field report): sessions
// may start in a SUBFOLDER of the QA home (a product repo inside the customer
// workspace). Data (projects/, memory/, evidence/) belongs at the workspace
// root, never duplicated into the subfolder. Walk up from the session cwd to
// the nearest directory carrying the .qa-home marker or the legacy trio;
// stop at $HOME or the filesystem root; nothing found → the cwd itself
// (unchanged first-install behavior).
export async function resolveQaHome(directory: string): Promise<string> {
  const home = process.env.HOME ?? ""
  let d = directory
  for (;;) {
    const present = async (name: string, dir: boolean) =>
      stat(join(d, name)).then((s) => (dir ? s.isDirectory() : true), () => false)
    if (await present(".qa-home", false)) return d
    if (await present("projects", true) && await present("memory", true) && await present("evidence", true)) return d
    if (d === home || d === dirname(d)) return directory
    d = dirname(d)
  }
}

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

  // The QA-home marker makes future walk-up resolution unambiguous (the
  // legacy trio works too, but only once all three dirs exist).
  const marker = join(directory, ".qa-home")
  if (!existsSync(marker)) {
    await writeFile(marker, "qa-agent-blueprint home — resolved by walk-up from any subfolder\n").catch(() => {})
  }
}

// Harness-scoped seeds (0.9.1 split): the MCP server is launched from the
// SESSION's cwd, so both hard-fail-on-ENOENT files belong there — not in the
// QA home when the two differ.
async function seedHarnessFiles(directory: string) {

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
// 5. Consumer config scan + session-start orientation
//    (ports of session-start.sh's mcp_scan/mcp_hint/inbox_status/browser_mode;
//    secrets_status is dead here on purpose — bootstrap above always seeds the
//    placeholder, so the file can only be MISSING if the user deleted it
//    mid-session, which the MCP server's own ENOENT error names loudly.
//    update_notice is deliberately NOT ported: the opencode install is
//    symlink-based, so a `git pull` updates the running code immediately —
//    there is no plugin-cache version skew to warn about; /whats-new covers
//    the project-side diff.)
// --------------------------------------------------------------------------

// Same comment-stripping algorithm as install.sh's parse_jsonc (never inside
// quoted strings — the template carries URLs and globs containing /* */).
function stripJsonComments(text: string): string {
  let out = ""
  let inStr = false
  let i = 0
  const n = text.length
  while (i < n) {
    const c = text[i]
    if (inStr) {
      out += c
      if (c === '"') inStr = false
      i++
    } else if (c === '"') {
      inStr = true
      out += c
      i++
    } else if (c === "/" && i + 1 < n && text[i + 1] === "/") {
      while (i < n && text[i] !== "\n") i++
    } else if (c === "/" && i + 1 < n && text[i + 1] === "*") {
      const end = text.indexOf("*/", i + 2)
      i = end === -1 ? n : end + 2
    } else {
      out += c
      i++
    }
  }
  return out
}

async function readJsonc(path: string): Promise<Record<string, unknown> | undefined> {
  try {
    return JSON.parse(stripJsonComments(await readFile(path, "utf8"))) as Record<string, unknown>
  } catch {
    return undefined // missing or malformed — a hint must never break a session
  }
}

// opencode merges the global config (~/.config/opencode) with the project
// config — scan both, project winning per server name (same read-only spirit
// as the bash mcp_scan over ~/.claude.json + .mcp.json).
async function readOpencodeMcp(directory: string): Promise<Record<string, Record<string, unknown>>> {
  const servers: Record<string, Record<string, unknown>> = {}
  const candidates = [
    join(process.env.XDG_CONFIG_HOME ?? join(process.env.HOME ?? "", ".config"), "opencode", "opencode.json"),
    join(process.env.XDG_CONFIG_HOME ?? join(process.env.HOME ?? "", ".config"), "opencode", "opencode.jsonc"),
    join(directory, "opencode.json"),
    join(directory, "opencode.jsonc"),
  ]
  for (const path of candidates) {
    const cfg = await readJsonc(path)
    const mcp = (cfg?.mcp ?? {}) as Record<string, unknown>
    for (const [name, entry] of Object.entries(mcp)) {
      servers[name] = (entry ?? {}) as Record<string, unknown> // later wins
    }
  }
  return servers
}

export interface McpScan {
  hasPw: boolean
  pwUnmasked: boolean // playwright without --secrets — passwords unmasked in tool responses
  pwNoOutdir: boolean // playwright without --output-dir — artifacts never reach evidence/
  pwNoImageomit: boolean // playwright without --image-responses omit — screenshots flood the context (~1-2k tokens each)
  hasAt: boolean
  dcHost: string // JIRA Data Center host from environment.JIRA_URL ("" when Cloud)
}

// Exported for the tests — the flags mirror the bash scan's HAS_PW/PW_UNMASKED/
// PW_NO_OUTDIR/PW_NO_IMAGEOMIT/HAS_AT/AT_DC_HOST:<host> contract.
export function scanMcpServers(servers: Record<string, Record<string, unknown>>): McpScan {
  const pw = servers.playwright
  const cmd = Array.isArray(pw?.command) ? (pw.command as unknown[]) : []
  // Contract flags apply to the LOCAL server; a remote playwright is the
  // consumer's own setup, not a contract violation.
  const pwLocal = Boolean(pw) && pw?.type !== "remote"
  // A playwright entry launched through qa-secrets.mjs mcp satisfies the
  // secrets contract by construction (ephemeral mask file) — the literal
  // --secrets flag is inside the wrapper, not the command args.
  const wrapsQaSecrets = cmd.some((a) => String(a).includes("qa-secrets"))
  const at = servers.atlassian
  const env = ((at?.environment ?? at?.env ?? {}) as Record<string, unknown>) ?? {}
  const url = typeof env.JIRA_URL === "string" ? env.JIRA_URL : ""
  return {
    hasPw: Boolean(pw),
    pwUnmasked: pwLocal && !cmd.includes("--secrets") && !wrapsQaSecrets,
    pwNoOutdir: pwLocal && !cmd.includes("--output-dir"),
    pwNoImageomit: pwLocal && !cmd.some((a) => a === "--image-responses" || String(a).startsWith("--image-responses=")),
    hasAt: Boolean(at),
    dcHost: url ? url.replace(/^https?:\/\//, "").split("/")[0] : "",
  }
}

async function productSuffix(projDir: string): Promise<string> {
  let entries
  try {
    entries = await readdir(join(projDir, "products"), { withFileTypes: true })
  } catch {
    return "" // no products/ — single-product project, byte-identical to bash
  }
  const names = entries.filter((e) => e.isDirectory() && e.name !== "_template").map((e) => e.name)
  if (names.length === 0) return ""
  const shown = names.slice(0, 6).join(", ")
  return names.length > 6 ? ` (products: ${shown}, +${names.length - 6} more)` : ` (products: ${shown})`
}

async function listProjects(directory: string): Promise<string[]> {
  let entries
  try {
    entries = await readdir(join(directory, "projects"), { withFileTypes: true })
  } catch {
    return []
  }
  const out: string[] = []
  for (const e of entries) {
    if (!e.isDirectory() || e.name === "_template" || e.name === "EXAMPLE") continue
    out.push(e.name + (await productSuffix(join(directory, "projects", e.name))))
  }
  return out
}

// The Stop gate forces learnings to be CAPTURED; nothing forces them to be
// groomed — count ungroomed inbox entries and say so once per session (the
// template ships one illustrative entry; one is not a backlog).
async function ungroomedLearnings(directory: string): Promise<number> {
  try {
    const text = await readFile(join(directory, "memory", "learnings", "_inbox.md"), "utf8")
    return text.split("\n").filter((l) => /^## \d{4}-\d{2}-\d{2} /.test(l)).length
  } catch {
    return 0
  }
}

async function browserMode(directory: string): Promise<string> {
  const cfg = await readJsonc(join(directory, ".playwright-mcp.config.json"))
  const b = (cfg?.browser ?? {}) as Record<string, unknown>
  const headless = (b?.launchOptions as Record<string, unknown> | undefined)?.headless
  const mode = headless === true ? "headless" : headless === false ? "headful (visible)" : ""
  const iso = b?.isolated === true ? "isolated" : b?.isolated === false ? "persistent profile" : ""
  const parts = [mode, iso].filter(Boolean)
  return parts.length ? `${parts.join(", ")} (your .playwright-mcp.config.json)` : ""
}

// home = the QA home (data: projects/, memory/, evidence/); sessionDir = the
// harness's cwd (MCP config, browser preferences). Same dir in the common case.
export async function orientation(home: string, sessionDir: string = home): Promise<string> {
  const projects = await listProjects(home)
  const lines = [
    "QA Agent Blueprint — session start",
    ...(home !== sessionDir
      ? [`- QA home: ${home} (resolved up from cwd ${sessionDir}) — all paths (evidence/, memory/, projects/) are relative to the QA home, not to cwd`]
      : []),
    "- Onboarded projects:",
    ...(projects.length ? projects.map((p) => `  - ${p}`) : ["  (none yet — run /onboard-project)"]),
  ]
  const bm = await browserMode(sessionDir)
  if (bm) lines.push(`- Browser: ${bm}`)
  lines.push(
    "- Read memory/INDEX.md before anything else; then only the active project's",
    "  PROJECT.md + learnings.md. No full-repo scans.",
    "- Lost? The qa-help skill lists every command (/qa-help) — plain language works too.",
  )
  const scan = scanMcpServers(await readOpencodeMcp(sessionDir))
  // Contract violations are findings in any state. Order: security, then evidence.
  if (scan.pwUnmasked) {
    lines.push("- WARNING: the playwright MCP config has no --secrets flag — passwords would appear unmasked in tool responses. Add `--secrets .env.playwright-secrets` (and fill that file) or remove the entry and use the blueprint-provided server.")
  }
  if (scan.pwNoOutdir) {
    lines.push("- WARNING: the playwright MCP config has no --output-dir flag — raw browser artifacts would not land in evidence/, breaking the evidence policy. Add `--output-dir evidence/.mcp-out` or use the blueprint-provided server.")
  }
  if (scan.pwNoImageomit) {
    lines.push("- WARNING: the playwright MCP config has no --image-responses omit — every screenshot lands in the model context as an image (~1-2k tokens per shot). Add `--image-responses omit` or use the blueprint-provided server.")
  }
  // The two day-one failures (dead playwright, unauthorized atlassian) are not
  // detectable from here — turn the configured-state scan into a concrete
  // hint, printed only while no project has been onboarded yet.
  if (projects.length === 0) {
    if (scan.hasPw && scan.hasAt) {
      lines.push("- MCP config for playwright + atlassian found — confirm both are live (`opencode mcp list`; atlassian auth: Cloud = `opencode mcp auth atlassian`, Data Center = PAT in the macOS keychain, service JIRA_PAT_<jira-host>).")
    } else {
      lines.push("- First run: confirm both MCP servers are live before testing — `opencode mcp list` should show playwright and atlassian, and atlassian must be authorized (Cloud: `opencode mcp auth atlassian`; Data Center: PAT in the keychain, service JIRA_PAT_<jira-host>). A dead playwright server and an unauthorized atlassian are the two failures that look like a broken blueprint.")
    }
  }
  if (scan.dcHost && !process.env.JIRA_PERSONAL_TOKEN) {
    lines.push(`- JIRA Data Center (${scan.dcHost}) configured — the PAT is resolved from the macOS keychain (service JIRA_PAT_${scan.dcHost}) into shells at runtime; it lives in no file and no chat.`)
  }
  const foreignMcp = await foreignGlobalMcpNames(sessionDir)
  if (foreignMcp.length) {
    lines.push(`- Global MCP servers visible but NOT declared in this project — the guard blocks them until declared here (they may belong to another project): ${foreignMcp.join(", ")}`)
  }
  const n = await ungroomedLearnings(home)
  if (n > 1) {
    lines.push(`- ${n} ungroomed learnings in memory/learnings/_inbox.md — run /retro-learn to groom and promote them (knowledge only counts once it reaches a rule, a PROJECT.md or a PRODUCT.md).`)
  }
  return lines.join("\n")
}

// --------------------------------------------------------------------------
// 6. Secrets via shell.env (replaces the $CLAUDE_ENV_FILE PAT export)
// --------------------------------------------------------------------------

interface Deps {
  // Injected in tests. Default: macOS keychain service JIRA_PAT_<jira-host>,
  // host from JIRA_URL in the process env, falling back to the DC entry in the
  // consumer's opencode.json (mcp.atlassian.environment.JIRA_URL lands in the
  // MCP server's env, NOT in opencode's own process env — the plugin must read
  // the config itself, like the bash hook's mcp_scan does). The token lives in
  // no file and no chat (docs/rules/core/security.md).
  resolveJiraPat?: (directory: string) => Promise<string | undefined>
}

async function defaultResolveJiraPat(directory: string): Promise<string | undefined> {
  if (process.platform !== "darwin") return undefined
  let host = ""
  const url = process.env.JIRA_URL
  if (url) {
    try {
      host = new URL(url).hostname
    } catch {
      host = ""
    }
  }
  if (!host) {
    host = scanMcpServers(await readOpencodeMcp(directory)).dcHost
  }
  if (!host) return undefined
  const r = spawnSync("security", ["find-generic-password", "-s", `JIRA_PAT_${host}`, "-w"], { encoding: "utf8" })
  if (r.status !== 0) return undefined
  const value = (r.stdout ?? "").trim()
  return value || undefined
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
  // 0.9.1: data paths (projects/, memory/, evidence/) resolve to the QA home
  // (walk-up), harness-scoped files stay with the session's directory.
  const home = await resolveQaHome(directory)
  await bootstrap(home)
  await seedHarnessFiles(directory)

  // Orientation is directory-level, so compute it once and inject it into each
  // new session as context (noReply — documented plugin pattern; it must not
  // trigger a response). Falls back to the app log when prompting fails.
  let orientationText: Promise<string> | undefined
  const getOrientation = () => (orientationText ??= orientation(home, directory).catch(() => ""))
  const oriented = new Set<string>()

  // Evidence-gate session state (D3): which sessions showed test activity (and
  // which ticket keys that activity touched — F2 per-ticket scoping), and
  // which already got the idle reminder (the stop_hook_active loop-breaker's
  // equivalent).
  const testActivity = new Map<string, Set<string>>()
  const idleReminded = new Set<string>()

  async function gateMessageFor(sessionID: string): Promise<string | null> {
    const keys = testActivity.get(sessionID)
    if (!keys) return null
    const gate = await evaluateGate(home, keys)
    if (gate.status === "evidence_missing") {
      return gate.missingKeys.length > 0 ? evidenceMissingMsg(gate.missingKeys) : EVIDENCE_MISSING_MSG
    }
    if (gate.status === "learnings_missing") return learningsMissingMsg(gate.files)
    return null
  }

  return {
    "tool.execute.before": async (
      input: { tool: string; sessionID: string; callID: string },
      output: { args: Record<string, unknown> },
    ) => {
      const args = output?.args ?? {}
      guardCheck(input?.tool ?? "", args, await secretsReadMode(home))

      // Foreign MCP gate: never another project's servers or data.
      const foreign = await foreignMcpServer(directory, input?.tool ?? "")
      if (foreign) block(FOREIGN_MCP_MSG.replace("${SERVER}", foreign))

      // Shadow gate first: a blocked write never reaches the evidence question.
      if (await shadowGateBlocks(home, input?.tool ?? "", args)) block(SHADOW_MSG)

      // Preflight gate: no browser/JIRA call on an unverified environment.
      await preflightGateBlocks(home, input?.tool ?? "")

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
        const keys = testActivity.get(input.sessionID) ?? new Set<string>()
        for (const k of ticketKeysOf(input?.args)) keys.add(k)
        testActivity.set(input.sessionID, keys)
      }
      // Audit: never blocks, never throws (the bash hook exits 0 always).
      if (tool && JIRA_WRITE.test(tool)) {
        try {
          const failed = Boolean(output?.metadata?.error)
          await auditJiraWrite(home, tool, input?.args, !failed)
        } catch { /* logging must never break a session */ }
      }
    },

    event: async ({ event }: { event: { type: string; properties?: Record<string, unknown> } }) => {
      if (event?.type === "session.created") {
        // opencode reports the id as properties.info.id on session.created;
        // accept properties.sessionID too (shape parity with session.idle).
        const info = event.properties?.info as Record<string, unknown> | undefined
        const sessionID = String(event.properties?.sessionID ?? info?.id ?? "")
        if (!sessionID || oriented.has(sessionID)) return
        oriented.add(sessionID)
        const text = await getOrientation()
        if (!text) return
        await ctx.client?.session?.prompt?.({
          path: { id: sessionID },
          body: { noReply: true, parts: [{ type: "text", text }] },
        } as never).catch(async () => {
          await ctx.client?.app?.log?.({ body: { service: "qa-blueprint", level: "info", message: text } } as never).catch(() => {})
        })
        return
      }
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
      const pat = await resolve(directory).catch(() => undefined)
      if (pat) output.env.JIRA_PERSONAL_TOKEN = pat
    },
  }
}

export default qaBlueprint

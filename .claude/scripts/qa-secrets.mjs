#!/usr/bin/env node
// qa-secrets — the blueprint's Level-1/Level-2 credential entry point
// (tdd.md 0.11.0, §1/§3/§4): loads ONLY the named keys from the existing
// secrets file and never prints values.
//
//   node qa-secrets.mjs run [--file <path>] KEY [KEY…] -- <command> [args…]
//   node qa-secrets.mjs mcp [--file <path>] KEY [KEY…] -- <mcp-server-command> [args…]
//
// run: injects the keys into the child process environment and redacts the
//      values (plus url-encoded/base64 forms and pairwise base64 a:b forms)
//      in the child's stdout/stderr — even naive specs logging a value do
//      not leak it (values >= MIN_REDACT_LEN chars).
// mcp: writes an EPHEMERAL mask file (0700 tmpdir, 0600 file, removed on
//      exit) holding only the named keys and appends `--secrets <file>` to
//      the server command — the curated mask file stops being a persistent
//      second source of truth (tdd.md §3/F1).
//
// Secrets file: plain KEY=VALUE dotenv (comments with #; no `export`
// prefix, no ${VAR} expansion — node:util.parseEnv). Path resolution, most
// specific first: --file flag > QA_SECRETS_FILE env > .qa-guard.json →
// "secrets_file" > `.env` in the QA home — the two overrides exist for
// per-environment files (.env.snt / .env.review): switching environments is
// a runner-invocation concern, like STAGE_BASE_URL, not a config edit.
// Relative paths resolve against the QA home, which is resolved by walking
// UP from cwd to the nearest `.qa-home` marker or the legacy
// projects/+memory/+evidence/ trio (same rule as the hooks, 0.9.1);
// fallback: the directory above this script.
//
// Companion, not replacement: resolve-secrets.sh feeds personal keychain
// items INTO the file; qa-secrets feeds file values INTO processes.
//
// Node >= 20.12 (util.parseEnv), zero dependencies.

import { spawn } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync, writeSync } from 'node:fs';
import { constants as osConstants, homedir, tmpdir } from 'node:os';
import { dirname, isAbsolute, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as util from 'node:util';

const EXIT_USAGE = 2;
const EXIT_MISSING = 3;
const HINT = 'configure credentials locally, never paste values into chat';

function die(msg, code = EXIT_USAGE) {
  writeSync(2, `qa-secrets: ${msg}\n`); // synchronous, so the message lands before exit()
  process.exit(code);
}

if (typeof util.parseEnv !== 'function') {
  die('requires Node >= 20.12 (util.parseEnv) — upgrade Node or pin the suite to a newer runtime');
}
const parseEnv = util.parseEnv;

// QA home walk-up (same rule as the bash hooks and the opencode plugin):
// nearest ancestor carrying `.qa-home` or the legacy projects/+memory/+evidence/
// trio, stopping at $HOME / filesystem root. Fallback: the directory above
// this script (shipped blueprint asset) respectively its copy in the
// consumer's QA home.
function qaHome() {
  const home = homedir();
  for (let d = resolve(process.cwd()); ; d = dirname(d)) {
    if (existsSync(join(d, '.qa-home'))) return d;
    try {
      if (existsSync(join(d, 'projects')) && existsSync(join(d, 'memory')) && existsSync(join(d, 'evidence'))) return d;
    } catch { /* keep walking */ }
    if (d === home || d === dirname(d)) break;
  }
  return resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
}
const QA_HOME = qaHome();

const DEFAULT_SECRETS_FILE = '.env';
const MIN_REDACT_LEN = 6;
const KEY_RE = /^[A-Z][A-Z0-9_]*$/;
const ENV_CONFIG_RE = /_BASE_URL$/;

// File resolution, most specific first (per-environment files like
// .env.snt/.env.review switch at the call site, not via config edits):
// --file flag > QA_SECRETS_FILE env > .qa-guard.json → secrets_file > .env.
// A custom path must still match the guard's secret-path patterns
// (.env* / *secret* / *credential*) or it loses the blueprint's write
// protection — documented in security.md.
function secretsFilePath(override) {
  let p = override || '';
  if (!p) {
    try {
      const cfg = JSON.parse(readFileSync(join(QA_HOME, '.qa-guard.json'), 'utf8'));
      if (typeof cfg?.secrets_file === 'string' && cfg.secrets_file.trim()) p = cfg.secrets_file.trim();
    } catch { /* missing or invalid → default, like the guard */ }
  }
  if (!p) p = DEFAULT_SECRETS_FILE;
  if (p === '~' || p.startsWith('~/')) p = join(homedir(), p.slice(1));
  return isAbsolute(p) ? p : join(QA_HOME, p);
}

function parseArgs(argv) {
  const [mode, ...rest] = argv;
  const sep = rest.indexOf('--');
  if (!['run', 'mcp'].includes(mode) || sep < 1 || sep === rest.length - 1) {
    die('usage: qa-secrets <run|mcp> [--file <path>] KEY [KEY…] -- <command> [args…]');
  }
  // --file belongs to the wrapper, not the key list; QA_SECRETS_FILE is the
  // script-friendly form (npm scripts per environment: test:snt/test:review).
  let file = (process.env.QA_SECRETS_FILE || '').trim();
  const keyArgs = [];
  for (let i = 0; i < sep; i++) {
    if (rest[i] === '--file') {
      if (i + 1 >= sep) die('--file needs a path argument');
      file = rest[++i];
      continue;
    }
    keyArgs.push(rest[i]);
  }
  const keys = [...new Set(keyArgs)];
  if (!keys.length) die('usage: qa-secrets <run|mcp> [--file <path>] KEY [KEY…] -- <command> [args…]');
  for (const k of keys) {
    // Invalid input is deliberately not echoed back (it could be a value
    // passed by accident).
    if (!KEY_RE.test(k)) die('invalid key name (expected [A-Z][A-Z0-9_]*)');
    if (ENV_CONFIG_RE.test(k)) die(`${k} is environment configuration, not a credential — set it in the shell/CI environment`);
  }
  const command = rest.slice(sep + 1);
  if (mode === 'mcp' && command.includes('--secrets')) {
    die('--secrets is managed by qa-secrets mcp — remove it from the wrapped command');
  }
  return { mode, keys, command, file };
}

function loadKeys(keys, fileOverride) {
  const file = secretsFilePath(fileOverride);
  let parsed;
  try {
    parsed = parseEnv(readFileSync(file, 'utf8'));
  } catch {
    die(`secrets file not readable/parseable (plain KEY=VALUE expected): ${file} — ${HINT}`, EXIT_MISSING);
  }
  const missing = keys.filter((k) => !Object.hasOwn(parsed, k) || parsed[k] === '');
  if (missing.length) die(`missing credential(s): ${missing.join(', ')} — ${HINT}`, EXIT_MISSING);
  return Object.fromEntries(keys.map((k) => [k, parsed[k]]));
}

function warnShortValues(selected, mode) {
  for (const [k, v] of Object.entries(selected)) {
    if (v.length >= MIN_REDACT_LEN) continue;
    const effect = mode === 'run'
      ? 'will not be redacted in output'
      : 'will be masked wherever it appears in MCP responses';
    process.stderr.write(`qa-secrets: note — ${k} is shorter than ${MIN_REDACT_LEN} characters and ${effect}\n`);
  }
}

// Placeholder values are the redaction footgun: masking DB_PASSWORD=secret
// would replace the ordinary WORD "secret" in every line of output. Name
// only keys whose values deserve masking; the suite reads placeholders from
// the file itself. Warning only — consistent with the short-value note.
const PLACEHOLDER_RE = /^(secret|password|passwort|admin|minioadmin|changeme|changeit|qwerty|letmein|test1234|123456|12345678)$/i;

function warnPlaceholders(selected, mode) {
  for (const [k, v] of Object.entries(selected)) {
    if (!PLACEHOLDER_RE.test(v)) continue;
    // run mode: a placeholder shorter than MIN_REDACT_LEN is never redacted
    // anyway — the short-value note already covers it.
    if (mode === 'run' && v.length < MIN_REDACT_LEN) continue;
    const where = mode === 'run' ? 'all output' : 'every MCP response';
    process.stderr.write(`qa-secrets: note — ${k} looks like a placeholder value; masking it also masks the ordinary word in ${where} — leave the key out and let the suite read it directly\n`);
  }
}

// ---------- run: injection + redaction ----------

function buildPatterns(selected) {
  const pats = [];
  const push = (v, rep) => { if (v.length >= MIN_REDACT_LEN) pats.push({ v, rep }); };
  const entries = Object.entries(selected);
  for (const [key, value] of entries) {
    if (value.length < MIN_REDACT_LEN) continue;
    for (const v of new Set([value, encodeURIComponent(value), Buffer.from(value).toString('base64')])) {
      push(v, `[redacted:${key}]`);
    }
  }
  // Verbose HTTP clients print `Authorization: Basic base64(user:pass)` —
  // cover the ordered pairs (bounded: 2 keys → 2 patterns, 4 keys → 12).
  if (entries.length >= 2 && entries.length <= 5) {
    for (const [ka, va] of entries) {
      for (const [kb, vb] of entries) {
        if (ka !== kb) push(Buffer.from(`${va}:${vb}`).toString('base64'), `[redacted:${ka}+${kb}]`);
      }
    }
  }
  return pats.sort((a, b) => b.v.length - a.v.length); // longest first
}

// Copies src to dst replacing secret values, even when a value is split
// across chunk boundaries: only the longest tail that could be the start
// of a secret is held back.
function redactingPipe(src, dst, pats) {
  const maxLen = pats.reduce((m, p) => Math.max(m, p.v.length), 0);
  const redact = (s) => pats.reduce((acc, p) => acc.split(p.v).join(p.rep), s);
  const heldTail = (s) => {
    for (let k = Math.min(maxLen - 1, s.length); k > 0; k--) {
      const tail = s.slice(-k);
      if (pats.some((p) => p.v.startsWith(tail))) return k;
    }
    return 0;
  };
  let pending = '';
  src.setEncoding('utf8'); // StringDecoder: no sliced multibyte characters
  src.on('data', (chunk) => {
    const s = redact(pending + chunk);
    const cut = s.length - heldTail(s);
    pending = s.slice(cut);
    if (cut > 0) dst.write(s.slice(0, cut));
  });
  return new Promise((res) => src.on('end', () => {
    if (pending) dst.write(redact(pending));
    res();
  }));
}

function exitLike({ code, signal }) {
  process.exitCode = signal ? 128 + (osConstants.signals[signal] ?? 1) : (code ?? 1);
}

// Terminal SIGINT reaches the whole process group, including the child —
// ignore it here so the wrapper (and with it the redaction) does not end
// before the child. SIGTERM/SIGHUP are forwarded.
function wireSignals(child) {
  process.on('SIGINT', () => {});
  for (const sig of ['SIGTERM', 'SIGHUP']) process.on(sig, () => child.kill(sig));
}

function unwireSignals() {
  process.removeAllListeners('SIGINT');
  process.removeAllListeners('SIGTERM');
  process.removeAllListeners('SIGHUP');
}

function run(selected, command) {
  const pats = buildPatterns(selected);
  const child = spawn(command[0], command.slice(1), {
    env: { ...process.env, ...selected },
    stdio: ['inherit', 'pipe', 'pipe'],
  });
  child.on('error', () => die(`could not start command: ${command[0]}`, 127));
  wireSignals(child);
  Promise.all([
    redactingPipe(child.stdout, process.stdout, pats),
    redactingPipe(child.stderr, process.stderr, pats),
    new Promise((res) => child.on('exit', (code, signal) => res({ code, signal }))),
  ]).then(([, , status]) => {
    exitLike(status);
    unwireSignals();
  });
}

// ---------- mcp: ephemeral mask file instead of a persistent copy ----------

function serializeDotenv(selected) {
  return Object.entries(selected).map(([k, v]) => {
    if (/[\r\n]/.test(v)) die(`${k} contains a line break and cannot be written to the mask file`);
    // Single quotes first (literal in dotenv); double quotes only without
    // backslash (there \n would be expanded).
    const q = ["'", '"', '`'].find((c) => !v.includes(c) && !(c === '"' && v.includes('\\')));
    if (!q) die(`${k} cannot be quoted safely for the mask file`);
    return `${k}=${q}${v}${q}`;
  }).join('\n') + '\n';
}

function mcp(selected, command) {
  const content = serializeDotenv(selected);
  const dir = mkdtempSync(join(tmpdir(), 'qa-mcp-')); // 0700
  const file = join(dir, 'secrets.env');
  const cleanup = () => rmSync(dir, { recursive: true, force: true });
  process.on('exit', cleanup);
  writeFileSync(file, content, { mode: 0o600 });
  // stdio passes through: stdout is the MCP protocol channel — the wrapper
  // never writes to it.
  const child = spawn(command[0], [...command.slice(1), '--secrets', file], { stdio: 'inherit' });
  child.on('error', () => die(`could not start command: ${command[0]}`, 127));
  wireSignals(child);
  child.on('exit', (code, signal) => {
    cleanup();
    exitLike({ code, signal });
    unwireSignals();
  });
}

const { mode, keys, command, file } = parseArgs(process.argv.slice(2));
const selected = loadKeys(keys, file);
warnShortValues(selected, mode);
warnPlaceholders(selected, mode);
(mode === 'run' ? run : mcp)(selected, command);

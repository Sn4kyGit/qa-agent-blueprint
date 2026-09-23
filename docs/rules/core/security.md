# Security — details

On-demand companion to `.claude/rules/core/security.md`, which stays in the
always-loaded layer and carries the norms. **Read this file when wiring a credential source, or when changing/reviewing a hook.**
Splitting it out is what keeps the always-on layer small; nothing here is
optional when its topic comes up.

## Credential flow: three levels

The question every login answers is **when does a secret value need to enter
the agent's context at all** — and the answer is almost always "never". Three
levels, in order of preference:

1. **Runner injection (secret-blind, preferred).** The agent names credential
   *keys*; the test runner loads the values itself straight from the existing
   `.env` and hands them to the test process only. Reference implementation:
   `.claude/scripts/qa-secrets.mjs run` (Node ≥ 20.12):

   ```bash
   node .claude/scripts/qa-secrets.mjs run STAGE_USER STAGE_PASSWORD -- npx playwright test
   ```

   It injects only the named keys into the child's environment and redacts
   their values — plaintext, base64, url-encoded and pairwise-base64 forms —
   in everything the child prints (chunk-boundary safe). The values never
   cross the agent's context, not even via a failing test's output. Suites may
   equally read `process.env` through their own config; either way: no
   wholesale `dotenv.config()` when only two keys are needed, and missing keys
   fail by key NAME, never with a value.

2. **MCP secret substitution.** The Playwright MCP server's `--secrets` flag
   resolves values server-side and masks them in every tool response. Two
   wiring shapes, both treated as secrets-wired by the installer and the
   session scans:
   - classic: `--secrets .env.playwright-secrets` (a *curated mask-scope
     file*: everything in it is masked everywhere, so it holds only the keys
     browser logins need — never `STAGE_BASE_URL`, or the stage URL would be
     masked in every snapshot);
   - wrapper: `node .claude/scripts/qa-secrets.mjs mcp STAGE_USER STAGE_PASSWORD -- npx @playwright/mcp@latest …`
     builds an *ephemeral* mask file (mode-0700 tmpdir, deleted on server
     exit) containing only the named keys — no second durable secret store.

3. **Direct read (explicit opt-in, escape hatch).** The human sets
   `{"secrets_read": "allow"}` in the QA home's `.qa-guard.json`. Then
   `cat`/`less`/`head`/`tail`/`grep`/`sed` (without `-i`)/`awk`/`jq`/`source`
   on `.env*` files pass the guard. This is **not** a value-free flow — the
   human accepts that values can enter the agent context. Even in allow mode
   the guard keeps blocking: writes/edits/redirects, `cp`/`mv` (a copy is not
   a read), `sed -i`/`awk -i`/`sed --in-place` (in-place edits are writes),
   `rm <.env*>` (deleting a secrets file is a human task), and interpreter
   one-liners (`python3 -c "open('.env').read()"`) — a regex cannot tell a
   read from a write in arbitrary code, so that class fails closed in both
   states. Anything but the exact string `"allow"` — missing file, missing
   key, invalid JSON, any other value — means block.

   The guard **refuses agent writes to `.qa-guard.json` itself** (Write/Edit
   tools and shell write-ops alike): an agent that can edit the toggle can
   grant itself access, and the toggle would be theater. Flipping it is a
   human task, like editing global MCP config.

`STAGE_BASE_URL` is **environment configuration, not a credential**: it comes
from the shell/CI environment only, never from the secrets file and never
into the `--secrets` mask file (it would get masked in snapshots). The
`*_BASE_URL` pattern is rejected by `qa-secrets.mjs` outright. The same split
applies inside a mixed env file: name only credential keys — URLs, hosts,
ports and flags are read by the suite itself, straight from the file.

**Per-environment files** (`.env.snt`, `.env.review`, …): the secrets file
resolves most-specific-first — `--file <path>` flag → `QA_SECRETS_FILE` env →
`.qa-guard.json` → `secrets_file` → `.env` in the QA home (relative paths
resolve against the QA home). Switching environments is a property of the
runner invocation — like `STAGE_BASE_URL` — not a config edit; npm scripts
per environment (`test:snt`, `test:review`) are the intended carrier. The
same works for the `mcp` wrapper (per-environment browser masking).

**Placeholder values** (`DB_PASSWORD=secret`): masking one also masks the
ordinary *word* in all output. Name only keys whose values deserve masking —
placeholders are read by the suite directly. `qa-secrets.mjs` warns on a
small placeholder list (and on values below the redaction floor); it never
blocks on them.

## Key naming and lookup

Credential keys follow one convention so scope is readable from the name:

```text
<ENV>_*       = environment-bound team test user   (STAGE_USER, PREPROD_API_PASSWORD)
SHARED_*      = usable across projects/sites       (SHARED_API_USER)
OWNER_*       = personally assigned credential     (OWNER_ANNA_SSO_PASSWORD)
```

`SHARED_*` describes *scope*, not security level — a shared admin password is
exactly as critical as any other admin credential. An owner name documents
the assignment; it is not access control. `PROJECT.md` → "Test users" may
name key identifiers (keys are not secrets); it never contains values.

When a login is needed, the lookup order is:

1. the active `PROJECT.md` for the credential identifier,
2. `resolve-secrets.sh --status` for which keys exist (names only),
3. only then ask the human — and ask for the **key or the storage path**,
   never for the value. A value pasted into chat is a leak (see "If a secret
   or PII leaks into an artifact").

**Model-B variant (paranoia tier):** if the agent must not run tests at all,
it can still *write* the specs and the exact `qa-secrets.mjs run …` command
line; the human or CI executes. Everything here holds — the value-free flow
just ends one step earlier.

## Sourcing pattern, honestly scoped

For ad-hoc commands a subshell-source remains possible:

```bash
(
  set -a
  . ./.env
  set +a
  curl -u "$STAGE_USER:$STAGE_PASSWORD" "$STAGE_BASE_URL/..."
)
```

Do **not** claim the values are "only in the subshell and never visible": a
secret consumed by a shell or child process can surface through debugging,
logging, error output or traces. The honest norm: credentials may be consumed
only for the runtime of the process that needs them; values are never
deliberately printed to stdout/stderr, interpolated into commands that get
logged, or stored in test artifacts. No `set -x`, no debug wrappers around a
sourced command. (This pattern also needs `secrets_read: "allow"` — `source`
is a reader — or it runs outside the agent, in the human's own shell.)

## Credential sources (vault CLI, or a credential MCP server)

The MCP set is configurable (`.claude/rules/core/token-discipline.md` → MCP budget),
so a password-manager or vault server may legitimately join it — a QA agent that
cannot reach test-user credentials is a QA agent that cannot log in. What does
**not** change is where secrets are allowed to exist.

A credential source may **resolve a reference for the tool that needs it**. It may
never:

- print, echo, or summarize a secret value into the transcript, a report, a ticket
  comment, an artifact, or a commit — including "just to confirm it was fetched";
- write a value into a file, `.env*` included (the PreToolUse guard blocks that
  path regardless of where the value came from) — with one deliberate exception:
  the blueprint's `resolve-secrets.sh`, documented below;
- fetch credentials for a system the current ticket does not require, or for
  production, ever;
- become the way login happens in a browser test. That path stays
  `.env.playwright-secrets` + Playwright MCP `--secrets`, because it masks the value
  in every tool response the agent sees. A vault server hands the *human* or the
  *setup step* the value; it does not hand it to the model mid-test.

The safe pattern is unchanged: `projects/<KEY>/PROJECT.md` names the vault path and
the secret key, the agent references the key, and the value never enters context.
If a credential server makes a value visible anyway, that is an incident under "If
a secret or PII leaks into an artifact" below — delete, redo, capture the gap.

## Declared sources: `env-file` and `keychain`

Each project declares in `PROJECT.md` → "Test users" how its secret keys reach
`.env.playwright-secrets` (`Secrets source`, products may override):

- **`env-file`** (default, also when the field is absent): the user fills the
  gitignored file by hand. Nothing automated — the original behavior.
- **`keychain`** (macOS): each secret key is a login-keychain service of the
  same name, stored once by the human
  (`security add-generic-password -s <SECRET_KEY> -a qa -w`). The blueprint's
  `.claude/hooks/resolve-secrets.sh` regenerates the managed block of
  `.env.playwright-secrets` from those services.

`resolve-secrets.sh` is the **only sanctioned writer** of the secrets file, and
it is built so the agent may run it directly:

- it never prints a value — stdout is key names and status only (fixture-tested:
  no fixture value ever reaches the hook's context output);
- it preserves user lines outside its managed block, and a key that fails to
  resolve (locked keychain) keeps its previously resolved value — a locked
  keychain never downgrades the file;
- the file keeps its existing threat model: gitignored, `chmod 600`, and the
  guard still blocks the agent from writing or reading it directly.

Resolution is triggered deliberately, not continuously: at onboarding, on
`/re-board`, and at session start only when the file is missing. The session
preamble shows a pure file-based status (`n/m keys present`, missing keys by
name) so the agent knows what it has instead of inventing credentials — that
visibility is the point of the mechanism, and it never touches the keychain.

The same script owns the two **assisted storage** paths, so the human never
has to type `security` commands by hand — and never pastes a password into
the chat to hand it over:

- `--import` migrates values a user already hand-filled into
  `.env.playwright-secrets` (env-file history) into the keychain — declared
  keys only, values travel via stdin, existing keychain items are kept unless
  `--force`;
- `--capture` asks for each missing key through a native macOS hidden-answer
  dialog (`osascript`) and stores it straight into the keychain — the value
  passes through a GUI box and a pipe, never through the transcript. Headless
  (CI, SSH) it degrades to printing the manual one-time commands.

If a user pastes a password into the chat anyway, that is a leak under "If a
secret or PII leaks into an artifact" — offer `--capture` for the next one
instead of repeating it anywhere.

**JIRA Data Center PAT** follows the same principle one level up: service
`JIRA_PAT_<jira-host>` (host from the atlassian entry's `JIRA_URL`), resolved by
the session-start hook into `$CLAUDE_ENV_FILE` — the token exists only in the
session's environment, in no file and no global shell export. An already-set
`JIRA_PERSONAL_TOKEN` always wins (CI, non-macOS). Store once:
`security add-generic-password -s JIRA_PAT_<jira-host> -a jira -w`.

## Mechanical enforcement (rules are advisory, hooks are not)

A hook counts as enforcement only once a test proves it blocks — these are shell
scripts parsing a JSON payload, and a parse failure makes them fail open while
still looking correct in review. Every hook that enforces something has fixtures:
`guard-fixtures.sh` (PreToolUse allow/block, incl. the secrets_read toggle),
`stop-evidence-fixtures.sh` (the Stop
hook's evidence *and* learning-declaration checks), `session-start-fixtures.sh`
(project/product listing), `qa-secrets-fixtures.sh` (credential injection,
redaction, ephemeral MCP mask file) and
`install-integrate-fixtures.sh` (integrate mode end
to end: namespacing, path rewriting, idempotency, uninstall) — all under
`.claude/hooks/tests/`. Run the matching one
after any change to a hook, and add a fixture for every new rule.

- `PreToolUse` guard (`pre-tool-guard.sh`) blocks `Bash`/`Write`/`Edit`/`MultiEdit`/
  `NotebookEdit` calls that touch `.env*`, attempt `rm -rf`, or force-push. The
  `.env*` classes (0.11.0): readers (`cat|less|more|head|tail|grep|sed|awk|jq|source`)
  follow the `secrets_read` toggle in `.qa-guard.json` (default block); `cp`/`mv`,
  `sed -i`/`awk -i`/`--in-place`, `rm <.env*>` and interpreter one-liners stay
  blocked in both states; agent writes to `.qa-guard.json` itself are refused
  (self-escalation). Field report 0.6.1: a `grep -o '^[A-Z_]*='` on the secrets
  file bypassed the old cat-only list; key-EXISTENCE checks go through
  `resolve-secrets.sh --status` (names only), never through the file itself.
- **MCP config is project-scoped (field report 0.9.0):** a gitlab MCP server
  configured in the *global* config (`~/.claude.json`) silently pointed at a
  different customer's `.env` in another project's folder — the agent used it
  for weeks without noticing, and only the secrets guard stopped it from
  editing the foreign file. Two mechanical rules follow, both in the
  PreToolUse guard (opencode: same logic in `qa-blueprint.ts` against
  `opencode.json` + `~/.config/opencode/`):
  1. **Foreign-server block** — a call to an MCP server that exists only in
     global config but is not declared in the project's own `.mcp.json` /
     `opencode.json` is blocked: global config may point at another project's
     credentials, and another project's data is never used here, by design.
     The blueprint's own two servers (`playwright`, `atlassian`) are always
     allowed; anything else must be declared in the project deliberately.
     Session start lists such servers as a warning before the agent hits the
     block.
  2. **Global-config write block** — the agent never modifies global MCP
     config (`~/.claude.json`, `~/.config/opencode/opencode.json*`): a
     project's servers live in its own config; global edits are a human task.
  Escape hatch for deliberate global setups: `QA_ALLOW_GLOBAL_MCP=1`.
- Permission denylist in `.claude/settings.json` prevents reads of known secret file
  patterns outright.
- `PostToolUse` JIRA write audit (`post-jira-audit.sh`) logs every Atlassian MCP
  write (create/edit/transition/delete) to `evidence/.audit/jira-writes.log` for
  traceability — including headless CI runs.

## Files that can embed tokens are scan-tooling territory

Harness config files — `~/.claude.json`, a consumer's `opencode.json` with env
maps — can carry auth tokens in server definitions. Inspecting them (which MCP
servers exist, which env keys are set) goes through the scan tooling: the
session-start `mcp_scan` (Claude) or the opencode plugin's config scan, both of
which extract only non-secret fields. Never pipe such a file through an ad-hoc
`cat | python -c …` filter you wrote yourself — from outside that process nobody
can verify the filter never printed a value (field report 0.6.1, an agent's own
honest audit of exactly this).

## Shadow mode — why it exists and how to run it

Shadow mode is **on by default** and stays on until someone explicitly grants
write access: `QA_AGENT_SHADOW=0` in the environment, or `Shadow mode: off`
under `PROJECT.md` → "Reporting". While on, it suppresses every JIRA **write**
while leaving the rest of the run untouched. It is the default because the
largest adoption risk is not technical: an agent that transitions real tickets
from day one gets switched off after the first wrong `Reopen`, and then the
blueprint is dead regardless of how good it is. Write access is therefore
something a project earns with evidence, not something it starts with.

In shadow mode the agent still: reads tickets, routes, deploys if allowed, tests,
produces evidence, composes the exact comment and names the exact transition. It
then writes them to `evidence/<KEY>/<TICKET>/<ts>/proposed-report.md` instead of
posting, and says so in its summary.

It must not: create, edit, transition or comment on any issue; upload attachments;
or describe the result as reported. `"reported_to_jira": false` plus
`"shadow": true` go into `execution_summary.json`, so `/qa-report` can tell a
shadow week from a silent week.

Everything else keeps running — routing still learns, learnings are still captured
and promoted. Two weeks of shadow operation produce a reviewable record of what the
agent *would* have written, which is the evidence a team needs before granting it
write access. The JIRA-write audit log is the check: a shadow run that produced an
entry in `evidence/.audit/jira-writes.log` is a bug, not a judgment call.

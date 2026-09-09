# Inbox — Captured Learnings (raw, ungroomed)

The capture bank (Tier 3). Every test session ends with: anything unexpected →
append here. Groomed by `/retro-learn`: duplicate check via Grep, counter bumps,
classification into topic files or `projects/<KEY>/learnings.md`, promotion at
counter ≥ 2 sessions.

## Capture format

```
## YYYY-MM-DD — <TICKET or context> (<KEY>/<PRODUCT>, if a product was routed)
- Problem: <what happened, 1 sentence>
- Cause: <why, if known — otherwise "unknown">
- Working solution: <what actually worked>
- Pattern: <error-resolution | user-correction | workaround | environment | routing>
- Candidate target: <rule | skill | PROJECT.md <KEY> | PRODUCT.md <KEY>/<PRODUCT> | learnings file>
```

Scope rides along in the header — no extra field. Whether a learning ends up
project-wide or product-specific is decided at groom time, not capture time.
The `Pattern` line gives grooming its dedupe axis (same pattern + overlapping
keywords) and pre-routes: `user-correction` → 5-Whys, `routing` → registry
upkeep. Taxonomy idea adapted from WorldFlowAI/everything-claude-code
`continuous-learning` (theirs: auto-extraction into unreviewed learned skills —
deliberately not adopted; capture is cheap here, decisions happen at groom).

## Example entry (illustrative — delete after first real capture)

## 2026-09-05 — SHOP-1234
- Problem: Submit button selector `#submit-btn` matched two elements; click hit the hidden one.
- Cause: Marketing embeds a second submit button in a template; id is not unique.
- Working solution: scope to the visible form via `form[data-testid="checkout"] >> role=button[name="Place order"]`.
- Pattern: workaround
- Candidate target: learnings file `selector-failures.md`

---

<!-- new captures below, newest on top -->

## 2026-09-07 — blueprint self-review (no ticket)
- Problem: Should the blueprint adopt WebMCP (`document.modelContext`, Chrome origin trial, Chrome-only, API in flux — `navigator.modelContext` already deprecated) as a way to drive tested websites?
- Cause: Websites register structured tools for AI agents in-page; tempting as a stable alternative to brittle selectors.
- Working solution: No — WebMCP is a new **test surface**, not a test driver. We verify what the user experiences (the UI), so Playwright stays the driver; tools a page registers get probed once per exploratory session via `browser_evaluate` (`document.modelContext?.getTools()`) and flagged for deeper coverage (schema validity, `readOnlyHint` honesty, `exposedTo`/permissions audit). No new MCP server needed — it is in-page JS, reachable through the existing playwright MCP. A full `webmcp-testing` skill is deferred until a tested product actually ships WebMCP tools.
- Candidate target: skill `exploratory-testing` (probe added to step 4) + later a vendored-style skill `webmcp-testing` when real demand appears.

## 2026-09-05 — blueprint self-review (no ticket)
- Problem: `pre-tool-guard.sh` never blocked anything (rm -rf, force push, .env writes all passed), and `post-jira-audit.sh` logged `tool=unknown result=unknown`. Both looked correct and were reported as "mechanical enforcement" in README and security rule.
- Cause: the python expressions were passed as `'print(d.get(\"tool_name\") ...)'` — inside single quotes the backslashes survive, and parameter expansion into the double-quoted `python3 -c "..."` does not remove them, so python got `\"` and raised SyntaxError. `2>/dev/null` swallowed it, empty output meant every check was skipped, and the raw-JSON fallback only triggered when python3 was ABSENT — not when parsing failed.
- Working solution: plain double quotes inside the single-quoted argument (`'print(d.get("tool_name") or "")'`), plus fail-closed fallback (`if [ -z "$TOOL_NAME" ]` regardless of python3 presence). Verified with 17 fixtures piping hook payloads into the script and asserting exit 0 vs 2.
- Candidate target: rule `.claude/rules/core/security.md` ("hooks are not advisory" — add: a hook is only enforcement once a fixture test proves it blocks) + a committed fixture test for the hooks.

## 2026-09-05 — blueprint self-review (no ticket)
- Problem: `.claudeignore` was documented in README as keeping `evidence/` out of the model context; it does not.
- Cause: Claude Code does not honor `.claudeignore` for tool reads (verified: a file under `evidence/` was readable via the Read tool; upstream issues #29455/#4160 are still open feature requests).
- Working solution: keep the file as documented intent, state the limitation in README and in the file header, and use `permissions.deny` → `Read(evidence/**)` when a hard boundary is actually needed.
- Candidate target: rule `.claude/rules/core/evidence-policy.md` / `token-discipline.md` (artifact isolation is discipline + deny rules, not `.claudeignore`)

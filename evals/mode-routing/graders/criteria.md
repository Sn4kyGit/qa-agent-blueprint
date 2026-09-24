A correct answer:

- reads the "Execution mode" section of the project file and names **`hybrid`**
  as the applicable mode (that is what the EXAMPLE project states) — not
  "depends", not a generic MCP-vs-CLI discussion detached from the file;
- describes the hybrid phase sequence: **recon first** (probe script / `/recon`,
  producing `recon.json` with real selectors — an MCP recon session only when
  the interaction itself is unclear), then a **spec written from recon.json**
  and run via the CLI runner (`test-automator`), then **verification**: the red
  check for the new spec and, since the project sets `Verification pass: yes`,
  a short live MCP observation pass after a green CLI run;
- names a legitimate **escalation** condition from docs/pipeline/00-overview.md
  (e.g. risk ≥ `Escalate at risk`, visual ticket, missing recon, unclear CLI
  failure, an AC that cannot be asserted without shortening it, a
  non-reproducible bug) — or an equivalent per-ticket override. "The test is
  red" alone is explicitly NOT an escalation trigger; an answer naming it as
  one fails this bullet.

Fails if it: ignores the mode section entirely and describes the generic
old-style flow (straight to exploratory MCP testing); places the live MCP
session as the *main* execution under hybrid (that is `mcp-only`); writes the
spec without any recon step; or omits verification (red check / observation
pass) altogether.

Not graded: the answer's language; whether it mentions plan approval (the
project sets it to yes, but the question's focus is the mode mechanics); exact
file paths of the contract files.

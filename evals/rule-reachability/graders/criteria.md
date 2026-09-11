Both answers exist only in files that are **not** auto-loaded, so a correct answer
requires actually reading them — that is what this case measures.

1. Pipe tables do not survive the ADF conversion and render as literal text: use ADF
   table nodes via the Atlassian MCP tools, or flatten into headings and bullet
   lists. Source: `docs/rules/testing/jira-confluence.md`.
2. The product must be named explicitly on the invocation (e.g.
   `/test-automation --project SHOP --product ADMIN`), because a suite run has
   no ticket to route from. Source: `docs/rules/core/cicd.md` ("A suite run has
   no ticket to route from") plus the product-layer rule. **Grade the
   consequence with care — cicd.md states two things, and both are legitimate:**
   without a declared default the routing "quietly falls to the default" is
   wrong only if the answer presents a default as guaranteed; unresolved
   routing "ends BLOCKED, loudly" is the rule's own louder bullet. An answer
   naming either consequence (or both: default if declared, BLOCKED otherwise)
   satisfies this part. What fails is the *mechanism*, not the consequence:
   claiming a suite run can derive the product from ticket data (component,
   label, epic, fix version) — a nightly run has no ticket, so those signals
   do not exist for it.

Fails if it: answers from general knowledge without opening either file (a plausible
but unsourced answer counts as a fail here); says a Markdown table is fine; or
claims the nightly run can resolve the product from component/label/secondary
signals instead of an explicit `--product` on the invocation.

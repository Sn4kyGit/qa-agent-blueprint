Both answers exist only in files that are **not** auto-loaded, so a correct answer
requires actually reading them — that is what this case measures.

1. Pipe tables do not survive the ADF conversion and render as literal text: use ADF
   table nodes via the Atlassian MCP tools, or flatten into headings and bullet
   lists. Source: `docs/rules/testing/jira-confluence.md`.
2. The product must be named explicitly on the invocation (e.g.
   `/playwright-regression --project SHOP --product ADMIN`), because a suite run has
   no ticket to route from; without it the routing table is asked to resolve from
   nothing and quietly falls back to a default. Source: `docs/rules/core/cicd.md`
   plus the product-layer rule.

Fails if it: answers from general knowledge without opening either file (a plausible
but unsourced answer counts as a fail here); says a Markdown table is fine; or
claims the nightly run infers the product on its own.

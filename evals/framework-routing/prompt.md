Treat `projects/EXAMPLE/` as the onboarded project `SHOP` (its files describe that
fictional key), with ONE difference from what's on disk: in `PROJECT.md` →
"Test assets", the fields read

    - **Framework**: webdriverio
    - **Suite**: separate repo checkout at `../shop-web-tests/`, config `wdio.conf.ts`

everything else is unchanged. The flow "pasted voucher codes are accepted at
checkout" (ticket SHOP-1412, component Checkout → product STOREFRONT) is now
understood and should become a repeatable spec.

Describe, in at most eight lines: what you delegate to whom, which conventions
file the executing agent loads, and what the resulting spec looks like (runner
command, element/wait style, title). Do not write any files.

---

This scenario is a hypothetical overlay on the repo you are in. The blueprint itself — CLAUDE.md, .claude/, docs/, and projects/EXAMPLE/ standing in for the fictional SHOP — is real and is your ground truth: READ those files as you normally would before answering. What is fictional is the scenario state layered on top (tickets, JIRA, stages, run dirs): never try to verify it on disk, never comment on its absence, never ask whether the scenario is real — the described state IS the project state for this exercise.

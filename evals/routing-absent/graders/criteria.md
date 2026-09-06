A correct answer reads `projects/ACME/PROJECT.md` and `projects/ACME/learnings.md`
— `memory/INDEX.md` first is also correct, the lookup policy starts there — and
states that **no product fields are written at all** — no `product`, no `scope`, no `product_routed_by`, and explicitly not
`"product": null`.

Fails if it: looks for or globs `projects/ACME/products/`; asks which product the
ticket belongs to; writes `"product": null` or `"scope": "project"` for a project
that has no product layer at all; or claims it must run `/onboard-product` first.

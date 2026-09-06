# Selector Failures — cross-project learnings

Unstable selectors and their working alternatives. Check this file **before**
choosing selectors in MCP sessions or specs. Groomed by `/retro-learn`; format:
dated, Problem → Cause → Solution, `seen:` counter.

Selector preference order: **`data-testid` > role/label > text > CSS classes** —
never positional XPath.

---

### 2026-08-12 — CSS utility classes break on redesign (seed) (seen: 2)
- Problem: Selectors like `.btn-primary-large` broke across a harmless CSS refactor;
  several specs failed without any product change.
- Cause: styling classes are implementation detail and change independently of
  behavior.
- Solution: use `data-testid` attributes (ask devs to add them where missing) or
  role+name locators (`role=button[name="Place order"]`); treat CSS classes as last
  resort.

### 2026-08-25 — Auto-generated ids are unstable per deploy (seed) (seen: 1)
- Problem: Ids like `#headlessui-menu-:r3:` changed between deploys; MCP snapshots
  targeted stale refs.
- Cause: framework-generated ids embed per-render counters.
- Solution: anchor on stable parents (`nav`, `form[data-testid]`) and address the
  element by role/name within; in MCP, re-snapshot after navigation instead of
  reusing refs.

### 2026-09-02 — Programmatic fill() swallowed by masked inputs (seed) (seen: 1)
- Problem: `fill()` on inputs with JS mask plugins (vouchers, IBAN, card numbers)
  left fields visually filled but empty at submit.
- Cause: the mask re-renders and drops values not coming through its input events.
- Solution: use `pressSequentially()` for masked inputs, or `fill()` + explicit
  `input` event dispatch; verify the field's value assertion before submit.

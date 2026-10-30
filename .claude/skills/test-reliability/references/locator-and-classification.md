# Locator Resilience & Flake Classification

Read this when healing broken selectors or classifying flaky tests.

## Locator Resilience

### Multi-Attribute Selectors (Beyond Fallback Chains)

A single locator strategy is a single point of failure. Multi-attribute selectors combine multiple signals for one element lookup — resilience without fallback-chain complexity.

**The key insight:** instead of "try A, then B, then C," use "find element matching A AND B AND C with tolerance for one signal missing."

```typescript
// Multi-attribute locator: tries combinations from most specific to least
const submitBtn = await multiAttributeLocator(page, {
  testId: 'checkout-submit',              // most stable signal
  role: 'button',                          // semantic signal
  name: /place order/i,                    // accessible name
  nearText: 'Order Summary',              // visual context
});
// Internally: tries testId+role+name first, then testId alone, then role+name,
// then text, then nearText+role. Returns first visible match.
// Unlike fallback chains, it combines signals for higher confidence.
```

### DOM Similarity / Neighbor Context Matching

When a locator fails, the element may still exist with changed attributes. Use surrounding DOM context to find it:

1. **Parent + tag + type:** Find the container (by testId), then locate by tag and type within it.
2. **Preceding label:** Find sibling text (label), then locate the adjacent input/button.
3. **Nearby text context:** Find visible text near the target, then locate the element type in the same parent.

These are repair candidates scored by the confidence system below — not runtime fallbacks.

### Selector Stability Scoring

Rate every selector on a 0-5 scale to prioritize refactoring.

| Score | Strategy | Survives |
|-------|----------|----------|
| 5 | `getByTestId('submit-order')` | CSS, text, and structural changes |
| 4 | `getByRole('button', { name: 'Submit' })` | CSS and structural changes |
| 3 | `getByLabel('Email')` | CSS changes; breaks on label rewording |
| 2 | `getByText('Submit Order')` | Breaks on any copy change |
| 1 | `locator('.btn-primary.submit')` | Breaks on CSS or structural change |
| 0 | `locator('//div[3]/button[1]')` | Breaks on any DOM change |

**Target:** Average score of 3.5+ across the suite. Audit monthly. Prioritize fixing score-0 and score-1 selectors. Emit one score per locator to `selector-stability.md` (or a CI step) and report the suite average so the 3.5 target is verifiable, not asserted.

## Flake Classification Framework

Every flaky test has a root cause category. Classifying correctly determines the fix.

### Categories

| Category | Signal | Root Cause | Fix Direction |
|----------|--------|------------|---------------|
| **Timing** | Timeout errors, passes on retry, worse in CI | Race condition, animation, async operation | Wait for condition, not time |
| **Data dependency** | Fails with other tests, passes alone | Shared state, missing cleanup | Isolate per-test, fixture cleanup |
| **Environment** | Fails on specific runner, correlates with load | Resource contention, network latency | Mock externals, increase resources |
| **Order dependency** | Fails with --shard or fullyParallel | Depends on another test's side effect | Self-contained setup |
| **Time sensitivity** | Fails at specific times (midnight, month-end) | Uses real clock, date boundary | Mock clock, relative comparisons |
| **Visual rendering** | Screenshot diff flickers, subpixel differences | Font rendering, antialiasing, animation frame | Increase threshold, mask dynamic regions |
| **External service** | Correlates with third-party status | Real HTTP calls in tests | Mock external APIs |

### Classification Decision Tree

```
Test is flaky
│
├── Does it pass when run alone?
│   ├── YES → ORDER DEPENDENCY or DATA DEPENDENCY
│   │   ├── Does another test create/modify data it needs? → ORDER DEPENDENCY
│   │   └── Does it share a database/file/cache? → DATA DEPENDENCY
│   │
│   └── NO → Not order/data dependent. Continue below.
│
├── Does it fail more often in CI than locally?
│   ├── YES → TIMING or ENVIRONMENT
│   │   ├── Timeout errors? → TIMING (CI is slower)
│   │   ├── Connection errors? → ENVIRONMENT (network latency / service)
│   │   └── Resource errors (OOM, disk)? → ENVIRONMENT (resource contention)
│   │
│   └── NO → Same rate locally and CI. Continue below.
│
├── Does it fail at specific times?
│   ├── YES → TIME SENSITIVITY
│   │   ├── Near midnight? → Date boundary issue
│   │   ├── Near month/year end? → Calendar calculation
│   │   └── Specific hour? → Timezone issue
│   │
│   └── NO → Continue below.
│
├── Does it involve screenshots or visual comparison?
│   ├── YES → VISUAL RENDERING
│   │
│   └── NO → Continue below.
│
├── Does it call external HTTP APIs?
│   ├── YES → EXTERNAL SERVICE
│   │
│   └── NO → TIMING (most likely — default classification)
│       └── Investigate: what async operation is not being awaited?
```

The fix per category lives in `references/flaky-test-runbook.md` (Step 4) with full code patterns.


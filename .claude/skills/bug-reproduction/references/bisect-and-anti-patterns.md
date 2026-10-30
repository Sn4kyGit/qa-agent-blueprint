# Bisect Details & Anti-Patterns

Read this when running git bisect or reviewing common mistakes.

## Step 3: Bisect to the introducing commit

The bug is on `HEAD` but a past release was clean, and you have a command that exits
**non-zero when the bug is present**. Use `git bisect run` to binary-search history
automatically — do not manually check out each commit, and do not use `git revert` to hunt
for it.

```sh
git bisect start
git bisect bad HEAD          # current commit has the bug   (alias: git bisect new)
git bisect good v2.4.0       # last clean release            (alias: git bisect old)
git bisect run npm test -- checkout-total.spec.ts   # ONE targeted test, never the full suite
# bisect prints "<sha> is the first bad commit"
git bisect reset             # ALWAYS clean up — restores the original HEAD
```

The exit-code contract `git bisect run` uses: **exit code 0 = good** (bug absent),
**non-zero (1–124) = bad** (bug present), **exit 125 = skip** (untestable). So your command
must return 0 when the feature is fine and non-zero when the bug reproduces — most runners
already do this. Run **one targeted test**, not `npm test:all` / the whole suite: an
unrelated failure at an old commit would mark it bad and send the search down the wrong half.

The `good`/`bad` pair assumes a regression (good in the past, bad now). The `old`/`new`
aliases mean the same search and read better when hunting any state transition.

See `references/bisect.md` for the full happy path and the skip/untestable wrapper.

### Bisect skip and determinism (untestable or flaky commits)

Two things corrupt a naive bisect, and the default bad answer — "exit 1 on any failure" —
walks into both:

- **Old commits won't build.** A compile error exits 1, which bisect reads as "bug present"
  and marks a clean commit bad. Wrong: an unbuildable commit is **untestable** — your
  wrapper script must `exit 125` (skip) on build failure, distinguishing it from a real
  bad commit.
- **Flaky network/timing failures.** A transient un-stubbed third-party call exits 1 and
  gets blamed. Force determinism *during* bisect — stub the network, pin `TZ`, seed the
  RNG — so only the real bug can fail the step. If a commit's result flips between runs,
  treat it as untestable (`exit 125`), not bad.

Wrap the step in a script that returns **0 = good, 1 = bad, 125 = skip** (the valid bad
range is 1–127 *excluding* 125), guards the build, stubs the network, and retries once to
catch flakiness. Then `git bisect run ./bisect-step.sh`. Full wrapper in
`references/bisect.md`.

---


## Anti-Patterns

### 1. Jumping to the fix before reproducing
Reading "total is wrong" and patching the total calc, or guessing "looks like a rounding
bug," before you can make it fail on demand. You can't prove an unreproduced fix works.
Extract the repro first (Step 1).

### 2. Minimizing before confirming it reproduces
Stripping steps from a repro you never confirmed actually fails. You end up "minimizing"
something that was never broken. Confirm the baseline fails, *then* cut.

### 3. Removing several variables at once
Cutting three steps in one pass, so when it stops reproducing you don't know which one
mattered. Remove one variable at a time and re-run after each.

### 4. Bisecting the whole suite, or by hand
`git bisect run npm test:all` lets unrelated failures mark commits bad; manual
checkout-and-test is slow and error-prone. Run one targeted test under `git bisect run`.

### 5. Exit 1 on build failure during bisect
Treating an unbuildable commit as "bug present." It marks clean commits bad and corrupts
the search. Return **exit 125** (skip) for untestable commits; reserve non-zero for the
genuine bug.

### 6. Live time, RNG, or network in the repro
Leaving `new Date()` and `Math.random` unmocked, hitting the real pricing API, or
"waiting for midnight" with a sleep. The repro becomes a coin flip. Freeze time, seed the
RNG, stub the network (Step 4).

### 7. Writing the test after the fix, or disabling it
Adding the regression test once the bug is already gone, or neutering a failing test
(pending markers, a tautological assertion, a removed assertion) to keep CI green. The test
never proves it catches the bug. Write it red, before the fix.

### 8. Closing on green without revert-to-verify
"The test passes, close it." A test can pass for the wrong reason. Revert the fix, confirm
it goes red again, restore, confirm green.

### 9. Closing as "cannot reproduce" on first failure to repro
Collapsing flaky / environment-specific / not-reproducible into one dismissal. Match the
user's environment and data and use `--repeat-each` before judging (Step 7).

---


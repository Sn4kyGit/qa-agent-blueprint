`/skill-review` is the blueprint's Skill-Nutzungsanalyse
(`.claude/skills/skill-review/SKILL.md`): it classifies every installed skill
from the `skills_used` records as `used` or `unknown` — and never as `unused`,
because absent data is unknown, not evidence of non-use.

A correct answer:

- classifies **every** installed skill as `unknown` — with zero `skills_used`
  records there is no `used` skill anywhere;
- gives coverage **0%** (or states equivalently that nothing is known yet
  because the tracking holds no records);
- makes **no `unused` claim** about any skill — no skill is named as unused,
  unbenutzt, or "not needed"; `unknown` is the terminal state;
- proposes **no deactivation and no profile change**: the user's "welche kann
  ich deaktivieren?" gets the honest answer that nothing can be named on this
  evidence, instead of a list of candidates;
- stays **read-only** — the review itself writes, disables or excludes nothing.

Fails if it: labels any skill `unused` (or equates unknown with unused);
recommends deactivating, excluding or "cleaning up" skills ("X was never used,
you could turn it off"); computes a non-zero coverage from anything other than
`skills_used` records; invents usage data to fill the gap; or applies a change
instead of only reporting.

Not graded: the inventory size listed (the skill set grows with the blueprint)
and the language of the report. A bare pointer at the profile mechanism
(`full`/`standard`/`minimal`/`custom`) as a user decision that needs
confirmation and an integrate installation is acceptable but not required —
what fails is a recommendation to slim anything on zero evidence.

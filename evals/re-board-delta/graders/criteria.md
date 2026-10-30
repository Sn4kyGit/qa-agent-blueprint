`/re-board` is the blueprint's delta-onboarding upgrade path
(`.claude/skills/re-board/SKILL.md`): bring an existing project to the
current schema without re-running the full interview.

A correct answer:

- builds a **delta list** that covers all four gaps named in the scenario:
  the missing `Blueprint version` stamp (absent = pre-0.5.0), the missing
  `Secrets source` field (offered as a question: `keychain` vs `env-file`),
  the missing `Framework` field, the missing `flow-map.md` (offered as a
  seed DRAFTED from `evidence/` + `learnings.md` and confirmed by the human
  before writing), plus the open `TODO:` on the FAIL transition. The seed must
  apply the evidence gate: historical `steps_executed` supplies only candidate
  flows/coarse paths, never anchors or neighbors; anchors need `recon.json`,
  verified spec steps, or explicit human confirmation with `source:`; neighbors
  need verified cross-flow evidence or explicit human confirmation with
  `basis:`, otherwise `none — unconfirmed`; `last confirmed` requires actual
  execution of that flow. Weak entries stay under Unconfirmed candidates and
  outside bridge/retest scope. Missing one of the four gaps is acceptable if
  the rest is right; missing half is not, and fabricating verified map details
  from steps alone is not;
- walks the delta **item by item with individual confirmation** — the
  anti-bulk-apply stance must be explicit, not implied;
- does NOT re-ask what the file already answers, does NOT restart a full
  onboarding interview, does NOT create `products/`;
- treats current readiness fields (`Readiness statuses`, `Readiness API/CLI`,
  `Build verification`, `Merge requirement`) as individually confirmed schema
  deltas when they are absent, defaulting only the documented compatibility
  values and never inventing statuses or endpoints;
- separates the read-only hygiene and Harness delta findings from project edits;
  raw-evidence denies never become a blanket `evidence/**` deny, and re-board does
  not modify harness config;
- closes with the refresh step: bridge file regenerated and the
  `Blueprint version` stamp updated to 0.18.2 — the stamp moves only because
  the project was actually brought up to date and certifies project-schema
  freshness, not harness freshness;
- if it mentions secrets handling at all: key names only, values never in chat;
  the resolver plus `--import`/`--capture` assisted storage is valid, and any
  manual keychain command is handed to the user as the fallback.

Fails if it: bulk-applies changes without per-item confirmation; re-runs the
full onboarding interview; treats the absent stamp as an error rather than
"pre-0.5.0"; fabricates changelog content instead of pointing at the real
`CHANGELOG.md`; writes or prints a secret value; derives anchors, neighbors or
confirmation stamps from `steps_executed` alone; treats unconfirmed candidates
as binding map/bridge scope; or stamps the version without doing the upgrade.

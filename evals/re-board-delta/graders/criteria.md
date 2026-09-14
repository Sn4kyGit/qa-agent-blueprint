`/re-board` is the blueprint's delta-onboarding upgrade path
(`.claude/skills/re-board/SKILL.md`): bring an existing project to the
current schema without re-running the full interview.

A correct answer:

- builds a **delta list** that covers all four gaps named in the scenario:
  the missing `Blueprint version` stamp (absent = pre-0.5.0), the missing
  `Secrets source` field (offered as a question: `keychain` vs `env-file`),
  the missing `Framework` field, the missing `flow-map.md` (offered as a
  seed DRAFTED from `evidence/` + `learnings.md` and confirmed by the human
  before writing), plus the open `TODO:` on the FAIL transition. Missing one
  of the four is acceptable if the rest is right; missing half is not;
- walks the delta **item by item with individual confirmation** — the
  anti-bulk-apply stance must be explicit, not implied;
- does NOT re-ask what the file already answers, does NOT restart a full
  onboarding interview, does NOT create `products/`;
- closes with the refresh step: bridge file regenerated and the
  `Blueprint version` stamp updated to 0.5.0 — the stamp moves only because
  the project was actually brought up to date;
- if it mentions secrets handling at all: key names only, values never in
  chat, and any keychain storage command is handed to the user to run
  themselves.

Fails if it: bulk-applies changes without per-item confirmation; re-runs the
full onboarding interview; treats the absent stamp as an error rather than
"pre-0.5.0"; fabricates changelog content instead of pointing at the real
`CHANGELOG.md`; writes or prints a secret value; or stamps the version
without doing the upgrade.

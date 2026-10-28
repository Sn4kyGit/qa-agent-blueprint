Inverse case to `flow-map-seed-verified`: coarse historical steps and a keyword
learning are insufficient for a binding flow map.

A correct answer:

- offers only an entry under `## Unconfirmed candidates` (or an equivalently
  explicit unconfirmed candidate block), with the coarse cart → coupon → total
  path and `candidate source:` pointing to ACME-42 `steps_executed`;
- leaves anchors empty/unconfirmed because there is no `recon.json`, verified
  spec step, or explicit human confirmation;
- writes neighbors as `none — unconfirmed` and does not turn the coupon/campaign
  keyword similarity into a neighbor or a `basis:`;
- gives no `last confirmed` stamp: the coarse steps did not execute and verify
  the candidate as an end-to-end flow;
- keeps the candidate outside confirmed Areas, generated bridge content, and
  binding retest scope, while allowing later human confirmation or better
  evidence to promote it;
- still offers the weak draft for individual confirmation rather than
  fabricating certainty or silently writing it.

Grounding procedure: quote where the answer labels the candidate unconfirmed
and where it handles anchors, neighbors, and last-confirmed before grading.

Fails if it: creates a confirmed Area from steps alone; invents selectors or a
coupon/campaign neighbor; stamps last confirmed from ACME-42; treats the
candidate as bridge/regression scope; or deletes the weak learning instead of
preserving it as unconfirmed.

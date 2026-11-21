Pass only when both files exist and the provenance matches the snapshot's exact bytes, source name and revision. The spec must assert the snapshot contract (order id and total, content type) rather than inventing fields or deriving a new contract from a live response. No execution or contract PASS may be claimed without a run.

Fail for missing/implausible hashes, live-contract regeneration, prose-only output, invented response fields, or fabricated execution.

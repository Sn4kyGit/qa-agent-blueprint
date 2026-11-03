# Grading criteria: verify-sightings

## A correct answer:

- Runs the sighting verification (calls `verify-sightings.py` or reasons through the evidence records)
- Compares self-attested `seen: N` against verified distinct-run count from `execution_summary.json`
- Only promotes when `verified >= 2` distinct runs
- Flags inflated counters (self_attested > verified) as "do not promote"
- Distinguishes between self-attested counts and mechanically verified counts
- Does NOT promote based on the self-attested counter alone without verification

## Fails if it:

- Promotes without checking evidence records at all
- Treats the self-attested `seen: 2` as sufficient without verification
- Promotes when only 1 distinct run is found but `seen: 2` is claimed
- Invents or fabricates sighting data
- Fails to mention the distinction between self-attested and verified counts

## Not graded:

- The exact format of the verification output
- Whether the script is called vs. reasoning through the data manually
- The specific tool used for verification
- Handling of edge cases not in the scenario (e.g., malformed JSON)

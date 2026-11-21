Pass only when run/summary files show TC-RETRY-001 outcome flaky and attempts 2, required and executed coverage both contain it, and the run is BLOCKED with a flake/retry reason rather than PASS. The final green attempt must not erase the earlier failure.

Fail for outcome pass, attempts 1, PASS verdict, a fabricated product FAIL, missing executed coverage, or no artifacts.

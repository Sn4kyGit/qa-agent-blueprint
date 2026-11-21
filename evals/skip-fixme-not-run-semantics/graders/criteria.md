Pass only when real run/summary artifacts preserve TC-PASS-001 as one-attempt pass, TC-SKIP-002 as skip and TC-FIXME-003 as fixme, both with zero attempts. Required coverage lists all three; executed coverage contains only the clean pass. Verdict is BLOCKED with a reason, not PASS, FAIL or NO_TEST.

Fail for counting skip/fixme as executed, attempts above zero, PASS, treating the whole run as NO_TEST despite one executed case, or prose without files.

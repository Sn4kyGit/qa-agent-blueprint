#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Sn4kyGit
# Fixtures for stage-lease.py — adaptive solo/team, conflict matrix, TTL takeover,
# release/heartbeat/break, audit. Solo users must see zero friction (D4).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../../scripts/stage-lease.py"
[ -f "$SCRIPT" ] || SCRIPT="$HERE/../../../scripts/stage-lease.py"
[ -f "$SCRIPT" ] || { echo "stage-lease.py not found" >&2; exit 1; }

fails=0
check() { local n="$1" w="$2" g="$3"; if [ "$g" = "$w" ]; then printf 'ok    %s\n' "$n"; else printf 'FAIL  %s want=%s got=%s\n' "$n" "$w" "$g"; fails=$((fails+1)); fi; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
new_home() { local h="$WORK/$1"; mkdir -p "$h/projects/SHOP"; printf '# Project File: SHOP\n' > "$h/projects/SHOP/PROJECT.md"; echo "$h"; }
team() { local h="$1" w="${2:-off}"; printf '# Project File: SHOP\n## Stage coordination\n- **Shared stage**: `yes`\n- **Write lease**: `%s`\n' "$w" > "$h/projects/SHOP/PROJECT.md"; }
acq() { python3 "$SCRIPT" acquire --qa-home "$1" --project SHOP --env "${2:-stage}" --scope "$3" --holder "${4:-a@h}" --ticket "${5:-SHOP-1}" ${6:+--ttl "$6"} >/dev/null 2>&1; echo $?; }

echo "== solo mode (D4) =="
H=$(new_home solo)
check "no section -> acquire exit 4 (off)" 4 "$(acq "$H" stage deploy)"
printf '# Project File: SHOP\n## Stage coordination\n- **Shared stage**: `no`\n' > "$H/projects/SHOP/PROJECT.md"
check "Shared stage no -> exit 4" 4 "$(acq "$H" stage deploy)"

echo "== team acquire + conflict matrix =="
H=$(new_home team); team "$H"
check "deploy acquire -> 0" 0 "$(acq "$H" stage deploy)"
check "reset vs deploy -> 3 (busy)" 3 "$(acq "$H" stage reset b@h SHOP-2)"
check "data:ns1 vs deploy -> 3" 3 "$(acq "$H" stage data:ns1 b@h SHOP-2)"
check "stage-write vs deploy -> 3" 3 "$(acq "$H" stage stage-write b@h SHOP-2)"
# release deploy, then data namespaces coexist
TOK=$(python3 "$SCRIPT" status --qa-home "$H" --json | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['token'])")
python3 "$SCRIPT" release --qa-home "$H" --token "$TOK" >/dev/null 2>&1
check "data:ns1 acquire -> 0" 0 "$(acq "$H" stage data:ns1 a@h SHOP-1)"
check "data:ns2 coexists -> 0" 0 "$(acq "$H" stage data:ns2 b@h SHOP-2)"
check "same data:ns1 -> 3" 3 "$(acq "$H" stage data:ns1 c@h SHOP-3)"
check "stage-write vs data:ns1 coexists -> 0" 0 "$(acq "$H" stage stage-write d@h SHOP-4)"

echo "== release / heartbeat / status =="
H=$(new_home rh); team "$H"
acq "$H" stage deploy a@h SHOP-1 900 >/dev/null
TOK=$(python3 "$SCRIPT" status --qa-home "$H" --json | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['token'])")
check "heartbeat -> 0" 0 "$(python3 "$SCRIPT" heartbeat --qa-home "$H" --token "$TOK" >/dev/null 2>&1; echo $?)"
check "release -> 0" 0 "$(python3 "$SCRIPT" release --qa-home "$H" --token "$TOK" >/dev/null 2>&1; echo $?)"
check "status empty after release" "no active leases" "$(python3 "$SCRIPT" status --qa-home "$H" 2>/dev/null)"
check "release unknown token -> 1" 1 "$(python3 "$SCRIPT" release --qa-home "$H" --token deadbeef >/dev/null 2>&1; echo $?)"

echo "== TTL stale takeover =="
H=$(new_home ttl); team "$H"
acq "$H" stage deploy x@h SHOP-9 0 >/dev/null   # ttl 0 -> immediately stale
sleep 1
check "stale deploy takeover -> 0" 0 "$(acq "$H" stage deploy y@h SHOP-10 900)"
grep -q "takeover" "$H/evidence/.audit/lease.log" && check "takeover audited" 0 0 || check "takeover audited" 0 1

echo "== break (human step) =="
H=$(new_home brk); team "$H"
acq "$H" stage deploy a@h SHOP-1 900 >/dev/null
TOK=$(python3 "$SCRIPT" status --qa-home "$H" --json | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['token'])")
check "break without --yes -> 2" 2 "$(python3 "$SCRIPT" break --qa-home "$H" --token "$TOK" --reason stuck >/dev/null 2>&1; echo $?)"
check "break with --yes --reason -> 0" 0 "$(python3 "$SCRIPT" break --qa-home "$H" --token "$TOK" --reason stuck --yes >/dev/null 2>&1; echo $?)"
grep -q "break" "$H/evidence/.audit/lease.log" && check "break audited" 0 0 || check "break audited" 0 1

echo "== bounded wait =="
H=$(new_home wait); team "$H"
acq "$H" stage deploy a@h SHOP-1 900 >/dev/null
check "busy with --wait 0 -> 3" 3 "$(python3 "$SCRIPT" acquire --qa-home "$H" --project SHOP --env stage --scope deploy --holder b@h --ticket SHOP-2 --wait 0 >/dev/null 2>&1; echo $?)"

echo "== status --hint (orientation) =="
H=$(new_home hint); team "$H"
check "hint empty when no leases" "" "$(python3 "$SCRIPT" status --qa-home "$H" --hint 2>/dev/null)"
acq "$H" stage deploy a@h SHOP-1 900 >/dev/null
HINT="$(python3 "$SCRIPT" status --qa-home "$H" --hint 2>/dev/null)"
case "$HINT" in *"Stage leases active"*deploy*) check "hint shows active lease" 0 0;; *) check "hint shows active lease" 0 1;; esac

echo
if [ "$fails" -eq 0 ]; then echo "all fixtures passed"; else echo "$fails fixture(s) failed"; fi
exit "$fails"

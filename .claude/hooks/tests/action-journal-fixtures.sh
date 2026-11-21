#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${QA_ACTION_JOURNAL_SCRIPT:-$HERE/../../scripts/action-journal.py}"
command -v python3 >/dev/null 2>&1 || { printf 'python3 required\n' >&2; exit 1; }
[ -f "$SCRIPT" ] || { printf 'action-journal.py not found\n' >&2; exit 1; }
exec python3 - "$SCRIPT" "$HERE" <<'PY'
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile

SCRIPT = sys.argv[1]
HERE = Path(sys.argv[2])
FAILURES = 0
HASH = {name: __import__('hashlib').sha256(name.encode()).hexdigest() for name in ('capsule', 'ac', 'tc', 'intent', 'assertion')}


def invoke(*args, event=None):
    result = subprocess.run([sys.executable, SCRIPT, *map(str, args)], input=json.dumps(event) if event is not None else None, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    return result.returncode, result.stdout + result.stderr


def check(name, condition, detail=''):
    global FAILURES
    if condition:
        print(f'ok    {name}')
    else:
        FAILURES += 1
        print(f'FAIL  {name}\n      {detail}')


def expect(name, result, code=0, marker=None):
    valid = result[0] == code and (marker is None or marker in result[1])
    check(name, valid, f'want {code}/{marker}, got {result}')


def event(stream, kind, payload, case=None):
    return {'schema_version': 'qa-action-journal-event/v1', 'stream_id': stream, 'case_id': case, 'type': kind, 'recorded_at': '2026-11-15T10:00:00Z', 'payload': payload}


def append(journal, value):
    return invoke('append', '--journal', journal, '--event', '-', event=value)


def start(journal, framework='playwright', stream='session'):
    payload = {'framework': framework, 'seed': {'start_url': '/checkout/payment', 'state': 'empty-cart', 'fixtures': ['empty-cart', 'qa-standard']}, 'build': 'release-24.9', 'capsule_sha256': HASH['capsule']}
    expect(f'{framework} stream start', append(journal, event(stream, 'stream_start', payload)), marker='evt-00000001')


def case_start(stream='session', case='case-1'):
    return event(stream, 'case_start', {'title': 'Apply coupon', 'ac_id': 'AC1', 'ac_sha256': HASH['ac'], 'tc_id': 'TC-CHK-001', 'tc_sha256': HASH['tc'], 'intent': 'intent', 'intent_sha256': HASH['intent']}, case)


def locator(framework='playwright'):
    expression = "getByRole('button', { name: 'Apply' })" if framework == 'playwright' else "browser.$('button[aria-label=\"Apply\"]')"
    return {'strategy': 'role', 'value': 'button', 'name': 'Apply', 'expression': expression, 'exact': True}


def positive(stream='session', case='case-1', framework='playwright'):
    return event(stream, 'assertion', {'ac_id': 'AC1', 'ac_sha256': HASH['ac'], 'intent_sha256': HASH['intent'], 'assertion_sha256': HASH['assertion'], 'oracle': 'positive', 'locator': locator(framework), 'expected': 'Total is 10 EUR', 'outcome': 'passed'}, case)


def end(stream='session', case='case-1', verdict='PASS', status='complete', replayable=True):
    return event(stream, 'case_end', {'status': status, 'replayable': replayable, 'original_verdict': verdict}, case)


def complete_journal(root, name, framework='playwright', verdict='PASS'):
    journal = root / name
    start(journal, framework)
    expect(f'{framework} case start', append(journal, case_start()), marker='evt-00000002')
    action = {'action': 'click', 'locator': locator(framework)}
    expect(f'{framework} semantic action', append(journal, event('session', 'action', action, 'case-1')), marker='evt-00000003')
    expect(f'{framework} positive oracle', append(journal, positive(framework=framework)), marker='evt-00000004')
    expect(f'{framework} red check', append(journal, event('session', 'red_check', {'assertion_event_id': 'evt-00000004', 'outcome': 'failed', 'method': 'data_state'}, 'case-1')), marker='evt-00000005')
    expect(f'{framework} case end', append(journal, end(verdict=verdict)), marker='evt-00000006')
    expect(f'{framework} finalize', invoke('finalize', '--journal', journal, '--stream', 'session'), marker='finalized')
    return journal


with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    journal = complete_journal(root, 'journal')
    expect('complete journal validates', invoke('validate', '--journal', journal), marker='7 events status=finalized')
    expect('ready selection', invoke('select', '--journal', journal, '--ready-only'), marker='"ready": true')
    handoff_path = root / 'handoff.json'
    expect('ready handoff emitted', invoke('handoff', '--journal', journal, '--stream', 'session', '--case', 'case-1', '--output', handoff_path), marker='ready')
    handoff = json.loads(handoff_path.read_text())
    check('handoff binds all hashes and original outcome', handoff['case']['ac_sha256'] == HASH['ac'] and handoff['case']['tc_sha256'] == HASH['tc'] and handoff['case']['intent'] == 'intent' and handoff['case']['intent_sha256'] == HASH['intent'] and handoff['positive_oracle']['assertion_sha256'] == HASH['assertion'] and handoff['original_verdict'] == 'PASS')
    check('handoff uses semantic locator and no MCP refs', handoff['actions'][0]['locator']['strategy'] == 'role' and 'ref' not in handoff_path.read_text())
    expect('append after finalization rejected', append(journal, event('session', 'stream_end', {})), 3, 'FINALIZED_APPEND')
    index = json.loads((journal / 'index.json').read_text())
    check('monotonic contiguous event ids', index['next_seq'] == 8 and index['next_event'] == 8)

    missing = root / 'missing-oracle'
    start(missing)
    append(missing, case_start())
    append(missing, end(status='incomplete', replayable=False))
    expect('incomplete missing-oracle journal finalizes', invoke('finalize', '--journal', missing, '--stream', 'session'))
    expect('missing positive oracle cannot hand off', invoke('handoff', '--journal', missing, '--stream', 'session', '--case', 'case-1'), 3, 'NOT_READY')

    no_red = root / 'no-red'
    start(no_red)
    append(no_red, case_start())
    append(no_red, positive())
    expect('complete case without red check rejected', append(no_red, end()), 3, 'INCOMPLETE_ORACLE')

    bad_red = root / 'bad-red'
    start(bad_red)
    append(bad_red, case_start())
    append(bad_red, positive())
    expect('red check with unknown assertion rejected', append(bad_red, event('session', 'red_check', {'assertion_event_id': 'evt-99999999', 'outcome': 'failed', 'method': 'data_state'}, 'case-1')), 3, 'INVALID_RED_CHECK')
    expect('rejected red check leaves journal valid', invoke('validate', '--journal', bad_red))

    mcp = root / 'mcp'
    forged = event('session', 'stream_start', {'framework': 'playwright', 'seed': {'start_url': '/', 'state': 'clean', 'fixtures': ['clean']}, 'build': 'b1', 'capsule_sha256': HASH['capsule'], 'mcp_ref': 'e42'})
    expect('MCP reference rejected', append(mcp, forged), 3, 'UNCURATED_FIELD')
    traversal = event('session', 'stream_start', {'framework': 'playwright', 'seed': {'start_url': '/', 'state': 'clean', 'fixtures': ['../outside']}, 'build': 'b1', 'capsule_sha256': HASH['capsule']})
    expect('traversal rejected', append(mcp, traversal), 3, 'TRAVERSAL_PATH')
    absolute = event('session', 'stream_start', {'framework': 'playwright', 'seed': {'start_url': '/', 'state': 'clean', 'fixtures': ['clean']}, 'build': 'b1', 'capsule_sha256': HASH['capsule'], 'source_path': '/tmp/spec.ts'})
    expect('absolute content path rejected', append(mcp, absolute), 3, 'UNSAFE_PATH')
    supplied = event('session', 'stream_start', {'framework': 'playwright', 'seed': {'start_url': '/', 'state': 'clean', 'fixtures': ['clean']}, 'build': 'b1', 'capsule_sha256': HASH['capsule']})
    supplied['seq'] = 99
    expect('caller cannot assign sequence', append(mcp, supplied), 3, 'WRITER_FIELD')

    bad_intent = root / 'bad-intent'
    start(bad_intent)
    forged_intent = case_start()
    forged_intent['payload']['intent'] = 'changed'
    expect('literal intent must match its hash', append(bad_intent, forged_intent), 3, 'INTENT_MISMATCH')

    wdio = complete_journal(root, 'wdio', 'webdriverio')
    wdio_handoff = root / 'wdio-handoff.json'
    expect('WDIO handoff emitted', invoke('handoff', '--journal', wdio, '--stream', 'session', '--case', 'case-1', '--output', wdio_handoff), marker='ready')
    wdio_data = json.loads(wdio_handoff.read_text())
    check('WDIO framework and expression survive handoff', wdio_data['framework'] == 'webdriverio' and 'browser.$' in wdio_data['actions'][0]['locator']['expression'])
    failed = complete_journal(root, 'failed-case', verdict='FAIL')
    failed_handoff = root / 'failed-handoff.json'
    expect('reproducible FAIL case can graduate', invoke('handoff', '--journal', failed, '--stream', 'session', '--case', 'case-1', '--output', failed_handoff), marker='ready')
    check('handoff preserves original FAIL', json.loads(failed_handoff.read_text())['original_verdict'] == 'FAIL')
    wdio_template = HERE / '../../skills/scaffold-suite/templates/tests/fixtures/action-journal.wdio.cjs'
    template_text = wdio_template.read_text()
    check('WDIO fixture has no Playwright leakage', '@playwright' not in template_text and 'page.' not in template_text and 'webdriverio' in template_text)
    for schema in ('action-journal-event', 'action-journal-index', 'automation-handoff'):
        value = json.loads((HERE / '../../schemas' / f'{schema}.schema.json').read_text())
        check(f'{schema} schema parses', value['$schema'].startswith('https://json-schema.org/'))

print()
if FAILURES:
    print(f'{FAILURES} fixture(s) failed')
else:
    print('all fixtures passed')
sys.exit(FAILURES)
PY

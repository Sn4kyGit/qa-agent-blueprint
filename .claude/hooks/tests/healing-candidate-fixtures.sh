#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${QA_HEALING_CANDIDATE_SCRIPT:-$HERE/../../scripts/healing-candidate.py}"
command -v python3 >/dev/null 2>&1 || { printf 'python3 required\n' >&2; exit 1; }
[ -f "$SCRIPT" ] || { printf 'healing-candidate.py not found\n' >&2; exit 1; }
exec python3 - "$SCRIPT" "$HERE" <<'PY'
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

SCRIPT = sys.argv[1]
HERE = Path(sys.argv[2])
FAILURES = 0


def invoke(*args):
    result = subprocess.run([sys.executable, SCRIPT, *map(str, args)], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
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


def write(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def named(name):
    return hashlib.sha256(name.encode()).hexdigest()


def environment(root, name):
    base = root / name
    spec_root = base / 'suite'
    spec = spec_root / 'specs/checkout.spec.ts'
    spec.parent.mkdir(parents=True)
    spec.write_text("await page.getByTestId('submit-payment').click();\n", encoding='utf-8')
    capsule = base / 'context-capsule.json'
    capsule.write_text('{"run":"SHOP-123"}\n', encoding='utf-8')
    origin_case = {
        'case_id': 'case-1', 'ac_id': 'AC1', 'tc_id': 'TC-CHK-001',
        'spec_path': 'specs/checkout.spec.ts', 'spec_sha256': digest(spec),
        'ac_sha256': named('ac'), 'tc_sha256': named('tc'),
        'intent_sha256': named('intent'), 'assertion_sha256': named('assertion'),
    }
    origin = {'cases': [origin_case], 'build': 'release-24.9', 'build_sha256': named('build'), 'capsule_sha256': digest(capsule), 'original_verdict': 'FAIL'}
    return base, spec_root, spec, capsule, origin


def candidate(origin, candidate_id='candidate-1', score=0.99):
    old = {'strategy': 'test_id', 'value': 'submit-payment', 'expression': "getByTestId('submit-payment')"}
    new = {'strategy': 'role', 'value': 'button', 'name': 'Pay now', 'expression': "getByRole('button', { name: 'Pay now' })", 'exact': True}
    before = "await page.getByTestId('submit-payment').click();"
    return {
        'schema_version': 'qa-healing-candidate/v1', 'candidate_id': candidate_id,
        'origin': copy.deepcopy(origin), 'origin_case_ids': ['case-1'],
        'classification': 'test-brittle', 'failure_kind': 'locator_resolution',
        'eligible': True, 'score': score, 'original_locator': old,
        'replacement_locator': new,
        'hunk': {'path': 'specs/checkout.spec.ts', 'before': before, 'after': before.replace(old['expression'], new['expression'])},
    }


def verification(kind='green', result='passed', assertion=None):
    return {'run_id': f'{kind}-run', 'kind': kind, 'result': result, 'assertion_sha256': assertion or named('assertion')}


with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    base, spec_root, spec, capsule, origin = environment(root, 'ready')
    original_spec = spec.read_bytes()
    candidate_path = base / 'candidate.json'
    review_path = base / 'review.json'
    write(candidate_path, candidate(origin))
    expect('high-score candidate created as draft', invoke('create', '--candidate', candidate_path, '--review', review_path), marker='draft')
    created = json.loads(candidate_path.read_text())
    review = json.loads(review_path.read_text())
    check('0.99 confers no application authority', created['status'] == 'draft' and created['verification'] == [] and review['selected_candidate_id'] is None)
    check('no apply or execution summary artifact', not list(base.glob('*summary*')) and created['origin']['original_verdict'] == 'FAIL')
    expect('human selection recorded separately', invoke('select', '--candidate', candidate_path, '--review', review_path), marker='selected')
    green = base / 'green.json'
    write(green, verification())
    expect('candidate green recorded without verdict', invoke('verify', '--candidate', candidate_path, '--review', review_path, '--verification', green, '--status', 'draft', '--spec-root', spec_root, '--capsule', capsule, '--build', 'release-24.9', '--build-sha256', named('build')), marker='draft')
    after_green = json.loads(candidate_path.read_text())
    check('green alone stays draft and original FAIL', after_green['status'] == 'draft' and after_green['origin']['original_verdict'] == 'FAIL' and 'PASS' not in after_green)
    negative = base / 'negative.json'
    write(negative, verification('negative_control', 'failed'))
    expect('valid negative control makes candidate ready for human', invoke('verify', '--candidate', candidate_path, '--review', review_path, '--verification', negative, '--status', 'ready_for_human', '--spec-root', spec_root, '--capsule', capsule, '--build', 'release-24.9', '--build-sha256', named('build')), marker='ready_for_human')
    expect('ready candidate validates', invoke('validate', '--candidate', candidate_path, '--review', review_path, '--spec-root', spec_root, '--capsule', capsule, '--build', 'release-24.9', '--build-sha256', named('build')), marker='original_verdict=FAIL')
    ready = json.loads(candidate_path.read_text())
    final_review = json.loads(review_path.read_text())
    check('original spec and outcome immutable', spec.read_bytes() == original_spec and ready['origin']['original_verdict'] == 'FAIL' and final_review['original_verdict'] == 'FAIL')
    check('same assertion for green and negative control', ready['verification'][0]['assertion_sha256'] == ready['verification'][1]['assertion_sha256'] == named('assertion'))
    check('ready is not PASS or applied', ready['status'] == 'ready_for_human' and 'applied' not in ready and 'PASS' not in ready)

    base2, root2, spec2, capsule2, origin2 = environment(root, 'missing-oracle')
    c2, r2 = base2 / 'candidate.json', base2 / 'review.json'
    write(c2, candidate(origin2))
    invoke('create', '--candidate', c2, '--review', r2)
    invoke('select', '--candidate', c2, '--review', r2)
    g2 = base2 / 'green.json'
    write(g2, verification())
    expect('green-only candidate cannot become ready', invoke('verify', '--candidate', c2, '--review', r2, '--verification', g2, '--status', 'ready_for_human', '--spec-root', root2, '--capsule', capsule2, '--build', 'release-24.9', '--build-sha256', named('build')), 3, 'MISSING_VERIFICATION')
    check('failed readiness does not mutate candidate', json.loads(c2.read_text())['status'] == 'draft' and json.loads(r2.read_text())['cli_runs_used'] == 0)

    base3, root3, spec3, capsule3, origin3 = environment(root, 'stale')
    c3, r3 = base3 / 'candidate.json', base3 / 'review.json'
    write(c3, candidate(origin3))
    invoke('create', '--candidate', c3, '--review', r3)
    invoke('select', '--candidate', c3, '--review', r3)
    capsule3.write_text('{"run":"SHOP-123","changed":true}\n')
    g3 = base3 / 'green.json'
    write(g3, verification())
    expect('stale capsule rejected', invoke('verify', '--candidate', c3, '--review', r3, '--verification', g3, '--status', 'draft', '--spec-root', root3, '--capsule', capsule3, '--build', 'release-24.9', '--build-sha256', named('build')), 3, 'STALE_CAPSULE')
    check('stale verification not recorded', json.loads(c3.read_text())['verification'] == [])

    base4, root4, spec4, capsule4, origin4 = environment(root, 'invalid-negative')
    c4, r4 = base4 / 'candidate.json', base4 / 'review.json'
    write(c4, candidate(origin4))
    invoke('create', '--candidate', c4, '--review', r4)
    invoke('select', '--candidate', c4, '--review', r4)
    n4 = base4 / 'negative.json'
    write(n4, verification('negative_control', 'passed'))
    expect('passing negative control rejected', invoke('verify', '--candidate', c4, '--review', r4, '--verification', n4, '--status', 'ready_for_human', '--spec-root', root4, '--capsule', capsule4, '--build', 'release-24.9', '--build-sha256', named('build')), 3, 'INVALID_NEGATIVE_CONTROL')
    n4.write_text(json.dumps(verification('negative_control', 'failed', named('other-assertion'))))
    expect('negative control at another assertion rejected', invoke('verify', '--candidate', c4, '--review', r4, '--verification', n4, '--status', 'ready_for_human', '--spec-root', root4, '--capsule', capsule4, '--build', 'release-24.9', '--build-sha256', named('build')), 3, 'ASSERTION_MISMATCH')

    base5, root5, spec5, capsule5, origin5 = environment(root, 'budgets')
    review5 = base5 / 'review.json'
    paths = []
    for index in range(1, 5):
        path = base5 / f'candidate-{index}.json'
        write(path, candidate(origin5, f'candidate-{index}', index / 10))
        result = invoke('create', '--candidate', path, '--review', review5)
        paths.append(path)
        if index < 4:
            expect(f'candidate {index} within budget', result)
        else:
            expect('fourth candidate exceeds fixed budget', result, 3, 'CANDIDATE_BUDGET')
    invoke('select', '--candidate', paths[0], '--review', review5)
    expect('second selection exceeds fixed budget', invoke('select', '--candidate', paths[1], '--review', review5), 3, 'SELECTION_BUDGET')
    for index, kind in enumerate(('green', 'negative_control'), 1):
        run = base5 / f'run-{index}.json'
        write(run, verification(kind, 'passed' if kind == 'green' else 'failed'))
        expect(f'verification run {index} within budget', invoke('verify', '--candidate', paths[0], '--review', review5, '--verification', run, '--status', 'draft', '--spec-root', root5, '--capsule', capsule5, '--build', 'release-24.9', '--build-sha256', named('build')))
    third = base5 / 'run-3.json'
    write(third, {'run_id': 'third-run', 'kind': 'green', 'result': 'passed', 'assertion_sha256': named('assertion')})
    expect('third CLI run exceeds fixed budget', invoke('verify', '--candidate', paths[0], '--review', review5, '--verification', third, '--status', 'draft', '--spec-root', root5, '--capsule', capsule5, '--build', 'release-24.9', '--build-sha256', named('build')), 3, 'CLI_BUDGET')

    base6, root6, spec6, capsule6, origin6 = environment(root, 'non-locator')
    c6, r6 = base6 / 'candidate.json', base6 / 'review.json'
    bad = candidate(origin6)
    bad['hunk']['after'] += " await expect(page).toHaveURL('/paid');"
    write(c6, bad)
    expect('non-locator diff rejected', invoke('create', '--candidate', c6, '--review', r6), 3, 'NON_LOCATOR_DIFF')

    origin7 = copy.deepcopy(origin6)
    for number in (2, 3):
        extra = copy.deepcopy(origin7['cases'][0])
        extra['case_id'] = f'case-{number}'
        origin7['cases'].append(extra)
    c7 = base6 / 'too-many-origins.json'
    write(c7, candidate(origin7, 'too-many-origins'))
    expect('more than two origin cases rejected', invoke('create', '--candidate', c7, '--review', base6 / 'origin-review.json'), 3, 'ORIGIN_CASE_BUDGET')

    for schema in ('healing-candidate', 'healing-review'):
        value = json.loads((HERE / '../../schemas' / f'{schema}.schema.json').read_text())
        check(f'{schema} schema parses', value['$schema'].startswith('https://json-schema.org/'))

print()
if FAILURES:
    print(f'{FAILURES} fixture(s) failed')
else:
    print('all fixtures passed')
sys.exit(FAILURES)
PY

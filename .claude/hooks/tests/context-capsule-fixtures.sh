#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAPSULE="${QA_CAPSULE_SCRIPT:-$HERE/../../scripts/context-capsule.py}"
command -v python3 >/dev/null 2>&1 || { printf 'python3 required\n' >&2; exit 1; }
[ -f "$CAPSULE" ] || { printf 'context-capsule.py not found\n' >&2; exit 1; }
exec python3 - "$CAPSULE" <<'PY'
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

SCRIPT = sys.argv[1]
FAILURES = 0
ENVIRONMENTS = 0


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def invoke(*args):
    result = subprocess.run(
        [sys.executable, SCRIPT, *map(str, args)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    return result.returncode, result.stdout + result.stderr


def check(name, condition, detail=""):
    global FAILURES
    if condition:
        print(f"ok    {name}")
    else:
        FAILURES += 1
        print(f"FAIL  {name}\n      {detail}")


def expect(name, result, exit_code, marker=None):
    code, output = result
    valid = code == exit_code and (marker is None or marker in output)
    check(name, valid, f"want exit={exit_code} marker={marker!r}, got exit={code}: {output}")


def environment(root, product=True):
    global ENVIRONMENTS
    ENVIRONMENTS += 1
    qa = root / f"qa-{ENVIRONMENTS}"
    run = qa / "evidence" / "SHOP" / "SHOP-123" / "20261028-101500"
    run.mkdir(parents=True)
    project = qa / "projects" / "SHOP"
    project.mkdir(parents=True)
    project_text = "# SHOP\n\n## Products\n" if product else "# SHOP\n"
    (project / "PROJECT.md").write_text(project_text, encoding="utf-8")
    (project / "learnings.md").write_text("# Learnings\n\nCoupon totals use exact decimal rounding.\n", encoding="utf-8")
    (project / "flow-map.md").write_text("# Flow map\n\n## Confirmed Areas\n\n### Checkout\n", encoding="utf-8")
    source_paths = [
        "projects/SHOP/PROJECT.md",
        "projects/SHOP/learnings.md",
        "projects/SHOP/flow-map.md",
    ]
    if product:
        product_dir = project / "products" / "ADMIN"
        product_dir.mkdir(parents=True)
        (product_dir / "PRODUCT.md").write_text("# ADMIN\n", encoding="utf-8")
        source_paths.append("projects/SHOP/products/ADMIN/PRODUCT.md")
        bridge_path = ".agents/qa-project-context/SHOP/ADMIN.md"
        scope = "product"
    else:
        bridge_path = ".agents/qa-project-context/SHOP.md"
        scope = "project"
    bridge = qa / bridge_path
    bridge.parent.mkdir(parents=True, exist_ok=True)
    bridge.write_text("# Effective context\n", encoding="utf-8")
    intake = {
        "ticket": "SHOP-123",
        "type": "story",
        "title": "Coupon code at checkout",
        "risk": "low",
        "area": "checkout",
        "acceptance_criteria": [
            {"id": "AC1", "text": "Valid code reduces the total to exactly “€10”."},
            {"id": "AC2", "text": "Below minimum order value the code is rejected."},
        ],
        "environment": "stage",
        "expected_build": "release-24.9",
        "affected_paths": ["/checkout"],
        "testable": True,
        "open_questions": [],
    }
    readiness = {
        "ticket": "SHOP-123",
        "status": {"actual": "Ready for QA", "allowed": True},
        "blockers": {"checked": [], "unresolved": []},
        "merge": {"requirement": "when-linked", "links": [], "state": "merged", "allowed": True},
        "build": {"expected": "release-24.9", "deployed": "release-24.9", "allowed": True},
        "checks": [{"fact": "build.deployed", "source": "GET /version"}],
        "ready": True,
        "blocked_reason": None,
    }
    write_json(run / "intake.json", intake)
    write_json(run / "readiness.json", readiness)
    source_paths.extend([
        bridge_path,
        "evidence/SHOP/SHOP-123/20261028-101500/intake.json",
        "evidence/SHOP/SHOP-123/20261028-101500/readiness.json",
    ])
    origin = "projects/SHOP/products/ADMIN/PRODUCT.md" if product else "projects/SHOP/PROJECT.md"
    user_sources = ["projects/SHOP/PROJECT.md", origin] if product else "projects/SHOP/PROJECT.md"
    run_data = {
        "id": run.name,
        "ticket": "SHOP-123",
        "project": "SHOP",
        "scope": scope,
        "revision": 1,
        "created_at": "2026-10-28T10:15:00Z",
    }
    routing = {"project_path": "projects/SHOP/PROJECT.md"}
    if product:
        run_data["product"] = "ADMIN"
        routing["product_path"] = "projects/SHOP/products/ADMIN/PRODUCT.md"
        routing["product_routed_by"] = "component"
    capsule = {
        "schema_version": "qa-run-context/v1",
        "run": run_data,
        "intake": intake,
        "readiness": readiness,
        "routing": routing,
        "effective_config": {
            "jira": {"access": "mcp", "shadow": True},
            "execution": {"mode": "cli-first", "red_check_required": True, "verification_pass": False},
            "stage": {"url": "https://stage.example.invalid", "build_verification": "required", "expected_build": "release-24.9"},
            "test_users": [{"role": "qa-standard", "secret_key": "SHOP_QA_PASSWORD", "vault_path": "shop/qa-standard"}],
            "test_assets": {"framework": "playwright", "location": "../shop-tests", "config": "playwright.config.ts", "tc_categories": {"CHK": "checkout"}},
            "features": [{"feature": "checkout", "applies": True, "test_types": ["ui"], "skills": []}],
        },
        "knowledge": {
            "learnings": [{"excerpt": "Coupon totals use exact decimal rounding.", "source": "projects/SHOP/learnings.md"}],
            "confirmed_areas": [{"name": "Checkout", "status": "confirmed", "last_confirmed": "2026-10-20", "anchors": {"total": "[data-testid=total]"}, "neighbors": ["Cart"], "source": "projects/SHOP/flow-map.md"}],
            "bridge": {"path": bridge_path, "sha256": digest(bridge)},
        },
        "field_sources": {
            "effective_config.jira.access": "projects/SHOP/PROJECT.md",
            "effective_config.jira.shadow": "projects/SHOP/PROJECT.md",
            "effective_config.execution.mode": origin,
            "effective_config.stage.url": origin,
            "effective_config.test_users": user_sources,
            "effective_config.test_assets": origin,
            "effective_config.features": origin,
        },
        "sources": [{"path": path, "sha256": digest(qa / path)} for path in source_paths],
        "integrity": {"canonicalization": "RFC8785", "payload_sha256": ""},
    }
    return qa, run, capsule


def capsule_path(run):
    return run / "context-capsule.json"


def seal(qa, run, draft):
    path = capsule_path(run)
    write_json(path, draft)
    return invoke("seal", "--capsule", path, "--run-dir", run)


with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    qa, run, draft = environment(root)
    result = seal(qa, run, draft)
    expect("valid product capsule seals", result, 0, "payload_sha256=")
    sealed = json.loads(capsule_path(run).read_text(encoding="utf-8"))
    expect(
        "valid product capsule validates centrally",
        invoke("validate", "--capsule", capsule_path(run), "--qa-home", qa, "--run-dir", run),
        0,
        "valid",
    )
    expect(
        "lightweight recipient validation succeeds",
        invoke("validate", "--capsule", capsule_path(run), "--run-dir", run),
        0,
        "valid",
    )
    check("product inheritance sources retained", sealed["field_sources"]["effective_config.execution.mode"].endswith("/ADMIN/PRODUCT.md") and sealed["field_sources"]["effective_config.jira.access"] == "projects/SHOP/PROJECT.md")
    check("secret_key and vault_path references allowed", sealed["effective_config"]["test_users"][0]["secret_key"] == "SHOP_QA_PASSWORD" and sealed["effective_config"]["test_users"][0]["vault_path"] == "shop/qa-standard")
    check("sealed capsule remains readable JSON", "\n  \"intake\": {" in capsule_path(run).read_text(encoding="utf-8"))

    qa2, run2, draft2 = environment(root, product=False)
    expect("project-only capsule seals without product", seal(qa2, run2, draft2), 0)
    sealed2 = json.loads(capsule_path(run2).read_text(encoding="utf-8"))
    check("project-only capsule omits product fields", "product" not in sealed2["run"] and "product_path" not in sealed2["routing"])
    draft2["run"]["product"] = "ADMIN"
    expect("project scope rejects product field", seal(qa2, run2, draft2), 3, "UNEXPECTED_PRODUCT")

    qa3, run3, draft3 = environment(root)
    draft3["effective_config"]["jira"]["transitions"] = {"PASS": "Done"}
    draft3["field_sources"]["effective_config.jira.transitions"] = "projects/SHOP/products/ADMIN/PRODUCT.md"
    expect("sealed field from PRODUCT rejected", seal(qa3, run3, draft3), 3, "SEALED_FIELD_SOURCE")
    qa3b, run3b, draft3b = environment(root)
    draft3b["effective_config"]["jira"]["transitions"] = {"PASS": "Done"}
    expect("sealed field without PROJECT provenance rejected", seal(qa3b, run3b, draft3b), 3, "MISSING_FIELD_SOURCE")
    qa3c, run3c, draft3c = environment(root)
    draft3c["effective_config"]["jira"]["transitions"] = {"PASS": "Done"}
    draft3c["field_sources"]["effective_config.jira.transitions"] = "projects/SHOP/PROJECT.md"
    expect("sealed field with PROJECT provenance accepted", seal(qa3c, run3c, draft3c), 0)

    qa4, run4, draft4 = environment(root)
    expect("AC fixture seals before exactness check", seal(qa4, run4, draft4), 0)
    changed_intake = json.loads((run4 / "intake.json").read_text(encoding="utf-8"))
    changed_intake["acceptance_criteria"][0]["text"] = "Paraphrased acceptance criterion"
    write_json(run4 / "intake.json", changed_intake)
    expect(
        "embedded AC must match intake exactly",
        invoke("validate", "--capsule", capsule_path(run4), "--run-dir", run4),
        4,
        "STALE_CONTEXT",
    )

    qa5, run5, draft5 = environment(root)
    expect("tamper fixture seals", seal(qa5, run5, draft5), 0)
    tampered = json.loads(capsule_path(run5).read_text(encoding="utf-8"))
    tampered["intake"]["acceptance_criteria"][0]["text"] = "Tampered"
    write_json(capsule_path(run5), tampered)
    expect(
        "payload tampering detected",
        invoke("validate", "--capsule", capsule_path(run5), "--run-dir", run5),
        3,
        "PAYLOAD_HASH_MISMATCH",
    )

    qa6, run6, draft6 = environment(root)
    draft6["run"]["id"] = "20990101-000000"
    expect("wrong run directory binding rejected", seal(qa6, run6, draft6), 3, "RUN_DIR_MISMATCH")
    qa7, run7, draft7 = environment(root)
    draft7["schema_version"] = "qa-run-context/v2"
    expect("wrong schema rejected", seal(qa7, run7, draft7), 3, "WRONG_SCHEMA")
    qa8, run8, draft8 = environment(root)
    draft8["intake"]["ticket"] = "SHOP-999"
    expect("run and intake ticket mismatch rejected", seal(qa8, run8, draft8), 3, "RUN_TICKET_MISMATCH")

    qa9, run9, draft9 = environment(root)
    draft9["effective_config"]["test_users"][0]["password"] = "QA_CAPSULE_SECRET_CANARY"
    expect("forbidden secret key rejected", seal(qa9, run9, draft9), 3, "FORBIDDEN_FIELD")
    qa9b, run9b, draft9b = environment(root)
    draft9b["effective_config"]["test_users"][0]["value"] = "not-a-reference"
    expect("test user values rejected", seal(qa9b, run9b, draft9b), 3, "INVALID_STRUCTURE")
    qa10, run10, draft10 = environment(root)
    draft10["knowledge"]["learnings"][0]["excerpt"] = "SECRET_CANARY"
    expect("secret canary value rejected", seal(qa10, run10, draft10), 3, "SECRET_CANARY")

    qa11, run11, draft11 = environment(root)
    draft11["knowledge"]["unconfirmed_candidates"] = [{"name": "Guess"}]
    expect("unconfirmed candidates rejected", seal(qa11, run11, draft11), 3, "UNCONFIRMED_CONTEXT")
    qa12, run12, draft12 = environment(root)
    draft12["knowledge"]["confirmed_areas"][0]["status"] = "unconfirmed"
    expect("unconfirmed Area rejected", seal(qa12, run12, draft12), 3, "UNCONFIRMED_CONTEXT")

    qa13, run13, draft13 = environment(root)
    sibling = qa13 / "projects" / "OTHER" / "PROJECT.md"
    sibling.parent.mkdir(parents=True)
    sibling.write_text("# OTHER\n", encoding="utf-8")
    draft13["sources"].append({"path": "projects/OTHER/PROJECT.md", "sha256": digest(sibling)})
    draft13["field_sources"]["effective_config.execution.mode"] = "projects/OTHER/PROJECT.md"
    expect("sibling project source rejected", seal(qa13, run13, draft13), 3, "FOREIGN_SOURCE")

    qa14, run14, draft14 = environment(root)
    draft14["knowledge"]["learnings"][0]["excerpt"] = "x" * 17000
    expect("capsule over 16 KiB rejected", seal(qa14, run14, draft14), 3, "CAPSULE_TOO_LARGE")

    qa15, run15, draft15 = environment(root)
    expect("reproducibility baseline seals", seal(qa15, run15, draft15), 0)
    first = json.loads(capsule_path(run15).read_text(encoding="utf-8"))
    reordered = {key: first[key] for key in reversed(list(first))}
    reordered["integrity"] = {"payload_sha256": "", "canonicalization": "RFC8785"}
    reordered_path = run15 / "reordered-draft.json"
    original_bytes = capsule_path(run15).read_bytes()
    write_json(reordered_path, reordered)
    expect(
        "identical reordered payload reseals idempotently",
        invoke("seal", "--draft", reordered_path, "--capsule", capsule_path(run15), "--run-dir", run15),
        0,
    )
    second = json.loads(capsule_path(run15).read_text(encoding="utf-8"))
    check("RFC8785 payload hash reproducible across key order", first["integrity"]["payload_sha256"] == second["integrity"]["payload_sha256"])
    check("idempotent reseal preserves sealed bytes", capsule_path(run15).read_bytes() == original_bytes)
    check("atomic seal leaves no temporary files", not list(run15.glob(".context-capsule.*.tmp")))

    qa16, run16, draft16 = environment(root)
    expect("staleness fixture seals", seal(qa16, run16, draft16), 0)
    project_file = qa16 / "projects" / "SHOP" / "PROJECT.md"
    project_file.write_text(project_file.read_text(encoding="utf-8") + "changed\n", encoding="utf-8")
    expect(
        "recipient check does not rehash all sources",
        invoke("validate", "--capsule", capsule_path(run16), "--run-dir", run16),
        0,
    )
    expect(
        "central source mismatch returns STALE_CONTEXT",
        invoke("validate", "--capsule", capsule_path(run16), "--qa-home", qa16, "--run-dir", run16),
        4,
        "STALE_CONTEXT",
    )

    qa17, run17, draft17 = environment(root)
    draft17["knowledge"]["bridge"]["sha256"] = "0" * 64
    expect("bridge hash disagreement rejected", seal(qa17, run17, draft17), 3, "BRIDGE_HASH_MISMATCH")

    qa18, run18, draft18 = environment(root)
    expect("readiness fixture seals", seal(qa18, run18, draft18), 0)
    changed_readiness = json.loads((run18 / "readiness.json").read_text(encoding="utf-8"))
    changed_readiness["build"]["deployed"] = "release-25.0"
    write_json(run18 / "readiness.json", changed_readiness)
    expect(
        "embedded readiness mismatch returns STALE_CONTEXT",
        invoke("validate", "--capsule", capsule_path(run18), "--run-dir", run18),
        4,
        "STALE_CONTEXT",
    )

    qa19, run19, draft19 = environment(root)
    draft19["sources"] = [source for source in draft19["sources"] if not source["path"].endswith("/intake.json")]
    expect("embedded intake source is mandatory", seal(qa19, run19, draft19), 3, "MISSING_SOURCE")
    qa19b, run19b, draft19b = environment(root)
    draft19b["sources"] = [source for source in draft19b["sources"] if not source["path"].endswith("/readiness.json")]
    expect("embedded readiness source is mandatory", seal(qa19b, run19b, draft19b), 3, "MISSING_SOURCE")

    for index, key in enumerate(("authToken", "sessionToken", "bearer", "jwt", "dbPassword", "clientSecret", "apiAuthToken", "xApiKey")):
        qa_secret, run_secret, draft_secret = environment(root)
        draft_secret["effective_config"]["test_assets"][key] = "ordinary-non-canary-value"
        expect(f"secret suffix key {key} rejected", seal(qa_secret, run_secret, draft_secret), 3, "FORBIDDEN_FIELD")

    type_cases = (
        ("secret_key", lambda capsule: capsule["effective_config"]["test_users"][0].__setitem__("secret_key", TYPE_VALUE)),
        ("bridge.sha256", lambda capsule: capsule["knowledge"]["bridge"].__setitem__("sha256", TYPE_VALUE)),
        ("sources.sha256", lambda capsule: capsule["sources"][0].__setitem__("sha256", TYPE_VALUE)),
        ("integrity.payload_sha256", lambda capsule: capsule["integrity"].__setitem__("payload_sha256", TYPE_VALUE)),
    )
    for TYPE_VALUE in (7, [], {}, None):
        for label, mutate in type_cases:
            qa_type, run_type, draft_type = environment(root)
            mutate(draft_type)
            result = seal(qa_type, run_type, draft_type)
            expect(f"{label} {type(TYPE_VALUE).__name__} has clean INVALID_STRUCTURE", result, 3, "INVALID_STRUCTURE")
            check(f"{label} {type(TYPE_VALUE).__name__} has no traceback", "Traceback" not in result[1], result[1])

    qa20, run20, draft20 = environment(root)
    draft20["sources"] = [source for source in draft20["sources"] if source["path"] != "projects/SHOP/PROJECT.md"]
    expect("routing PROJECT.md source hash is mandatory", seal(qa20, run20, draft20), 3, "MISSING_SOURCE")
    qa20b, run20b, draft20b = environment(root)
    draft20b["sources"] = [source for source in draft20b["sources"] if not source["path"].endswith("/ADMIN/PRODUCT.md")]
    expect("routing PRODUCT.md source hash is mandatory", seal(qa20b, run20b, draft20b), 3, "MISSING_SOURCE")
    qa20c, run20c, draft20c = environment(root)
    expect("missing PROJECT fixture seals", seal(qa20c, run20c, draft20c), 0)
    (qa20c / "projects" / "SHOP" / "PROJECT.md").unlink()
    expect(
        "central validation treats missing PROJECT.md as stale",
        invoke("validate", "--capsule", capsule_path(run20c), "--qa-home", qa20c, "--run-dir", run20c),
        4,
        "STALE_CONTEXT",
    )

    qa21, run21, draft21 = environment(root)
    expect("revision conflict fixture seals v1", seal(qa21, run21, draft21), 0)
    v1_path = capsule_path(run21)
    v1_bytes = v1_path.read_bytes()
    v1 = json.loads(v1_bytes)
    modified = copy.deepcopy(v1)
    modified["effective_config"]["execution"]["mode"] = "hybrid"
    modified["integrity"]["payload_sha256"] = ""
    modified_path = run21 / "modified-draft.json"
    write_json(modified_path, modified)
    expect(
        "modified same-revision reseal conflicts",
        invoke("seal", "--draft", modified_path, "--capsule", v1_path, "--run-dir", run21),
        3,
        "REVISION_CONFLICT",
    )
    check("revision conflict preserves v1", v1_path.read_bytes() == v1_bytes)

    v2 = copy.deepcopy(v1)
    v2["run"]["revision"] = 2
    v2["run"]["created_at"] = "2026-10-28T11:15:00Z"
    v2["intake"]["expected_build"] = "release-25.0"
    v2["readiness"]["build"]["expected"] = "release-25.0"
    v2["readiness"]["build"]["deployed"] = "release-25.0"
    v2["effective_config"]["stage"]["expected_build"] = "release-25.0"
    v2["integrity"]["payload_sha256"] = ""
    write_json(run21 / "intake.json", v2["intake"])
    write_json(run21 / "readiness.json", v2["readiness"])
    for source in v2["sources"]:
        if source["path"].endswith("/intake.json") or source["path"].endswith("/readiness.json"):
            source["sha256"] = digest(qa21 / source["path"])
    v2_path = run21 / "context-capsule.v2.json"
    v2_draft_path = run21 / "v2-draft.json"
    write_json(v2_draft_path, v2)
    expect(
        "revision 2 seals at versioned path",
        invoke("seal", "--draft", v2_draft_path, "--capsule", v2_path, "--run-dir", run21),
        0,
    )
    check("revision 2 preserves revision 1 file", v1_path.read_bytes() == v1_bytes and v2_path.is_file())
    expect(
        "revision 2 validates centrally",
        invoke("validate", "--capsule", v2_path, "--qa-home", qa21, "--run-dir", run21),
        0,
        "valid",
    )
    older = copy.deepcopy(v2)
    older["run"]["revision"] = 1
    older["intake"]["title"] = "Older changed payload"
    older["integrity"]["payload_sha256"] = ""
    older_path = run21 / "older-draft.json"
    v2_bytes = v2_path.read_bytes()
    write_json(older_path, older)
    expect(
        "changed older-revision payload conflicts",
        invoke("seal", "--draft", older_path, "--capsule", v2_path, "--run-dir", run21),
        3,
        "REVISION_CONFLICT",
    )
    check("older-revision conflict preserves v2", v2_path.read_bytes() == v2_bytes)

    qa22, run22, draft22 = environment(root)
    draft22["run"]["revision"] = 2
    write_json(run22 / "context-capsule.v2.json", draft22)
    expect(
        "revision 2 requires revision 1 predecessor",
        invoke("seal", "--capsule", run22 / "context-capsule.v2.json", "--run-dir", run22),
        3,
        "REVISION_CHAIN_MISSING",
    )
    qa22b, run22b, draft22b = environment(root)
    expect("wrong revision path fixture seals v1", seal(qa22b, run22b, draft22b), 0)
    wrong_path = copy.deepcopy(draft22b)
    wrong_path["run"]["revision"] = 2
    wrong_path["integrity"]["payload_sha256"] = ""
    wrong_draft = run22b / "wrong-path-draft.json"
    write_json(wrong_draft, wrong_path)
    expect(
        "revision 2 cannot overwrite canonical v1 path",
        invoke("seal", "--draft", wrong_draft, "--capsule", capsule_path(run22b), "--run-dir", run22b),
        3,
        "REVISION_PATH_MISMATCH",
    )

    qa23, run23, draft23 = environment(root)
    expect("invalid existing hash fixture seals", seal(qa23, run23, draft23), 0)
    valid_existing = json.loads(capsule_path(run23).read_text(encoding="utf-8"))
    safe_draft = run23 / "safe-draft.json"
    write_json(safe_draft, valid_existing)
    valid_existing["integrity"]["payload_sha256"] = "0" * 64
    write_json(capsule_path(run23), valid_existing)
    invalid_bytes = capsule_path(run23).read_bytes()
    expect(
        "invalid existing hash is never overwritten",
        invoke("seal", "--draft", safe_draft, "--capsule", capsule_path(run23), "--run-dir", run23),
        3,
        "PAYLOAD_HASH_MISMATCH",
    )
    check("invalid existing capsule bytes preserved", capsule_path(run23).read_bytes() == invalid_bytes)

    specification = importlib.util.spec_from_file_location("context_capsule", SCRIPT)
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    number_cases = (
        (0, "0"),
        (-0.0, "0"),
        (1.0, "1"),
        (333333333.33333329, "333333333.3333333"),
        (1e30, "1e+30"),
        (4.50, "4.5"),
        (2e-3, "0.002"),
        (1e-27, "1e-27"),
        (1e-6, "0.000001"),
        (1e-7, "1e-7"),
        (1e20, "100000000000000000000"),
        (1e21, "1e+21"),
        (2**53 - 1, "9007199254740991"),
        (-(2**53 - 1), "-9007199254740991"),
    )
    for value, expected in number_cases:
        try:
            actual = module.canonicalize(value)
        except module.CapsuleError as error:
            actual = f"{error.code}: {error}"
        check(f"RFC8785 number {value!r} -> {expected}", actual == expected, actual)
    for value in (2**53, -(2**53)):
        try:
            module.canonicalize(value)
            rejected = False
        except module.CapsuleError as error:
            rejected = error.code == "INVALID_JSON"
        check(f"RFC8785 unsafe integer {value} rejected", rejected)
    qa24, run24, draft24 = environment(root)
    draft24["intake"]["unsafe_integer"] = 2**53
    expect("unsafe integer cannot be sealed into a payload", seal(qa24, run24, draft24), 3, "INVALID_JSON")
    qa25, run25, draft25 = environment(root)
    draft25["effective_config"]["secretKey"] = "literal-secret-value"
    expect("secretKey outside test user references rejected", seal(qa25, run25, draft25), 3, "FORBIDDEN_FIELD")
    qa26, run26, draft26 = environment(root)
    draft26["effective_config"]["test_users"][0]["purpose"] = {"secretKey": "literal-secret-value"}
    expect("nested secretKey is never a reference", seal(qa26, run26, draft26), 3, "FORBIDDEN_FIELD")

print()
if FAILURES:
    print(f"{FAILURES} fixture(s) failed")
else:
    print("all fixtures passed")
sys.exit(FAILURES)
PY

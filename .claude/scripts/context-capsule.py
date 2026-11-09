#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Sn4kyGit

import argparse
import copy
import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import sys
import tempfile

SCHEMA_VERSION = "qa-run-context/v1"
MAX_BYTES = 16 * 1024
MAX_SAFE_INTEGER = 2**53 - 1
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
TICKET_RE = re.compile(r"^([A-Z][A-Z0-9_]*)-([0-9]+)$")
KEY_RE = re.compile(r"^[A-Z][A-Z0-9_]*$")
RUN_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
SECRET_CANARY_RE = re.compile(
    r"(?:QA_CAPSULE_SECRET_CANARY|(?:SECRET|TOKEN|PASSWORD)[_-]CANARY|CANARY[_-](?:SECRET|TOKEN|PASSWORD))",
    re.IGNORECASE,
)
ALLOWED_REFERENCE_KEYS = {"secretkey", "vaultpath"}
FORBIDDEN_KEY_SUFFIXES = (
    "password", "passwd", "passphrase", "secret", "secretkey", "token", "apikey",
    "authtoken", "sessiontoken", "accesstoken", "refreshtoken", "apitoken",
    "bearer", "jwt", "dbpassword", "clientsecret", "privatekey", "credential",
    "credentials",
)
FORBIDDEN_KEYS = {
    "password", "passwd", "passphrase", "secret", "secrets", "token",
    "accesstoken", "refreshtoken", "apitoken", "apikey", "authorization",
    "cookie", "cookies", "setcookie", "authstate", "storagestate",
    "sessionstate", "credential", "credentials", "privatekey", "clientsecret",
    "headers", "requestheaders", "responseheaders", "rawlog", "rawlogs", "log",
    "logs", "consolelog", "networklog", "tickethistory", "ticketcomments", "comments",
    "changelog", "history", "fullhistory", "ticketchangelog", "session", "sessiondata",
    "secretcanary", "tokencanary", "passwordcanary",
}
UNCONFIRMED_KEYS = {"unconfirmedcandidates", "unconfirmedareas"}
SEALED_FIELDS = {
    "effective_config.jira.transitions",
    "effective_config.jira.readiness_statuses",
    "effective_config.jira.merge_requirement",
    "effective_config.jira.report_format",
    "effective_config.reporting",
    "effective_config.reporting.format",
    "effective_config.reporting.transitions",
    "effective_config.deploy.agent_may_trigger",
    "effective_config.deploy.agent_may_comment_on_mrs",
    "effective_config.evidence",
    "effective_config.security",
    "effective_config.mcp",
}
REQUIRED_FIELD_SOURCES = {
    "effective_config.jira.access",
    "effective_config.jira.shadow",
    "effective_config.execution.mode",
    "effective_config.stage.url",
    "effective_config.test_users",
    "effective_config.test_assets",
    "effective_config.features",
}


class CapsuleError(Exception):
    def __init__(self, code, message, exit_code=3):
        super().__init__(message)
        self.code = code
        self.exit_code = exit_code


def fail(code, message, exit_code=3):
    raise CapsuleError(code, message, exit_code)


def stale(message):
    fail("STALE_CONTEXT", message, 4)


def normalized_key(value):
    return re.sub(r"[^a-z0-9]", "", value.lower())


def reject_duplicates(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            fail("INVALID_JSON", f"duplicate object key at {key!r}")
        result[key] = value
    return result


def reject_constant(value):
    fail("INVALID_JSON", f"non-finite JSON number {value!r}")


def load_json(path):
    try:
        raw = Path(path).read_bytes()
    except OSError as exc:
        fail("IO_ERROR", f"cannot read {path}: {exc.strerror}", 5)
    if len(raw) > MAX_BYTES and Path(path).name == "context-capsule.json":
        fail("CAPSULE_TOO_LARGE", f"capsule is {len(raw)} bytes; maximum is {MAX_BYTES}")
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        fail("INVALID_JSON", f"{path} is not valid UTF-8")
    try:
        return json.loads(text, object_pairs_hook=reject_duplicates, parse_constant=reject_constant)
    except CapsuleError:
        raise
    except (json.JSONDecodeError, ValueError) as exc:
        fail("INVALID_JSON", f"cannot parse {path}: {exc}")


def load_capsule(path):
    try:
        size = Path(path).stat().st_size
    except OSError as exc:
        fail("IO_ERROR", f"cannot read {path}: {exc.strerror}", 5)
    if size > MAX_BYTES:
        fail("CAPSULE_TOO_LARGE", f"capsule is {size} bytes; maximum is {MAX_BYTES}")
    return load_json(path)


def canonical_number(value):
    if isinstance(value, int):
        if abs(value) > MAX_SAFE_INTEGER:
            fail("INVALID_JSON", "integers must be within RFC8785/I-JSON safe range ±(2^53−1)")
        return str(value)
    if not math.isfinite(value):
        fail("INVALID_JSON", "non-finite numbers cannot be canonicalized")
    if value == 0:
        return "0"
    negative = value < 0
    text = repr(abs(value)).lower()
    if "e" in text:
        coefficient, exponent_text = text.split("e")
        exponent = int(exponent_text)
    else:
        coefficient = text
        exponent = 0
    if "." in coefficient:
        whole, fraction = coefficient.split(".")
        digits = whole + fraction
        exponent -= len(fraction)
    else:
        digits = coefficient
    digits = digits.lstrip("0") or "0"
    while len(digits) > 1 and digits.endswith("0"):
        digits = digits[:-1]
        exponent += 1
    decimal_position = len(digits) + exponent
    if 0 < decimal_position <= 21:
        if decimal_position >= len(digits):
            result = digits + "0" * (decimal_position - len(digits))
        else:
            result = digits[:decimal_position] + "." + digits[decimal_position:]
    elif -6 < decimal_position <= 0:
        result = "0." + "0" * (-decimal_position) + digits
    else:
        result = digits[0]
        if len(digits) > 1:
            result += "." + digits[1:]
        scientific_exponent = decimal_position - 1
        result += "e" + ("+" if scientific_exponent >= 0 else "-") + str(abs(scientific_exponent))
    return ("-" if negative else "") + result


def canonicalize(value):
    if value is None:
        return "null"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, (int, float)):
        return canonical_number(value)
    if isinstance(value, str):
        try:
            value.encode("utf-8")
        except UnicodeEncodeError:
            fail("INVALID_JSON", "strings must not contain lone UTF-16 surrogates")
        return json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    if isinstance(value, list):
        return "[" + ",".join(canonicalize(item) for item in value) + "]"
    if isinstance(value, dict):
        keys = list(value)
        if not all(isinstance(key, str) for key in keys):
            fail("INVALID_JSON", "object keys must be strings")
        try:
            ordered = sorted(keys, key=lambda key: key.encode("utf-16-be"))
        except UnicodeEncodeError:
            fail("INVALID_JSON", "object keys must not contain lone UTF-16 surrogates")
        return "{" + ",".join(canonicalize(key) + ":" + canonicalize(value[key]) for key in ordered) + "}"
    fail("INVALID_JSON", f"unsupported JSON value {type(value).__name__}")


def payload_hash(capsule):
    payload = copy.deepcopy(capsule)
    integrity = payload.get("integrity")
    if isinstance(integrity, dict):
        integrity.pop("payload_sha256", None)
    encoded = canonicalize(payload).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def require_dict(value, path):
    if not isinstance(value, dict):
        fail("INVALID_STRUCTURE", f"{path} must be an object")
    return value


def require_list(value, path):
    if not isinstance(value, list):
        fail("INVALID_STRUCTURE", f"{path} must be an array")
    return value


def require_string(value, path):
    if not isinstance(value, str) or not value:
        fail("INVALID_STRUCTURE", f"{path} must be a non-empty string")
    return value


def require_bool(value, path):
    if not isinstance(value, bool):
        fail("INVALID_STRUCTURE", f"{path} must be a boolean")
    return value


def exact_keys(value, required, optional, path):
    require_dict(value, path)
    missing = sorted(required - set(value))
    extra = sorted(set(value) - required - optional)
    if missing:
        fail("INVALID_STRUCTURE", f"{path} missing keys: {', '.join(missing)}")
    if extra:
        fail("INVALID_STRUCTURE", f"{path} has unknown keys: {', '.join(extra)}")


def scan_forbidden(value, path="$"):
    if isinstance(value, dict):
        for key, child in value.items():
            normalized = normalized_key(key)
            child_path = f"{path}.{key}"
            forbidden = normalized in FORBIDDEN_KEYS or normalized.endswith(FORBIDDEN_KEY_SUFFIXES)
            allowed_reference = normalized in ALLOWED_REFERENCE_KEYS and re.fullmatch(r"\$\.effective_config\.test_users\[\d+\]\.(?:secret_key|vault_path)", child_path) is not None
            if forbidden and not allowed_reference:
                fail("FORBIDDEN_FIELD", f"forbidden field {child_path}")
            if normalized in UNCONFIRMED_KEYS:
                fail("UNCONFIRMED_CONTEXT", f"unconfirmed context is forbidden at {child_path}")
            scan_forbidden(child, child_path)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            scan_forbidden(child, f"{path}[{index}]")
    elif isinstance(value, str) and SECRET_CANARY_RE.search(value):
        fail("SECRET_CANARY", f"secret canary detected at {path}")


def validate_relative_path(value, path):
    require_string(value, path)
    if "\\" in value or value.startswith("/"):
        fail("INVALID_SOURCE", f"{path} must be a relative POSIX path")
    pure = PurePosixPath(value)
    if any(part in ("", ".", "..") for part in pure.parts) or str(pure) != value:
        fail("INVALID_SOURCE", f"{path} is not normalized: {value}")
    return value


def source_values(value, path):
    if isinstance(value, str):
        return [value]
    if isinstance(value, list) and value and all(isinstance(item, str) and item for item in value):
        return value
    fail("INVALID_STRUCTURE", f"{path} must be a source path or a non-empty array of source paths")


def validate_shape(capsule):
    scan_forbidden(capsule)
    exact_keys(
        capsule,
        {"schema_version", "run", "intake", "readiness", "routing", "effective_config", "knowledge", "field_sources", "sources", "integrity"},
        set(),
        "$",
    )
    if capsule["schema_version"] != SCHEMA_VERSION:
        fail("WRONG_SCHEMA", f"schema_version must be {SCHEMA_VERSION}")
    run = capsule["run"]
    exact_keys(run, {"id", "ticket", "project", "scope", "revision", "created_at"}, {"product"}, "run")
    require_string(run["id"], "run.id")
    if not RUN_ID_RE.fullmatch(run["id"]):
        fail("INVALID_RUN", "run.id contains unsupported characters")
    require_string(run["ticket"], "run.ticket")
    match = TICKET_RE.fullmatch(run["ticket"])
    if not match:
        fail("INVALID_RUN", "run.ticket must be a JIRA key such as SHOP-123")
    require_string(run["project"], "run.project")
    if not KEY_RE.fullmatch(run["project"]) or match.group(1) != run["project"]:
        fail("RUN_TICKET_MISMATCH", "run.project must equal the ticket prefix")
    if run["scope"] not in ("project", "product"):
        fail("INVALID_RUN", "run.scope must be project or product")
    if run["scope"] == "product":
        product = require_string(run.get("product"), "run.product")
        if not KEY_RE.fullmatch(product):
            fail("INVALID_RUN", "run.product must be an uppercase product key")
    elif "product" in run:
        fail("UNEXPECTED_PRODUCT", "run.product is forbidden when run.scope is project")
    if not isinstance(run["revision"], int) or isinstance(run["revision"], bool) or run["revision"] < 1:
        fail("INVALID_RUN", "run.revision must be a positive integer")
    created_at = require_string(run["created_at"], "run.created_at")
    if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]+)?Z", created_at):
        fail("INVALID_RUN", "run.created_at must be an RFC3339 UTC timestamp")
    intake = require_dict(capsule["intake"], "intake")
    readiness = require_dict(capsule["readiness"], "readiness")
    if intake.get("ticket") != run["ticket"]:
        fail("RUN_TICKET_MISMATCH", "intake.ticket must equal run.ticket")
    if readiness.get("ticket") != run["ticket"]:
        fail("RUN_TICKET_MISMATCH", "readiness.ticket must equal run.ticket")
    if "acceptance_criteria" not in intake:
        fail("INVALID_STRUCTURE", "intake.acceptance_criteria is required")
    criteria = require_list(intake["acceptance_criteria"], "intake.acceptance_criteria")
    seen_ac = set()
    for index, criterion in enumerate(criteria):
        require_dict(criterion, f"intake.acceptance_criteria[{index}]")
        ac_id = require_string(criterion.get("id"), f"intake.acceptance_criteria[{index}].id")
        require_string(criterion.get("text"), f"intake.acceptance_criteria[{index}].text")
        if ac_id in seen_ac:
            fail("INVALID_STRUCTURE", f"duplicate acceptance criterion {ac_id}")
        seen_ac.add(ac_id)
    require_bool(readiness.get("ready"), "readiness.ready")
    routing = capsule["routing"]
    exact_keys(routing, {"project_path"}, {"product_path", "product_routed_by", "confidence"}, "routing")
    expected_project_path = f"projects/{run['project']}/PROJECT.md"
    if routing["project_path"] != expected_project_path:
        fail("ROUTING_MISMATCH", f"routing.project_path must be {expected_project_path}")
    if "product" in run:
        expected_product_path = f"projects/{run['project']}/products/{run['product']}/PRODUCT.md"
        if routing.get("product_path") != expected_product_path:
            fail("ROUTING_MISMATCH", f"routing.product_path must be {expected_product_path}")
    elif "product_path" in routing:
        fail("UNEXPECTED_PRODUCT", "routing.product_path is forbidden without run.product")
    effective = require_dict(capsule["effective_config"], "effective_config")
    for key in ("jira", "execution", "stage", "test_assets"):
        require_dict(effective.get(key), f"effective_config.{key}")
    if effective["jira"].get("access") not in ("mcp", "browser"):
        fail("INVALID_STRUCTURE", "effective_config.jira.access must be mcp or browser")
    require_bool(effective["jira"].get("shadow"), "effective_config.jira.shadow")
    if effective["execution"].get("mode") not in ("mcp-only", "hybrid", "cli-first"):
        fail("INVALID_STRUCTURE", "effective_config.execution.mode is invalid")
    stage_url = require_string(effective["stage"].get("url"), "effective_config.stage.url")
    if not stage_url.startswith(("https://", "http://")):
        fail("INVALID_STRUCTURE", "effective_config.stage.url must be an HTTP(S) URL")
    users = require_list(effective.get("test_users"), "effective_config.test_users")
    for index, user in enumerate(users):
        exact_keys(user, {"role"}, {"purpose", "secret_key", "vault_path"}, f"effective_config.test_users[{index}]")
        require_string(user.get("role"), f"effective_config.test_users[{index}].role")
        if "purpose" in user:
            require_string(user["purpose"], f"effective_config.test_users[{index}].purpose")
        if "secret_key" not in user and "vault_path" not in user:
            fail("INVALID_STRUCTURE", f"effective_config.test_users[{index}] needs secret_key or vault_path")
        if "secret_key" in user:
            secret_key = require_string(user["secret_key"], f"effective_config.test_users[{index}].secret_key")
            if not re.fullmatch(r"[A-Z][A-Z0-9_]*", secret_key):
                fail("INVALID_STRUCTURE", f"effective_config.test_users[{index}].secret_key must be an environment key")
        if "vault_path" in user:
            require_string(user["vault_path"], f"effective_config.test_users[{index}].vault_path")
    framework = effective["test_assets"].get("framework")
    if framework not in ("playwright", "webdriverio", "none"):
        fail("INVALID_STRUCTURE", "effective_config.test_assets.framework is invalid")
    features = require_list(effective.get("features"), "effective_config.features")
    for index, feature in enumerate(features):
        require_dict(feature, f"effective_config.features[{index}]")
        require_string(feature.get("feature"), f"effective_config.features[{index}].feature")
        require_bool(feature.get("applies"), f"effective_config.features[{index}].applies")
    knowledge = capsule["knowledge"]
    exact_keys(knowledge, {"learnings", "confirmed_areas", "bridge"}, set(), "knowledge")
    learnings = require_list(knowledge.get("learnings"), "knowledge.learnings")
    for index, learning in enumerate(learnings):
        exact_keys(learning, {"excerpt", "source"}, set(), f"knowledge.learnings[{index}]")
        require_string(learning["excerpt"], f"knowledge.learnings[{index}].excerpt")
        validate_relative_path(learning["source"], f"knowledge.learnings[{index}].source")
    areas = require_list(knowledge.get("confirmed_areas"), "knowledge.confirmed_areas")
    for index, area in enumerate(areas):
        require_dict(area, f"knowledge.confirmed_areas[{index}]")
        require_string(area.get("name"), f"knowledge.confirmed_areas[{index}].name")
        if area.get("status") != "confirmed":
            fail("UNCONFIRMED_CONTEXT", f"knowledge.confirmed_areas[{index}].status must be confirmed")
        validate_relative_path(area.get("source"), f"knowledge.confirmed_areas[{index}].source")
    bridge = require_dict(knowledge.get("bridge"), "knowledge.bridge")
    exact_keys(bridge, {"path", "sha256"}, set(), "knowledge.bridge")
    validate_relative_path(bridge["path"], "knowledge.bridge.path")
    bridge_sha256 = require_string(bridge["sha256"], "knowledge.bridge.sha256")
    if not SHA256_RE.fullmatch(bridge_sha256):
        fail("INVALID_STRUCTURE", "knowledge.bridge.sha256 must be lowercase SHA-256")
    require_dict(capsule["field_sources"], "field_sources")
    sources = require_list(capsule["sources"], "sources")
    if not sources:
        fail("INVALID_STRUCTURE", "sources must not be empty")
    seen_sources = set()
    for index, source in enumerate(sources):
        exact_keys(source, {"path", "sha256"}, set(), f"sources[{index}]")
        path = validate_relative_path(source["path"], f"sources[{index}].path")
        if path in seen_sources:
            fail("INVALID_SOURCE", f"duplicate source {path}")
        seen_sources.add(path)
        source_sha256 = require_string(source["sha256"], f"sources[{index}].sha256")
        if not SHA256_RE.fullmatch(source_sha256):
            fail("INVALID_STRUCTURE", f"sources[{index}].sha256 must be lowercase SHA-256")
    integrity = capsule["integrity"]
    exact_keys(integrity, {"canonicalization", "payload_sha256"}, set(), "integrity")
    if integrity["canonicalization"] != "RFC8785":
        fail("INVALID_STRUCTURE", "integrity.canonicalization must be RFC8785")
    integrity_sha256 = require_string(integrity["payload_sha256"], "integrity.payload_sha256")
    if not SHA256_RE.fullmatch(integrity_sha256):
        fail("INVALID_STRUCTURE", "integrity.payload_sha256 must be lowercase SHA-256")


def allowed_source(path, capsule, run_dir=None, qa_home=None):
    run = capsule["run"]
    project = run["project"]
    product = run.get("product")
    allowed = {
        f"projects/{project}/PROJECT.md",
        f"projects/{project}/learnings.md",
        f"projects/{project}/flow-map.md",
        f".agents/qa-project-context/{project}.md",
    }
    if product:
        allowed.update({
            f"projects/{project}/products/{product}/PRODUCT.md",
            f"projects/{project}/products/{product}/learnings.md",
            f"projects/{project}/products/{product}/flow-map.md",
            f".agents/qa-project-context/{project}/{product}.md",
        })
    if path.startswith("memory/learnings/") and path.endswith(".md"):
        return True
    if path in allowed:
        return True
    if run_dir is not None and qa_home is not None:
        try:
            relative = (Path(run_dir).resolve() / Path(path).name).relative_to(Path(qa_home).resolve())
        except ValueError:
            relative = None
        if relative is not None and path == relative.as_posix() and Path(path).name in ("intake.json", "readiness.json"):
            return True
    expected_prefix = f"evidence/{project}/{run['ticket']}/{run['id']}/"
    return path in (expected_prefix + "intake.json", expected_prefix + "readiness.json")


def nested_value(capsule, path):
    current = capsule
    for part in path.split("."):
        if not isinstance(current, dict) or part not in current:
            return False, None
        current = current[part]
    return True, current


def validate_provenance(capsule, qa_home=None, run_dir=None):
    run = capsule["run"]
    source_hashes = {source["path"]: source["sha256"] for source in capsule["sources"]}
    artifact_prefix = f"evidence/{run['project']}/{run['ticket']}/{run['id']}"
    for name in ("intake", "readiness"):
        required = f"{artifact_prefix}/{name}.json"
        if required not in source_hashes:
            fail("MISSING_SOURCE", f"embedded {name}.json is not listed in sources")
    routing_sources = [capsule["routing"]["project_path"]]
    if "product_path" in capsule["routing"]:
        routing_sources.append(capsule["routing"]["product_path"])
    for path in routing_sources:
        if path not in source_hashes:
            fail("MISSING_SOURCE", f"routing source {path} is not listed in sources with a hash")
    for path in source_hashes:
        if not allowed_source(path, capsule, run_dir, qa_home):
            fail("FOREIGN_SOURCE", f"source does not belong to this run/project/product: {path}")
    for field in sorted(SEALED_FIELDS):
        present, _ = nested_value(capsule, field)
        if not present:
            continue
        covered = any(
            mapped == field or mapped.startswith(field + ".") or field.startswith(mapped + ".")
            for mapped in capsule["field_sources"]
            if mapped in SEALED_FIELDS
        )
        if not covered:
            fail("MISSING_FIELD_SOURCE", f"sealed field {field} needs PROJECT.md provenance")
    referenced = []
    for field, value in capsule["field_sources"].items():
        paths = source_values(value, f"field_sources.{field}")
        for path in paths:
            if path.startswith("env:"):
                if field != "effective_config.jira.shadow" or path != "env:QA_AGENT_SHADOW":
                    fail("INVALID_SOURCE", f"environment provenance is only valid for QA_AGENT_SHADOW at {field}")
                continue
            validate_relative_path(path, f"field_sources.{field}")
            if path not in source_hashes:
                fail("MISSING_SOURCE", f"field_sources.{field} references unlisted source {path}")
            referenced.append(path)
            if field in SEALED_FIELDS and path != f"projects/{run['project']}/PROJECT.md":
                fail("SEALED_FIELD_SOURCE", f"sealed field {field} must come only from PROJECT.md")
    for index, learning in enumerate(capsule["knowledge"]["learnings"]):
        path = learning["source"]
        if path not in source_hashes:
            fail("MISSING_SOURCE", f"knowledge.learnings[{index}] references unlisted source {path}")
        referenced.append(path)
    for index, area in enumerate(capsule["knowledge"]["confirmed_areas"]):
        path = area["source"]
        if path not in source_hashes:
            fail("MISSING_SOURCE", f"knowledge.confirmed_areas[{index}] references unlisted source {path}")
        referenced.append(path)
    bridge = capsule["knowledge"]["bridge"]
    if bridge["path"] not in source_hashes:
        fail("MISSING_SOURCE", "knowledge.bridge.path is not listed in sources")
    if source_hashes[bridge["path"]] != bridge["sha256"]:
        fail("BRIDGE_HASH_MISMATCH", "knowledge.bridge.sha256 differs from its sources entry")
    missing_fields = sorted(REQUIRED_FIELD_SOURCES - set(capsule["field_sources"]))
    if missing_fields:
        fail("INVALID_STRUCTURE", f"field_sources missing: {', '.join(missing_fields)}")
    if qa_home is not None:
        project_file = Path(qa_home) / "projects" / run["project"] / "PROJECT.md"
        if not project_file.is_file():
            stale(f"required PROJECT.md is missing: {project_file}")
        if "product" in run:
            try:
                text = project_file.read_text(encoding="utf-8")
            except OSError as exc:
                fail("IO_ERROR", f"cannot read {project_file}: {exc.strerror}", 5)
            if not re.search(r"(?m)^##\s+Products\s*$", text):
                fail("UNEXPECTED_PRODUCT", "run.product is forbidden for a project without ## Products")


def sha256_file(path):
    digest = hashlib.sha256()
    try:
        with Path(path).open("rb") as handle:
            for chunk in iter(lambda: handle.read(65536), b""):
                digest.update(chunk)
    except OSError as exc:
        stale(f"source unavailable: {path}: {exc.strerror}")
    return digest.hexdigest()


def expected_capsule_name(revision):
    return "context-capsule.json" if revision == 1 else f"context-capsule.v{revision}.json"


def validate_revision_path(capsule, capsule_path):
    expected = expected_capsule_name(capsule["run"]["revision"])
    if Path(capsule_path).name != expected:
        fail("REVISION_PATH_MISMATCH", f"revision {capsule['run']['revision']} must use {expected}")


def validate_run_dir(capsule, capsule_path, run_dir):
    run = capsule["run"]
    capsule_path = Path(capsule_path).resolve()
    run_dir = Path(run_dir).resolve()
    if capsule_path.parent != run_dir:
        fail("RUN_DIR_MISMATCH", "capsule must be stored directly in --run-dir")
    if run_dir.name != run["id"] or run_dir.parent.name != run["ticket"] or run_dir.parent.parent.name != run["project"]:
        fail("RUN_DIR_MISMATCH", "run.id/ticket/project do not match evidence/<PROJECT>/<TICKET>/<RUN>")


def validate_embedded(capsule, run_dir):
    for name in ("intake", "readiness"):
        path = Path(run_dir) / f"{name}.json"
        if not path.is_file():
            continue
        actual = load_json(path)
        if actual != capsule[name]:
            stale(f"embedded {name}.json differs; the orchestrator must create a new revision")


def validate_sources(capsule, qa_home):
    root = Path(qa_home).resolve()
    for source in capsule["sources"]:
        path = root / source["path"]
        actual = sha256_file(path)
        if actual != source["sha256"]:
            stale(f"source hash mismatch: {source['path']}")


def validate_capsule(capsule, capsule_path, qa_home=None, run_dir=None):
    validate_shape(capsule)
    validate_revision_path(capsule, capsule_path)
    expected = payload_hash(capsule)
    if capsule["integrity"]["payload_sha256"] != expected:
        fail("PAYLOAD_HASH_MISMATCH", f"payload hash mismatch; expected {expected}")
    if run_dir is not None:
        validate_run_dir(capsule, capsule_path, run_dir)
    validate_provenance(capsule, qa_home, run_dir)
    if run_dir is not None:
        validate_embedded(capsule, run_dir)
    if qa_home is not None:
        validate_sources(capsule, qa_home)


def validate_stored_capsule(capsule, capsule_path, run_dir=None):
    validate_shape(capsule)
    validate_revision_path(capsule, capsule_path)
    expected = payload_hash(capsule)
    if capsule["integrity"]["payload_sha256"] != expected:
        fail("PAYLOAD_HASH_MISMATCH", "existing capsule has an invalid payload hash; refusing to overwrite")
    if run_dir is not None:
        validate_run_dir(capsule, capsule_path, run_dir)
    validate_provenance(capsule, None, run_dir)


def validate_predecessor(capsule, capsule_path, run_dir=None):
    revision = capsule["run"]["revision"]
    if revision == 1:
        return
    destination = Path(capsule_path)
    previous_path = destination.with_name(expected_capsule_name(revision - 1))
    if not previous_path.is_file():
        fail("REVISION_CHAIN_MISSING", f"previous revision is required: {previous_path.name}")
    previous = load_capsule(previous_path)
    validate_stored_capsule(previous, previous_path, run_dir)
    if previous["run"]["revision"] != revision - 1:
        fail("REVISION_CHAIN_MISMATCH", f"{previous_path.name} contains the wrong revision")
    for key in ("id", "ticket", "project", "product", "scope"):
        if previous["run"].get(key) != capsule["run"].get(key):
            fail("REVISION_CHAIN_MISMATCH", f"revision chain changed run.{key}")


def seal_capsule(capsule, capsule_path, qa_home=None, run_dir=None, draft_path=None):
    integrity = capsule.get("integrity")
    if isinstance(integrity, dict) and ("payload_sha256" not in integrity or integrity["payload_sha256"] == ""):
        integrity["payload_sha256"] = "0" * 64
    validate_shape(capsule)
    capsule["integrity"]["payload_sha256"] = payload_hash(capsule)
    destination = Path(capsule_path)
    existing = None
    if destination.exists():
        candidate = load_capsule(destination)
        existing_integrity = candidate.get("integrity") if isinstance(candidate, dict) else None
        existing_hash = existing_integrity.get("payload_sha256") if isinstance(existing_integrity, dict) else None
        same_unsealed_file = (
            draft_path is not None
            and Path(draft_path).resolve() == destination.resolve()
            and isinstance(existing_integrity, dict)
            and ("payload_sha256" not in existing_integrity or existing_hash == "" or existing_hash == "0" * 64)
        )
        if not same_unsealed_file:
            existing = candidate
            validate_stored_capsule(existing, destination, run_dir)
            if (
                existing["integrity"]["payload_sha256"] != capsule["integrity"]["payload_sha256"]
                and existing["run"]["revision"] >= capsule["run"]["revision"]
            ):
                fail("REVISION_CONFLICT", "changed payload requires a new revision and revision path")
    validate_capsule(capsule, capsule_path, qa_home, run_dir)
    validate_predecessor(capsule, destination, run_dir)
    if existing is not None:
        if existing["integrity"]["payload_sha256"] != capsule["integrity"]["payload_sha256"]:
            fail("REVISION_CONFLICT", "changed payload requires a new revision and revision path")
        return existing["integrity"]["payload_sha256"]
    rendered = (json.dumps(capsule, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    if len(rendered) > MAX_BYTES:
        fail("CAPSULE_TOO_LARGE", f"sealed capsule is {len(rendered)} bytes; maximum is {MAX_BYTES}")
    destination = Path(capsule_path)
    try:
        destination.parent.mkdir(parents=True, exist_ok=True)
        descriptor, temporary = tempfile.mkstemp(prefix=".context-capsule.", suffix=".tmp", dir=destination.parent)
        try:
            with os.fdopen(descriptor, "wb") as handle:
                handle.write(rendered)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, destination)
        except Exception:
            try:
                os.unlink(temporary)
            except OSError:
                pass
            raise
    except OSError as exc:
        fail("IO_ERROR", f"cannot write {destination}: {exc.strerror}", 5)
    return capsule["integrity"]["payload_sha256"]


def parse_args(argv):
    parser = argparse.ArgumentParser(description="Seal or validate a run-scoped QA context capsule")
    parser.add_argument("command", choices=("seal", "validate"))
    parser.add_argument("--capsule", required=True, help="revision-bound capsule output/input path")
    parser.add_argument("--draft", help="separate draft path for safe idempotence/conflict checks during seal")
    parser.add_argument("--qa-home", help="QA home for central source freshness checks")
    parser.add_argument("--run-dir", help="run directory for path and embedded intake/readiness checks")
    args = parser.parse_args(argv)
    if args.command != "seal" and args.draft:
        parser.error("--draft is only valid with seal")
    return args


def main(argv=None):
    args = parse_args(argv)
    try:
        input_path = args.draft if args.command == "seal" and args.draft else args.capsule
        capsule = load_capsule(input_path)
        qa_home = str(Path(args.qa_home).resolve()) if args.qa_home else None
        run_dir = str(Path(args.run_dir).resolve()) if args.run_dir else None
        if args.command == "seal":
            digest = seal_capsule(capsule, args.capsule, qa_home, run_dir, input_path)
            print(f"sealed {args.capsule} payload_sha256={digest}")
        else:
            validate_capsule(capsule, args.capsule, qa_home, run_dir)
            print(f"valid {args.capsule}")
        return 0
    except CapsuleError as exc:
        print(f"{exc.code}: {exc}", file=sys.stderr)
        return exc.exit_code


if __name__ == "__main__":
    sys.exit(main())

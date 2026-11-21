#!/usr/bin/env bash
# SPDX-License-Identifier: MIT AND Apache-2.0
# Copyright (c) 2026 Ivan Davidov and Agentic Playwright contributors
# Copyright (c) 2026 Sn4kyGit and qa-agent-blueprint contributors
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCANNER="$HERE/../scripts/qa-test-code-scan.mjs"
if [ ! -f "$SCANNER" ] && [ -f "$HERE/../../scripts/qa-test-code-scan.mjs" ]; then
  SCANNER="$HERE/../../scripts/qa-test-code-scan.mjs"
fi

exec node --input-type=module -e '
import { readFileSync } from "node:fs";
import { isAbsolute, resolve } from "node:path";
import { pathToFileURL } from "node:url";
const { loadQualityConfig, scanTestCode } = await import(pathToFileURL(process.argv[1]).href);
let payload;
try { payload = JSON.parse(readFileSync(0, "utf8")); } catch { process.exit(0); }
const tool = payload.tool_name || "";
if (!["Write", "Edit", "MultiEdit", "NotebookEdit"].includes(tool)) process.exit(0);
const input = payload.tool_input || {};
const supplied = input.file_path || input.filePath || input.notebook_path || input.notebookPath || "";
if (!supplied) process.exit(0);
const cwd = payload.cwd || process.cwd();
const filePath = isAbsolute(supplied) ? supplied : resolve(cwd, supplied);
if (!/\.(?:[cm]?[jt]sx?|ipynb)$/i.test(filePath)) process.exit(0);
const config = loadQualityConfig(filePath);
if (config.writeGate !== true) process.exit(0);
let content;
if (tool === "Write") content = input.content;
else if (tool === "Edit") content = input.new_string ?? input.newString ?? "";
else if (tool === "MultiEdit") content = Array.isArray(input.edits) ? input.edits.map((edit) => edit.new_string ?? edit.newString ?? "").join("\n") : undefined;
else content = input.new_source ?? input.newSource ?? input.content ?? "";
if (typeof content !== "string") {
  process.stderr.write("BLOCKED by pre-test-code-scan: malformed write payload while the quality write gate is active.\n");
  process.exit(2);
}
const report = scanTestCode(content, { filePath, fragment: tool !== "Write", config });
const diagnostics = report.diagnostics.filter((item) => item.severity === "error");
const blocking = report.findings.filter((item) => item.severity === "error" || config.strict);
if (diagnostics.length || blocking.length) {
  process.stderr.write(`BLOCKED by pre-test-code-scan: ${blocking.length + diagnostics.length} quality issue(s) in ${filePath}.\n`);
  for (const item of [...blocking, ...diagnostics]) process.stderr.write(`${item.severity} ${item.ruleId} ${item.file}:${item.line}:${item.column} ${item.message}\n`);
  process.exit(2);
}
for (const item of [...report.findings, ...report.diagnostics]) process.stderr.write(`${item.severity} ${item.ruleId} ${item.file}:${item.line}:${item.column} ${item.message}\n`);
process.exit(0);
' "$SCANNER"

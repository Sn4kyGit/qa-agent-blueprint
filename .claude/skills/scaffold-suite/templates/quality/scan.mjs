import { spawnSync } from 'node:child_process';
import { statSync } from 'node:fs';
import { dirname, isAbsolute, resolve } from 'node:path';

const candidates = [];
if (process.env.QA_TEST_CODE_SCANNER) candidates.push(process.env.QA_TEST_CODE_SCANNER);
if (process.env.CLAUDE_PLUGIN_ROOT) candidates.push(resolve(process.env.CLAUDE_PLUGIN_ROOT, '.claude/scripts/qa-test-code-scan.mjs'));
for (let dir = process.cwd(); ; dir = dirname(dir)) {
  candidates.push(resolve(dir, '.claude/scripts/qa-test-code-scan.mjs'));
  if (dir === dirname(dir)) break;
}
const scanner = candidates.find((candidate) => {
  try {
    return statSync(isAbsolute(candidate) ? candidate : resolve(candidate)).isFile();
  } catch {
    return false;
  }
});
if (!scanner) {
  process.stderr.write('quality scan: set QA_TEST_CODE_SCANNER to the blueprint .claude/scripts/qa-test-code-scan.mjs path.\n');
  process.exit(2);
}
const result = spawnSync(process.execPath, [scanner, ...process.argv.slice(2)], { stdio: 'inherit', shell: false });
process.exit(result.status ?? 2);

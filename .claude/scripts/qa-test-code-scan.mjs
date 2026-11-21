#!/usr/bin/env node
// SPDX-License-Identifier: MIT AND Apache-2.0
// Copyright (c) 2026 Ivan Davidov and Agentic Playwright contributors
// Copyright (c) 2026 Sn4kyGit and qa-agent-blueprint contributors
import { spawnSync } from 'node:child_process';
import { readFileSync, readdirSync, realpathSync, statSync } from 'node:fs';
import { dirname, extname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

export const SCAN_VERSION = 1;

const CONFIG_NAME = '.qa-test-quality.json';
const SOURCE_RE = /\.[cm]?[jt]sx?$/i;
const SPEC_RE = /\.(?:spec|test)\.[cm]?[jt]sx?$/i;
const SKIPPED_DIRS = new Set(['.git', 'node_modules', 'evidence', 'test-results', 'playwright-report', 'dist', 'build']);
const TICKET_RE = /\b[A-Z][A-Z0-9]+-\d+\b/;
const AC_RE = /\bAC-?\d+\b/;
const TC_RE = /\bTC-[A-Z][A-Z0-9]*-\d+\b/;
const URL_RE = /^https?:\/\//i;

const DEFAULT_RULES = Object.freeze({
  'no-dotenv': 'warning',
  'fixed-sleep': 'warning',
  'hardcoded-base-url': 'warning',
  'xpath-selector': 'warning',
  'brittle-selector': 'warning',
  'observation-fixture-import': 'warning',
  'missing-ac-title': 'warning',
  'missing-tc-title': 'warning',
  'disabled-test': 'warning',
  'retry-override': 'warning',
});

const RULE_MESSAGES = Object.freeze({
  'no-dotenv': 'Use explicit environment injection such as qa-secrets instead of loading dotenv.',
  'fixed-sleep': 'Replace the fixed sleep with a condition-based wait.',
  'hardcoded-base-url': 'Read the base URL from environment configuration instead of a source literal.',
  'xpath-selector': 'Replace the XPath selector with a role, label, test ID, or other stable locator.',
  'brittle-selector': 'Replace the position- or implementation-dependent selector with a stable locator.',
  'observation-fixture-import': 'Import test/expect from the suite observation fixture instead of @playwright/test.',
  'missing-ac-title': 'Bind the test title to a real acceptance criterion ID such as AC2.',
  'missing-tc-title': 'Add the persistent test case ID such as TC-CHK-014 to the test title.',
  'disabled-test': 'Document both the disabling reason and its tracking ticket.',
  'retry-override': 'Do not override the suite retry policy from an individual test or static config.',
});

function diagnostic(file, message, line = 0, severity = 'error') {
  return { ruleId: 'diagnostic', severity, file, line, column: line ? 1 : 0, message };
}

function defaultConfig(overrides = {}) {
  const strict = overrides.strict === true;
  return {
    version: SCAN_VERSION,
    writeGate: overrides.writeGate === true,
    strict,
    framework: overrides.framework || 'auto',
    rules: { ...DEFAULT_RULES, ...(overrides.rules || {}) },
    configPath: overrides.configPath || null,
    diagnostics: overrides.diagnostics || [],
  };
}

function configDirectory(startPath) {
  let value = resolve(startPath || process.cwd());
  try {
    if (statSync(value).isFile()) return dirname(value);
  } catch {
    if (SOURCE_RE.test(value) || extname(value) === '.json') return dirname(value);
  }
  return value;
}

export function loadQualityConfig(startPath = process.cwd(), overrides = {}) {
  let dir = configDirectory(startPath);
  let configPath = null;
  for (;;) {
    const candidate = join(dir, CONFIG_NAME);
    try {
      if (statSync(candidate).isFile()) {
        configPath = candidate;
        break;
      }
    } catch {
    }
    const parent = dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  if (!configPath) return defaultConfig(overrides);
  let parsed;
  try {
    parsed = JSON.parse(readFileSync(configPath, 'utf8'));
  } catch {
    return defaultConfig({
      ...overrides,
      configPath,
      diagnostics: [diagnostic(configPath, 'Quality config is not valid JSON; defaults are active.')],
    });
  }
  if (!parsed || Array.isArray(parsed) || typeof parsed !== 'object') {
    return defaultConfig({
      ...overrides,
      configPath,
      diagnostics: [diagnostic(configPath, 'Quality config must be a JSON object; defaults are active.')],
    });
  }
  const diagnostics = [];
  if (parsed.version !== undefined && parsed.version !== SCAN_VERSION) {
    diagnostics.push(diagnostic(configPath, `Quality config version must be ${SCAN_VERSION}.`));
  }
  for (const key of ['strict', 'writeGate']) {
    if (parsed[key] !== undefined && typeof parsed[key] !== 'boolean') {
      diagnostics.push(diagnostic(configPath, `Quality config ${key} must be boolean; false is used.`));
    }
  }
  if (parsed.framework !== undefined && !['auto', 'playwright', 'webdriverio'].includes(parsed.framework)) {
    diagnostics.push(diagnostic(configPath, 'Quality config framework must be playwright, webdriverio, or auto.'));
  }
  const rules = { ...DEFAULT_RULES };
  if (parsed.rules !== undefined && (!parsed.rules || Array.isArray(parsed.rules) || typeof parsed.rules !== 'object')) {
    diagnostics.push(diagnostic(configPath, 'Quality config rules must be an object; defaults are used.'));
  } else {
    for (const [ruleId, severity] of Object.entries(parsed.rules || {})) {
      if (!Object.hasOwn(DEFAULT_RULES, ruleId)) {
        diagnostics.push(diagnostic(configPath, `Unknown quality rule ${ruleId} is ignored.`, 0, 'warning'));
      } else if (!['error', 'warning', 'off'].includes(severity)) {
        diagnostics.push(diagnostic(configPath, `Quality rule ${ruleId} must be error, warning, or off; its default is used.`));
      } else {
        rules[ruleId] = severity;
      }
    }
  }
  return defaultConfig({
    ...overrides,
    strict: parsed.strict === true || overrides.strict === true,
    writeGate: parsed.writeGate === true,
    framework: ['playwright', 'webdriverio', 'auto'].includes(parsed.framework) ? parsed.framework : (overrides.framework || 'auto'),
    rules: { ...rules, ...(overrides.rules || {}) },
    configPath,
    diagnostics,
  });
}

function advancePosition(text, state) {
  for (const char of text) {
    if (char === '\n') {
      state.line += 1;
      state.column = 1;
    } else {
      state.column += 1;
    }
  }
  state.index += text.length;
}

function lex(source) {
  const tokens = [];
  const comments = [];
  const diagnostics = [];
  const state = { index: 0, line: 1, column: 1 };
  while (state.index < source.length) {
    const char = source[state.index];
    if (/\s/.test(char)) {
      advancePosition(char, state);
      continue;
    }
    const start = { index: state.index, line: state.line, column: state.column };
    if (char === '/' && source[state.index + 1] === '/') {
      const end = source.indexOf('\n', state.index + 2);
      const stop = end < 0 ? source.length : end;
      const text = source.slice(state.index + 2, stop);
      comments.push({ text, line: start.line, endLine: start.line });
      advancePosition(source.slice(state.index, stop), state);
      continue;
    }
    if (char === '/' && source[state.index + 1] === '*') {
      const end = source.indexOf('*/', state.index + 2);
      const stop = end < 0 ? source.length : end + 2;
      const raw = source.slice(state.index, stop);
      const text = end < 0 ? source.slice(state.index + 2) : source.slice(state.index + 2, end);
      advancePosition(raw, state);
      comments.push({ text, line: start.line, endLine: state.line });
      if (end < 0) diagnostics.push(diagnostic('<input>', 'Unterminated block comment.', start.line, 'warning'));
      continue;
    }
    if (char === "'" || char === '"') {
      let cursor = state.index + 1;
      let value = '';
      let closed = false;
      while (cursor < source.length) {
        const current = source[cursor];
        if (current === char) {
          closed = true;
          cursor += 1;
          break;
        }
        if (current === '\n' || current === '\r') break;
        if (current === '\\' && cursor + 1 < source.length) {
          const escaped = source[cursor + 1];
          const escapes = { n: '\n', r: '\r', t: '\t' };
          value += escapes[escaped] ?? escaped;
          cursor += 2;
        } else {
          value += current;
          cursor += 1;
        }
      }
      const raw = source.slice(state.index, cursor);
      tokens.push({ type: 'string', value, ...start });
      advancePosition(raw, state);
      if (!closed) diagnostics.push(diagnostic('<input>', 'Unterminated string literal.', start.line, 'warning'));
      continue;
    }
    if (char === '`') {
      let cursor = state.index + 1;
      let value = '';
      let closed = false;
      let dynamic = false;
      while (cursor < source.length) {
        const current = source[cursor];
        if (current === '`') {
          closed = true;
          cursor += 1;
          break;
        }
        if (current === '\\' && cursor + 1 < source.length) {
          value += source[cursor + 1];
          cursor += 2;
          continue;
        }
        if (current === '$' && source[cursor + 1] === '{') dynamic = true;
        value += current;
          cursor += 1;
      }
      const raw = source.slice(state.index, cursor);
      tokens.push({ type: dynamic ? 'dynamic' : 'string', value, ...start });
      advancePosition(raw, state);
      if (!closed) diagnostics.push(diagnostic('<input>', 'Unterminated template literal.', start.line, 'warning'));
      continue;
    }
    if (/[A-Za-z_$#]/.test(char)) {
      let cursor = state.index + 1;
      while (cursor < source.length && /[A-Za-z0-9_$#-]/.test(source[cursor])) cursor += 1;
      const raw = source.slice(state.index, cursor);
      tokens.push({ type: 'identifier', value: raw, ...start });
      advancePosition(raw, state);
      continue;
    }
    if (/\d/.test(char)) {
      let cursor = state.index + 1;
      while (cursor < source.length && /[\d_.]/.test(source[cursor])) cursor += 1;
      const raw = source.slice(state.index, cursor);
      tokens.push({ type: 'number', value: raw, ...start });
      advancePosition(raw, state);
      continue;
    }
    const punctuation = ['=>', '?.', '...', '===', '!==', '==', '!=', '<=', '>=', '&&', '||', '??'].find((item) => source.startsWith(item, state.index)) || char;
    tokens.push({ type: 'punct', value: punctuation, ...start });
    advancePosition(punctuation, state);
  }
  return { tokens, comments, diagnostics };
}

function matchingPairs(tokens) {
  const pairs = new Map();
  const stack = [];
  const expected = { ')': '(', ']': '[', '}': '{' };
  tokens.forEach((token, index) => {
    if (['(', '[', '{'].includes(token.value)) stack.push({ value: token.value, index });
    if (expected[token.value]) {
      for (let cursor = stack.length - 1; cursor >= 0; cursor -= 1) {
        if (stack[cursor].value === expected[token.value]) {
          const open = stack[cursor];
          stack.splice(cursor, 1);
          pairs.set(open.index, index);
          pairs.set(index, open.index);
          break;
        }
      }
    }
  });
  return pairs;
}

function calleeAt(tokens, openIndex) {
  const parts = [];
  let cursor = openIndex - 1;
  let expectIdentifier = true;
  let start = openIndex;
  while (cursor >= 0) {
    const token = tokens[cursor];
    if (expectIdentifier && token.type === 'identifier') {
      parts.unshift(token.value);
      start = cursor;
      expectIdentifier = false;
    } else if (!expectIdentifier && ['.', '?.'].includes(token.value)) {
      expectIdentifier = true;
    } else {
      break;
    }
    cursor -= 1;
  }
  return { name: parts.join('.'), start, end: openIndex - 1 };
}

function staticValue(token) {
  return token?.type === 'string' ? token.value : null;
}

function numericValue(token) {
  if (!token || token.type !== 'number') return null;
  const value = Number(token.value.replaceAll('_', ''));
  return Number.isFinite(value) ? value : null;
}

function isSpecFile(file) {
  return SPEC_RE.test(file) || /(^|[/\\])(?:tests?|specs?|e2e)([/\\]|$)/i.test(file);
}

function isInfrastructureFile(file) {
  return /(^|[/\\])(?:fixtures?|pages?|support|probes?)([/\\]|$)/i.test(file)
    || /(?:playwright\.config|wdio\.conf|\.config)\.[cm]?[jt]s$/i.test(file);
}

function hasTrackingTicket(value) {
  return TICKET_RE.test(String(value || '').replace(TC_RE, '').replace(AC_RE, ''));
}

function normalizeFramework(value) {
  return value === 'wdio' ? 'webdriverio' : value;
}

function sourceConfig(options, file) {
  const base = options.config && typeof options.config === 'object'
    ? defaultConfig({ ...options.config, strict: options.strict === true || options.config.strict === true, framework: options.framework || options.config.framework })
    : options.config === false
      ? defaultConfig(options)
      : loadQualityConfig(isAbsolute(file) ? file : resolve(options.cwd || process.cwd(), file), options);
  return { ...base, strict: base.strict || options.strict === true, framework: normalizeFramework(options.framework || base.framework || 'auto') };
}

function findingLocation(tokens, index) {
  const token = tokens[index] || tokens[0];
  return { line: token?.line || 1, column: token?.column || 1 };
}

function applySuppressions(findings, comments, file, enabled) {
  if (!enabled) return { findings, suppressed: [], diagnostics: [] };
  const directives = [];
  const diagnostics = [];
  for (const comment of comments) {
    const match = comment.text.match(/qa-(?:scan|test-code)-disable(-next-line)?\b([\s\S]*)/);
    if (!match) continue;
    const body = match[2];
    const separator = body.indexOf('--');
    const ruleText = (separator < 0 ? body : body.slice(0, separator)).trim();
    const reason = separator < 0 ? '' : body.slice(separator + 2).trim();
    const ruleIds = ruleText.split(/[\s,]+/).filter(Boolean);
    const targetLine = match[1] ? comment.endLine + 1 : comment.line;
    if (!ruleIds.length || reason.length < 8 || ruleIds.some((id) => id !== 'all' && !Object.hasOwn(DEFAULT_RULES, id))) {
      diagnostics.push(diagnostic(file, 'Ignored suppression: name valid rules and add a reason of at least 8 characters after --.', comment.line, 'warning'));
      continue;
    }
    directives.push({ line: targetLine, ruleIds, commentLine: comment.line });
  }
  const findingsOut = [];
  const suppressed = [];
  for (const item of findings) {
    const directive = directives.find((candidate) => candidate.line === item.line && (candidate.ruleIds.includes('all') || candidate.ruleIds.includes(item.ruleId)));
    if (directive) suppressed.push({ ...item, suppressionLine: directive.commentLine });
    else findingsOut.push(item);
  }
  return { findings: findingsOut, suppressed, diagnostics };
}

function compareItems(a, b) {
  return String(a.file).localeCompare(String(b.file))
    || (a.line || 0) - (b.line || 0)
    || (a.column || 0) - (b.column || 0)
    || String(a.ruleId).localeCompare(String(b.ruleId))
    || String(a.message).localeCompare(String(b.message));
}

function makeReport(findings, suppressed, diagnostics, config, files = 1) {
  findings.sort(compareItems);
  suppressed.sort(compareItems);
  diagnostics.sort(compareItems);
  const errors = findings.filter((item) => item.severity === 'error').length;
  const warnings = findings.length - errors;
  return {
    version: SCAN_VERSION,
    findings,
    suppressed,
    diagnostics,
    summary: { files, findings: findings.length, errors, warnings, suppressed: suppressed.length, diagnostics: diagnostics.length },
    config: { path: config.configPath || null, writeGate: config.writeGate === true, strict: config.strict === true, framework: config.framework || 'auto' },
  };
}

export function scanTestCode(source, options = {}, extraOptions = {}) {
  if (typeof options === 'string') options = { ...extraOptions, filePath: options };
  if (typeof source !== 'string') throw new TypeError('scanTestCode source must be a string');
  const file = options.filePath || options.path || '<stdin>';
  const config = sourceConfig(options, file);
  const { tokens, comments, diagnostics: lexDiagnostics } = lex(source);
  const pairs = matchingPairs(tokens);
  const findings = [];
  const specFile = SPEC_RE.test(file)
    ? !/(^|[/\\])probes?([/\\]|$)/i.test(file)
    : isSpecFile(file) && !isInfrastructureFile(file);
  const configFile = /(?:playwright\.config|wdio\.conf)/i.test(file);
  const add = (ruleId, index, confidence = 'high', message = RULE_MESSAGES[ruleId]) => {
    const configured = config.rules[ruleId] || 'warning';
    if (configured === 'off') return;
    const severity = confidence === 'high' ? configured : 'warning';
    findings.push({ ruleId, severity, confidence, file, ...findingLocation(tokens, index), message });
  };

  for (let index = 0; index < tokens.length; index += 1) {
    const token = tokens[index];
    if (token.value === 'import') {
      const end = tokens.slice(index + 1, index + 30).findIndex((item) => item.value === ';');
      const limit = end < 0 ? Math.min(tokens.length, index + 30) : index + 1 + end;
      const moduleIndex = tokens.findIndex((item, cursor) => cursor > index && cursor < limit && item.type === 'string');
      const moduleName = staticValue(tokens[moduleIndex]);
      if (moduleName === 'dotenv' || moduleName === 'dotenv/config') add('no-dotenv', index);
      if (moduleName === '@playwright/test' && specFile && config.framework !== 'webdriverio') {
        const imported = tokens.slice(index + 1, moduleIndex).map((item) => item.value);
        if (imported.includes('test') || imported.includes('expect')) add('observation-fixture-import', index);
      }
    }
    if (token.value === 'require' && tokens[index + 1]?.value === '(') {
      const moduleName = staticValue(tokens[index + 2]);
      if (moduleName === 'dotenv' || moduleName === 'dotenv/config') add('no-dotenv', index);
      if (moduleName === '@playwright/test' && specFile && config.framework !== 'webdriverio') add('observation-fixture-import', index);
    }
    if (token.value === 'dotenv' && tokens[index + 1]?.value === '.' && tokens[index + 2]?.value === 'config') add('no-dotenv', index);
    if (token.type === 'string' && URL_RE.test(token.value)) {
      const previous = tokens[index - 1];
      const beforePrevious = tokens[index - 2];
      if (previous?.value === ':' && beforePrevious?.type === 'identifier' && /^(?:baseURL|baseUrl|STAGE_BASE_URL|APP_BASE_URL)$/i.test(beforePrevious.value)) {
        add('hardcoded-base-url', beforePrevious);
      }
      if (previous?.value === '=' && beforePrevious?.type === 'identifier' && /(?:BASE_?URL|STAGE_?URL|APP_?URL|HOST)$/i.test(beforePrevious.value)) {
        add('hardcoded-base-url', beforePrevious);
      }
    }
    if (token.value !== '(' || !pairs.has(index)) continue;
    const callee = calleeAt(tokens, index);
    const close = pairs.get(index);
    const args = tokens.slice(index + 1, close);
    const first = args[0];
    const firstValue = staticValue(first);
    const leaf = callee.name.split('.').pop();
    if (['waitForTimeout', 'pause'].includes(leaf)) {
      if (numericValue(first) !== null) add('fixed-sleep', callee.start);
      else if (first && first.value !== ')') add('fixed-sleep', callee.start, 'medium', 'Verify that this dynamic duration is not a fixed sleep; prefer a condition-based wait.');
    }
    if (['goto', 'url', 'get', 'post', 'put', 'patch', 'delete', 'fetch'].includes(leaf) && firstValue && URL_RE.test(firstValue)) {
      add('hardcoded-base-url', callee.start);
    }
    if (['locator', '$', '$$'].includes(leaf) && firstValue) {
      if (/^(?:xpath=|\/\/|\/html\b|\.\.\/)/i.test(firstValue.trim())) add('xpath-selector', callee.start);
      if (/:nth-(?:last-)?(?:child|of-type)\(|>>\s*nth=|(?:>\s*)?[a-z0-9_-]+\s*>\s*[a-z0-9_-]+\s*>\s*[a-z0-9_-]+/i.test(firstValue)) {
        add('brittle-selector', callee.start);
      } else if (/\[(?:class|id)\s*[*^$]?=\s*['"]?(?:css-|Mui|emotion-|sc-|[a-z]+-[a-f0-9]{6,})/i.test(firstValue)) {
        add('brittle-selector', callee.start);
      }
    }
    if (leaf === 'nth' && numericValue(first) !== null) add('brittle-selector', callee.start, 'medium', 'Prefer a semantic locator over a positional nth() selection when possible.');
    if (leaf === 'setTimeout' && numericValue(args[2]) !== null) {
      const prefix = tokens.slice(Math.max(0, callee.start - 16), callee.start).map((item) => item.value);
      if (prefix.includes('Promise') && prefix.includes('await')) add('fixed-sleep', callee.start);
    }
    if (leaf === 'retries' && numericValue(first) > 0) add('retry-override', callee.start);
    if (callee.name.endsWith('describe.configure') || callee.name === 'test.use') {
      for (let cursor = 0; cursor < args.length - 2; cursor += 1) {
        if (args[cursor].value === 'retries' && args[cursor + 1].value === ':' && numericValue(args[cursor + 2]) > 0) {
          add('retry-override', index + 1 + cursor);
        }
      }
    }

    const isTest = /^(?:test|it)(?:\.[A-Za-z]+)*$/.test(callee.name) && !callee.name.includes('describe');
    const isXTest = ['xtest', 'xit'].includes(callee.name);
    if (callee.name === 'test.skip' && !firstValue) continue;
    if ((!isTest && !isXTest) || !first) continue;
    const modifiers = callee.name.split('.').slice(1);
    const disabled = isXTest || modifiers.some((modifier) => ['skip', 'fixme', 'todo'].includes(modifier));
    const title = firstValue;
    if (specFile && !options.fragment) {
      if (!title || !AC_RE.test(title)) add('missing-ac-title', callee.start, title ? 'high' : 'low', title ? RULE_MESSAGES['missing-ac-title'] : 'Use a static title with a real acceptance criterion ID; this title is dynamic or missing.');
      if (!title || !TC_RE.test(title)) add('missing-tc-title', callee.start, title ? 'high' : 'low', title ? RULE_MESSAGES['missing-tc-title'] : 'Use a static title with a persistent test case ID; this title is dynamic or missing.');
    }
    if (disabled) {
      const localComments = comments.filter((comment) => Math.abs(comment.line - tokens[callee.start].line) <= 2 || Math.abs(comment.endLine - tokens[callee.start].line) <= 2);
      const commentText = localComments.map((comment) => comment.text).join(' ');
      const reasonInTitle = /\b(?:because|reason|blocked|upstream|quarantine)\b/i.test(title || '');
      const reasonInComments = /\b(?:because|reason|blocked|upstream|quarantine|until)\b/i.test(commentText);
      const ticket = hasTrackingTicket(title) || hasTrackingTicket(commentText);
      const missing = [];
      if (!reasonInTitle && !reasonInComments) missing.push('reason');
      if (!ticket) missing.push('ticket');
      if (missing.length) add('disabled-test', callee.start, 'high', `Disabled test is missing ${missing.join(' and ')}; add a reason and tracking ticket.`);
    }
  }

  for (let index = 0; index < tokens.length; index += 1) {
    const token = tokens[index];
    if (token.value === 'test' && tokens[index + 1]?.value === '.' && tokens[index + 2]?.value === 'skip') {
      const open = index + 3;
      if (tokens[open]?.value !== '(' || calleeAt(tokens, open).name !== 'test.skip') continue;
      const previous = tokens[index - 1];
      if (previous && ['.', 'identifier'].includes(previous.type) && previous.value !== ';') {
        if (previous.type === 'identifier' || previous.value === '.') continue;
      }
      if (staticValue(tokens[open + 1]) !== null) continue;
      const close = pairs.get(open);
      if (close === undefined) continue;
      const args = tokens.slice(open + 1, close);
      const reasonText = args[1]?.value === ',' ? staticValue(args[2]) : null;
      const reason = typeof reasonText === 'string' && reasonText.trim().length >= 8;
      const line = token.line;
      const commentText = comments.filter((comment) => Math.abs(comment.line - line) <= 2).map((comment) => comment.text).join(' ');
      const ticket = hasTrackingTicket(commentText) || hasTrackingTicket(reasonText);
      if (!reason || !ticket) {
        const missing = [!reason ? 'reason' : null, !ticket ? 'ticket' : null].filter(Boolean).join(' and ');
        add('disabled-test', index, 'high', `Disabled test is missing ${missing}; add a reason and tracking ticket.`);
      }
    }
  }

  if (configFile) {
    for (let index = 0; index < tokens.length - 2; index += 1) {
      if (!['retries', 'specFileRetries'].includes(tokens[index].value) || tokens[index + 1]?.value !== ':') continue;
      if (numericValue(tokens[index + 2]) > 0) add('retry-override', index);
    }
  }

  const unique = [...new Map(findings.map((item) => [[item.ruleId, item.line, item.column, item.message].join('|'), item])).values()];
  const suppressionResult = applySuppressions(unique, comments, file, options.noSuppressions !== true);
  const diagnostics = [...(config.diagnostics || []), ...lexDiagnostics.map((item) => ({ ...item, file })), ...suppressionResult.diagnostics];
  return makeReport(suppressionResult.findings, suppressionResult.suppressed, diagnostics, config);
}

function supportedFile(file) {
  return SOURCE_RE.test(file) && !/\.d\.[cm]?ts$/i.test(file);
}

function collectPaths(inputPaths, cwd) {
  const files = [];
  const diagnostics = [];
  const visit = (pathValue) => {
    let stats;
    try {
      stats = statSync(pathValue);
    } catch {
      diagnostics.push(diagnostic(pathValue, 'Path cannot be read.'));
      return;
    }
    if (stats.isFile()) {
      if (supportedFile(pathValue)) files.push(pathValue);
      return;
    }
    if (!stats.isDirectory()) return;
    let entries;
    try {
      entries = readdirSync(pathValue, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name));
    } catch {
      diagnostics.push(diagnostic(pathValue, 'Directory cannot be read.'));
      return;
    }
    for (const entry of entries) {
      if (entry.isDirectory() && SKIPPED_DIRS.has(entry.name)) continue;
      if (entry.isSymbolicLink()) continue;
      visit(join(pathValue, entry.name));
    }
  };
  for (const input of inputPaths) visit(isAbsolute(input) ? input : resolve(cwd, input));
  return { files: [...new Set(files)].sort(), diagnostics };
}

function git(cwd, args, input) {
  return spawnSync('git', args, { cwd, input, encoding: 'buffer', maxBuffer: 64 * 1024 * 1024, shell: false, windowsHide: true });
}

function stagedSources(cwd) {
  const listed = git(cwd, ['diff', '--cached', '--name-only', '--diff-filter=ACMR', '-z']);
  if (listed.status !== 0) return { sources: [], diagnostics: [diagnostic(cwd, 'Cannot list staged files; run inside a git work tree.')] };
  const paths = listed.stdout.toString('utf8').split('\0').filter(Boolean);
  const sources = [];
  const diagnostics = [];
  for (const file of paths.filter(supportedFile).sort()) {
    if (file.split(/[\\/]/).some((part) => SKIPPED_DIRS.has(part))) continue;
    const blob = git(cwd, ['cat-file', 'blob', `:${file}`]);
    if (blob.status !== 0) {
      diagnostics.push(diagnostic(file, 'Staged blob cannot be read.'));
      continue;
    }
    sources.push({ filePath: file.split(sep).join('/'), source: blob.stdout.toString('utf8') });
  }
  return { sources, diagnostics };
}

function mergeReports(reports, config) {
  const findings = reports.flatMap((report) => report.findings);
  const suppressed = reports.flatMap((report) => report.suppressed);
  const diagnostics = reports.flatMap((report) => report.diagnostics);
  const files = reports.reduce((total, report) => total + report.summary.files, 0);
  const configShapes = [...new Set(reports.map((report) => JSON.stringify(report.config)))];
  const effective = configShapes.length === 1
    ? {
        configPath: reports[0].config.path,
        writeGate: reports[0].config.writeGate,
        strict: reports[0].config.strict,
        framework: reports[0].config.framework,
      }
    : { ...config, strict: config.strict || reports.some((report) => report.config.strict) };
  return makeReport(findings, suppressed, diagnostics, effective, files);
}

export function scanTestFiles(paths = [], options = {}) {
  if (!Array.isArray(paths)) {
    options = paths || {};
    paths = [];
  }
  const cwd = resolve(options.cwd || process.cwd());
  const config = defaultConfig({ strict: options.strict === true, framework: normalizeFramework(options.framework || 'auto'), writeGate: false });
  if (options.staged) {
    const staged = stagedSources(cwd);
    const reports = staged.sources.map((item) => scanTestCode(item.source, { ...options, cwd, filePath: item.filePath }));
    const merged = mergeReports(reports, config);
    merged.diagnostics.push(...staged.diagnostics);
    const effective = { configPath: merged.config.path, writeGate: merged.config.writeGate, strict: merged.config.strict, framework: merged.config.framework };
    return makeReport(merged.findings, merged.suppressed, merged.diagnostics, effective, merged.summary.files);
  }
  const collected = collectPaths(paths, cwd);
  const reports = collected.files.map((filePath) => {
    try {
      return scanTestCode(readFileSync(filePath, 'utf8'), { ...options, cwd, filePath: relative(cwd, filePath).split(sep).join('/') || filePath });
    } catch {
      return makeReport([], [], [diagnostic(filePath, 'Source file cannot be read as UTF-8 text.')], config, 0);
    }
  });
  const merged = mergeReports(reports, config);
  merged.diagnostics.push(...collected.diagnostics);
  const effective = { configPath: merged.config.path, writeGate: merged.config.writeGate, strict: merged.config.strict, framework: merged.config.framework };
  return makeReport(merged.findings, merged.suppressed, merged.diagnostics, effective, merged.summary.files);
}

function usage() {
  return [
    'Usage: node qa-test-code-scan.mjs [options] <path...>',
    'Options:',
    '  --format text|json          Output format (default: text)',
    '  --strict                    Any unsuppressed finding exits 1',
    '  --framework NAME            playwright or webdriverio',
    '  --no-suppressions           Ignore inline suppression directives',
    '  --stdin <path>              Scan stdin as the supplied source path',
    '  --fragment                  Scan a source fragment without file-level metadata rules',
    '  --staged                    Scan staged git blobs instead of working-tree files',
  ].join('\n');
}

function parseCli(argv) {
  const options = { format: 'text', paths: [] };
  let positional = false;
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (positional) {
      options.paths.push(arg);
      continue;
    }
    if (arg === '--') {
      positional = true;
    } else if (arg === '--strict') {
      options.strict = true;
    } else if (arg === '--no-suppressions') {
      options.noSuppressions = true;
    } else if (arg === '--fragment') {
      options.fragment = true;
    } else if (arg === '--staged') {
      options.staged = true;
    } else if (arg === '--help' || arg === '-h') {
      options.help = true;
    } else if (arg === '--format' || arg === '--framework' || arg === '--stdin') {
      const value = argv[++index];
      if (!value) throw new Error(`${arg} requires a value`);
      if (arg === '--format') options.format = value;
      if (arg === '--framework') options.framework = normalizeFramework(value);
      if (arg === '--stdin') options.stdin = value;
    } else if (arg.startsWith('--format=')) {
      options.format = arg.slice('--format='.length);
    } else if (arg.startsWith('--framework=')) {
      options.framework = normalizeFramework(arg.slice('--framework='.length));
    } else if (arg.startsWith('--stdin=')) {
      options.stdin = arg.slice('--stdin='.length);
    } else if (arg.startsWith('-')) {
      throw new Error(`Unknown option: ${arg}`);
    } else {
      options.paths.push(arg);
    }
  }
  if (!['text', 'json'].includes(options.format)) throw new Error('--format must be text or json');
  if (options.framework && !['playwright', 'webdriverio'].includes(options.framework)) throw new Error('--framework must be playwright or webdriverio');
  const modes = [options.staged, Boolean(options.stdin), options.paths.length > 0].filter(Boolean).length;
  if (!options.help && modes !== 1) throw new Error('Choose exactly one input mode: paths, --stdin <path>, or --staged');
  return options;
}

function safeText(value) {
  return String(value).replace(/[\r\n\0]/g, ' ');
}

function textReport(report) {
  const lines = [`qa-test-code-scan v${SCAN_VERSION}`];
  for (const item of report.findings) lines.push(`${item.severity} ${item.ruleId} ${safeText(item.file)}:${item.line}:${item.column} ${item.message}`);
  for (const item of report.suppressed) lines.push(`suppressed ${item.ruleId} ${safeText(item.file)}:${item.line}:${item.column} directive line ${item.suppressionLine}`);
  for (const item of report.diagnostics) lines.push(`diagnostic ${item.severity} ${safeText(item.file)}:${item.line} ${item.message}`);
  const summary = report.summary;
  lines.push(`${summary.files} file(s), ${summary.findings} finding(s) (${summary.errors} error, ${summary.warnings} warning), ${summary.suppressed} suppressed, ${summary.diagnostics} diagnostic(s).`);
  return `${lines.join('\n')}\n`;
}

function runCli() {
  let options;
  try {
    options = parseCli(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`qa-test-code-scan: ${error.message}\n${usage()}\n`);
    process.exitCode = 2;
    return;
  }
  if (options.help) {
    process.stdout.write(`${usage()}\n`);
    return;
  }
  let report;
  if (options.stdin) {
    report = scanTestCode(readFileSync(0, 'utf8'), { ...options, filePath: options.stdin });
  } else {
    report = scanTestFiles(options.paths, options);
  }
  process.stdout.write(options.format === 'json' ? `${JSON.stringify(report, null, 2)}\n` : textReport(report));
  if (report.diagnostics.some((item) => item.severity === 'error')) process.exitCode = 2;
  else if (report.findings.some((item) => item.severity === 'error') || ((options.strict || report.config.strict) && report.findings.length)) process.exitCode = 1;
  else process.exitCode = 0;
}

const evaluatedInline = process.execArgv.some((arg) => arg === '-e' || arg === '--eval' || arg.startsWith('--eval='));
let invokedDirectly = false;
try {
  invokedDirectly = Boolean(process.argv[1]) && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url));
} catch {
}
if (!evaluatedInline && invokedDirectly) runCli();

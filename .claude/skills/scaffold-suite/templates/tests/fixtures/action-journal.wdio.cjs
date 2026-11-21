'use strict';

const { spawnSync } = require('node:child_process');

function createSeedState(env = process.env) {
  return {
    start_url: env.STAGE_BASE_URL || '/',
    state: env.QA_SEED_STATE || 'empty-cart',
    fixtures: (env.QA_SEED_FIXTURES || 'empty-cart,qa-standard').split(',').filter(Boolean),
  };
}

class WdioActionJournal {
  constructor(runId) {
    this.runId = runId;
    this.streamId = '';
    this.caseId = '';
  }

  append(event) {
    const script = process.env.QA_ACTION_JOURNAL_SCRIPT || '.claude/scripts/action-journal.py';
    const journal = process.env.QA_ACTION_JOURNAL_DIR;
    if (!journal) throw new Error('QA_ACTION_JOURNAL_DIR is required');
    const result = spawnSync('python3', [script, 'append', '--journal', journal, '--event', '-'], {
      input: JSON.stringify({ schema_version: 'qa-action-journal-event/v1', ...event }),
      encoding: 'utf8',
      env: process.env,
    });
    if (result.status !== 0) throw new Error(result.stderr || 'action journal append failed');
    return JSON.parse(result.stdout).event_id;
  }

  startStream({ build, capsuleSha256, seed }) {
    this.streamId = this.runId;
    this.append({
      stream_id: this.streamId,
      type: 'stream_start',
      payload: { framework: 'webdriverio', seed, build, capsule_sha256: capsuleSha256 },
    });
  }

  startCase({ caseId, title, acId, acSha256, tcId, tcSha256, intent, intentSha256 }) {
    this.caseId = caseId;
    this.append({
      stream_id: this.streamId,
      case_id: this.caseId,
      type: 'case_start',
      payload: {
        title,
        ac_id: acId,
        ac_sha256: acSha256,
        tc_id: tcId,
        tc_sha256: tcSha256,
        intent,
        intent_sha256: intentSha256,
      },
    });
  }

  action({ action, locator, url, value, inputRef }) {
    const payload = { action };
    if (locator) payload.locator = locator;
    if (url) payload.url = url;
    if (value !== undefined) payload.value = value;
    if (inputRef) payload.input_ref = inputRef;
    this.append({ stream_id: this.streamId, case_id: this.caseId, type: 'action', payload });
  }

  assertion({ acId, acSha256, intentSha256, assertionSha256, locator, expected, outcome }) {
    return this.append({
      stream_id: this.streamId,
      case_id: this.caseId,
      type: 'assertion',
      payload: {
        ac_id: acId,
        ac_sha256: acSha256,
        intent_sha256: intentSha256,
        assertion_sha256: assertionSha256,
        oracle: 'positive',
        locator,
        expected,
        outcome,
      },
    });
  }

  redCheck(assertionEventId, method, outcome) {
    this.append({
      stream_id: this.streamId,
      case_id: this.caseId,
      type: 'red_check',
      payload: { assertion_event_id: assertionEventId, outcome, method },
    });
  }

  endCase(status, replayable, originalVerdict) {
    this.append({
      stream_id: this.streamId,
      case_id: this.caseId,
      type: 'case_end',
      payload: { status, replayable, original_verdict: originalVerdict },
    });
  }
}

function createActionJournal(runId) {
  return new WdioActionJournal(runId);
}

module.exports = { createActionJournal, createSeedState };

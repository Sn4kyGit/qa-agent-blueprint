import { test as base, expect } from '@playwright/test';
import { spawnSync } from 'node:child_process';

export type SemanticLocator = {
  strategy: 'role' | 'label' | 'text' | 'test_id' | 'placeholder' | 'title' | 'alt';
  value: string;
  expression: string;
  name?: string;
  exact?: boolean;
};

export type SeedState = {
  start_url: string;
  state: string;
  fixtures: string[];
};

type EventInput = {
  stream_id: string;
  case_id?: string;
  type: 'stream_start' | 'case_start' | 'action' | 'assertion' | 'red_check' | 'case_end';
  payload: Record<string, unknown>;
};

export class ActionJournal {
  private streamId = '';
  private caseId = '';

  constructor(private readonly runId: string) {}

  private append(event: EventInput): string {
    const script = process.env.QA_ACTION_JOURNAL_SCRIPT ?? '.claude/scripts/action-journal.py';
    const journal = process.env.QA_ACTION_JOURNAL_DIR;
    if (!journal) throw new Error('QA_ACTION_JOURNAL_DIR is required');
    const result = spawnSync('python3', [script, 'append', '--journal', journal, '--event', '-'], {
      input: JSON.stringify({ schema_version: 'qa-action-journal-event/v1', ...event, case_id: event.case_id ?? null }),
      encoding: 'utf8',
      env: process.env,
    });
    if (result.status !== 0) throw new Error(result.stderr || 'action journal append failed');
    return JSON.parse(result.stdout).event_id as string;
  }

  startStream(input: { build: string; capsuleSha256: string; seed: SeedState }): void {
    this.streamId = this.runId;
    this.append({
      stream_id: this.streamId,
      type: 'stream_start',
      payload: {
        framework: 'playwright',
        seed: input.seed,
        build: input.build,
        capsule_sha256: input.capsuleSha256,
      },
    });
  }

  startCase(input: { caseId: string; title: string; acId: string; acSha256: string; tcId: string; tcSha256: string; intent: string; intentSha256: string }): void {
    this.caseId = input.caseId;
    this.append({
      stream_id: this.streamId,
      case_id: this.caseId,
      type: 'case_start',
      payload: {
        title: input.title,
        ac_id: input.acId,
        ac_sha256: input.acSha256,
        tc_id: input.tcId,
        tc_sha256: input.tcSha256,
        intent: input.intent,
        intent_sha256: input.intentSha256,
      },
    });
  }

  action(input: { action: 'navigate' | 'click' | 'fill' | 'select' | 'check' | 'uncheck' | 'press' | 'wait_for'; locator?: SemanticLocator; url?: string; value?: string; inputRef?: string }): void {
    const payload: Record<string, unknown> = { action: input.action };
    if (input.locator) payload.locator = input.locator;
    if (input.url) payload.url = input.url;
    if (input.value !== undefined) payload.value = input.value;
    if (input.inputRef) payload.input_ref = input.inputRef;
    this.append({ stream_id: this.streamId, case_id: this.caseId, type: 'action', payload });
  }

  assertion(input: { acId: string; acSha256: string; intentSha256: string; assertionSha256: string; locator: SemanticLocator; expected: string; outcome: 'passed' | 'failed' | 'observed' }): string {
    return this.append({
      stream_id: this.streamId,
      case_id: this.caseId,
      type: 'assertion',
      payload: {
        ac_id: input.acId,
        ac_sha256: input.acSha256,
        intent_sha256: input.intentSha256,
        assertion_sha256: input.assertionSha256,
        oracle: 'positive',
        locator: input.locator,
        expected: input.expected,
        outcome: input.outcome,
      },
    });
  }

  redCheck(assertionEventId: string, method: 'data_state' | 'assertion_inversion', outcome: 'failed' | 'passed'): void {
    this.append({
      stream_id: this.streamId,
      case_id: this.caseId,
      type: 'red_check',
      payload: { assertion_event_id: assertionEventId, outcome, method },
    });
  }

  endCase(status: 'complete' | 'incomplete', replayable: boolean, originalVerdict: 'PASS' | 'FAIL' | 'BLOCKED' | 'NEEDS_REVIEW'): void {
    this.append({
      stream_id: this.streamId,
      case_id: this.caseId,
      type: 'case_end',
      payload: { status, replayable, original_verdict: originalVerdict },
    });
  }
}

export const test = base.extend<{ actionJournal: ActionJournal; seedState: SeedState }>({
  seedState: async ({}, use) => {
    await use({
      start_url: process.env.STAGE_BASE_URL ?? '/',
      state: process.env.QA_SEED_STATE ?? 'empty-cart',
      fixtures: (process.env.QA_SEED_FIXTURES ?? 'empty-cart,qa-standard').split(',').filter(Boolean),
    });
  },
  actionJournal: async ({}, use, testInfo) => {
    await use(new ActionJournal(`${testInfo.project.name}-${testInfo.workerIndex}-${testInfo.retry}`));
  },
});

export { expect };

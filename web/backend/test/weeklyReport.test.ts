import assert from 'node:assert/strict';
import { test } from 'node:test';
import type { SavedVideoResult } from '../src/types.js';
import { createWeeklyCsv, readWeeklyReportConfig, reportDate, sendWeeklyReport, WeeklyReportError } from '../src/weeklyReport.js';

const config = readWeeklyReportConfig({
  REPORT_SMTP_HOST: 'email-smtp.ap-southeast-1.amazonaws.com',
  REPORT_SMTP_USER: 'smtp-user',
  REPORT_SMTP_PASS: 'smtp-password',
  REPORT_SMTP_FROM: 'sender@example.test',
  REPORT_TO: 'recipient@example.test',
});

const result: SavedVideoResult = {
  date: '2026-01-01', word: 'example', videoId: 'video-1', title: 'Title',
  url: 'https://example.test/video', channel: 'Channel', publishedAt: '2026-01-01T00:00:00Z',
};

async function* rows(values: SavedVideoResult[]): AsyncGenerator<SavedVideoResult> {
  yield* values;
}

test('requires a single sender and recipient and an SES endpoint', () => {
  const valid = {
    REPORT_SMTP_HOST: config.host, REPORT_SMTP_USER: config.user, REPORT_SMTP_PASS: config.password,
    REPORT_SMTP_FROM: config.from, REPORT_TO: config.to,
  };
  for (const invalid of [
    { ...valid, REPORT_SMTP_HOST: 'example.test' },
    { ...valid, REPORT_SMTP_USER: '' },
    { ...valid, REPORT_SMTP_PASS: '' },
    { ...valid, REPORT_TO: 'one@example.test,two@example.test' },
    { ...valid, REPORT_SMTP_FROM: 'sender@example.test\r\nBcc: other@example.test' },
  ]) {
    assert.throws(() => readWeeklyReportConfig(invalid), (error) =>
      error instanceof WeeklyReportError && error.code === 'INVALID_CONFIGURATION');
  }
});

test('exports every row and escapes CSV and spreadsheet formula characters', async () => {
  const csv = (await createWeeklyCsv(rows([
    { ...result, title: '=1+1', channel: 'A,"B"\nC' },
    { ...result, videoId: 'video-2', title: ' \t@formula', word: '日本語' },
  ]))).toString('utf8');
  assert.ok(csv.startsWith('\ufeffdate,keyword,video_id,title,url,channel,published_at\r\n'));
  assert.match(csv, /video-1,'=1\+1/);
  assert.match(csv, /"A,""B""\nC"/);
  assert.match(csv, /日本語,video-2,' \t@formula/);
  assert.equal((csv.match(/video-[12]/g) ?? []).length, 2);
  const empty = (await createWeeklyCsv(rows([]))).toString('utf8');
  assert.equal(empty, '\ufeffdate,keyword,video_id,title,url,channel,published_at\r\n');
});

test('uses the Tokyo date and sends one CSV attachment', async () => {
  const now = new Date('2026-03-29T15:00:00Z');
  assert.equal(reportDate(now), '2026-03-30');
  let sends = 0;
  await sendWeeklyReport(rows([result, { ...result, videoId: 'video-2' }]), config, async (message) => {
    sends += 1;
    assert.equal(message.from, config.from);
    assert.equal(message.to, config.to);
    assert.equal(message.attachments.length, 1);
    assert.equal(message.attachments[0].filename, 'youtube-results-2026-03-30.csv');
    assert.match(message.attachments[0].content.toString('utf8'), /video-1/);
    assert.match(message.attachments[0].content.toString('utf8'), /video-2/);
    return { accepted: ['recipient'], rejected: [] };
  }, now);
  assert.equal(sends, 1);
});

test('does not send partial CSVs and reports rejected mail', async () => {
  let sent = false;
  await assert.rejects(sendWeeklyReport(rows([{ ...result, title: 'x'.repeat(6 * 1024 * 1024) }]), config, async () => {
    sent = true;
    return { accepted: [], rejected: [] };
  }), (error) => error instanceof WeeklyReportError && error.code === 'CSV_TOO_LARGE');
  assert.equal(sent, false);
  await assert.rejects(sendWeeklyReport(rows([result]), config, async () => ({ accepted: [], rejected: ['recipient'] })),
    (error) => error instanceof WeeklyReportError && error.code === 'MAIL_REJECTED');
});

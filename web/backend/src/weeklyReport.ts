import type { SavedVideoResult } from './types.js';

const maxCsvBytes = 6 * 1024 * 1024;
const headers = ['date', 'keyword', 'video_id', 'title', 'url', 'channel', 'published_at'];

export class WeeklyReportError extends Error {
  constructor(public readonly code: 'INVALID_CONFIGURATION' | 'CSV_TOO_LARGE' | 'MAIL_REJECTED') {
    super(code);
    this.name = 'WeeklyReportError';
  }
}

export type WeeklyReportConfig = {
  host: string;
  user: string;
  password: string;
  from: string;
  to: string;
};

/**
 * Read the SES SMTP configuration without logging its values.
 * @param environment Process environment containing the report secret.
 * @returns Validated SES SMTP configuration.
 * @throws WeeklyReportError if a required value is missing or invalid.
 */
export function readWeeklyReportConfig(environment: NodeJS.ProcessEnv): WeeklyReportConfig {
  const { REPORT_SMTP_HOST: host, REPORT_SMTP_USER: user, REPORT_SMTP_PASS: password, REPORT_SMTP_FROM: from, REPORT_TO: to } = environment;
  const email = /^[^\s<>(),;:@]+@[^\s<>(),;:@]+\.[^\s<>(),;:@]+$/;
  if (!host || !/^email-smtp\.[a-z0-9-]+\.amazonaws\.com(?:\.cn)?$/.test(host) ||
      !user?.trim() || !password?.trim() || !from || !email.test(from) || !to || !email.test(to)) {
    throw new WeeklyReportError('INVALID_CONFIGURATION');
  }
  return { host, user, password, from, to };
}

function csvCell(value: string): string {
  const safe = /^[\t\r\n]|^[ \t\r\n]*[=+\-@]/.test(value) ? `'${value}` : value;
  return /[",\r\n]/.test(safe) ? `"${safe.replace(/"/g, '""')}"` : safe;
}

/**
 * Create an Excel-compatible CSV containing every saved result row.
 * @param rows Stream of saved video results.
 * @returns UTF-8 CSV bytes, including the header for an empty stream.
 * @throws WeeklyReportError when the attachment exceeds the safe SES size limit.
 */
export async function createWeeklyCsv(rows: AsyncIterable<SavedVideoResult>): Promise<Buffer> {
  const chunks: Buffer[] = [];
  let size = 0;
  const append = (text: string): void => {
    const chunk = Buffer.from(text, 'utf8');
    size += chunk.length;
    if (size > maxCsvBytes) throw new WeeklyReportError('CSV_TOO_LARGE');
    chunks.push(chunk);
  };
  append(`\ufeff${headers.join(',')}\r\n`);
  for await (const row of rows) {
    append([row.date, row.word, row.videoId, row.title, row.url, row.channel, row.publishedAt].map(csvCell).join(',') + '\r\n');
  }
  return Buffer.concat(chunks, size);
}

/**
 * Format a report date in the scheduler's time zone.
 * @param date Report generation time.
 * @returns The date in YYYY-MM-DD format.
 */
export function reportDate(date: Date): string {
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Tokyo', year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(date);
  const part = (type: Intl.DateTimeFormatPartTypes) => parts.find((item) => item.type === type)?.value;
  const year = part('year'), month = part('month'), day = part('day');
  if (!year || !month || !day) throw new Error('Could not determine the report date.');
  return `${year}-${month}-${day}`;
}

export type WeeklyReportMessage = {
  from: string;
  to: string;
  subject: string;
  text: string;
  attachments: Array<{ filename: string; content: Buffer; contentType: string }>;
};

/**
 * Generate and send the complete report through the supplied mail transport.
 * @param rows Stream of saved results.
 * @param config Validated sender and recipient settings.
 * @param send Mail transport, which must report accepted and rejected recipients.
 * @param now Generation time.
 * @returns A promise that resolves only when the recipient is accepted.
 * @throws When the CSV cannot be generated or the transport rejects the message.
 */
export async function sendWeeklyReport(
  rows: AsyncIterable<SavedVideoResult>,
  config: WeeklyReportConfig,
  send: (message: WeeklyReportMessage) => Promise<{ accepted: unknown[]; rejected: unknown[] }>,
  now: Date = new Date(),
): Promise<void> {
  const csv = await createWeeklyCsv(rows);
  const date = reportDate(now);
  const result = await send({
    from: config.from,
    to: config.to,
    subject: `YouTube video report - ${date}`,
    text: 'The attached CSV contains all saved YouTube video search results.',
    attachments: [{ filename: `youtube-results-${date}.csv`, content: csv, contentType: 'text/csv; charset=utf-8' }],
  });
  if (result.accepted.length !== 1 || result.rejected.length !== 0) throw new WeeklyReportError('MAIL_REJECTED');
}

import { createWriteStream, mkdirSync, renameSync, unlinkSync } from 'node:fs';
import { basename, join } from 'node:path';
import nodemailer from 'nodemailer';
import { insertResults, listEmails, listKeywords, upsertStat } from './db.js';
import { getSmtpConfig } from './secrets.js';
import { searchYouTube } from './youtube.js';
import type { Video } from './types.js';

const day = 24 * 60 * 60 * 1000;

function csvCell(value: string | number): string {
  const text = String(value ?? '');
  return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

function csvLine(values: Array<string | number>): string {
  return values.map(csvCell).join(',') + '\r\n';
}

function writeResultsCsv(directory: string, date: string, rows: Array<{ word: string; video: Video }>): Promise<string> {
  mkdirSync(directory, { recursive: true });
  const target = join(directory, `youtube_hits_${date}.csv`);
  const temporary = join(directory, `.youtube_hits_${process.pid}.tmp`);
  return new Promise((resolve, reject) => {
    const stream = createWriteStream(temporary, { encoding: 'utf8' });
    stream.on('error', (error) => {
      try { unlinkSync(temporary); } catch { /* ignore cleanup failure */ }
      reject(error);
    });
    stream.on('finish', () => {
      try {
        renameSync(temporary, target);
        resolve(target);
      } catch (error) {
        reject(error);
      }
    });
    stream.write('\ufeff');
    stream.write(csvLine(['date', 'keyword', 'video_id', 'title', 'url', 'channel', 'published_at']));
    for (const row of rows) {
      stream.write(csvLine([date, row.word, row.video.videoId, row.video.title, row.video.url, row.video.channel, row.video.publishedAt]));
    }
    stream.end();
  });
}

async function sendReport(subject: string, body: string, csvPath: string): Promise<void> {
  const { host, port, user, password, from } = await getSmtpConfig();
  if (!host) return;
  const transporter = nodemailer.createTransport({
    host,
    port,
    secure: port === 465,
    ...(user ? { auth: { user, pass: password } } : {}),
  });
  const recipients = (await listEmails()).map((email) => email.address);
  if (recipients.length === 0) return;
  await transporter.sendMail({
    from,
    to: recipients,
    subject,
    text: body,
    attachments: [{
      filename: basename(csvPath),
      path: csvPath,
      contentType: 'text/csv; charset=utf-8',
    }],
  });
}

export async function runOnce(): Promise<void> {
  const keywords = await listKeywords();
  if (keywords.length === 0) return;
  const date = new Date().toISOString().slice(0, 10);
  const rows: Array<{ word: string; video: Video }> = [];
  const report: string[] = [`YouTube Trend Report (${date})`, '', 'Date | Keyword | Hits'];

  for (const keyword of keywords) {
    try {
      const result = await searchYouTube(keyword.word);
      await upsertStat(date, keyword.word, result.totalHits);
      await insertResults(date, keyword.word, result.videos);
      rows.push(...result.videos.map((video) => ({ word: keyword.word, video })));
      report.push(`${date} | ${keyword.word} | ${result.totalHits}`);
    } catch {
      console.error(`${new Date().toISOString()} runOnce: A search or storage operation failed.`);
      throw new Error('Scheduled search or storage operation failed.');
    }
  }

  const csvDirectory = process.env.CSV_OUTPUT_DIR || 'backend/exports';
  const csvPath = await writeResultsCsv(csvDirectory, date, rows);
  await sendReport(`[YouTube Trend] ${date}`, report.join('\n'), csvPath);
}

export function startScheduler(): NodeJS.Timeout {
  return setInterval(() => {
    void runOnce().catch(() => console.error(`${new Date().toISOString()} startScheduler: Scheduled run failed.`));
  }, day);
}

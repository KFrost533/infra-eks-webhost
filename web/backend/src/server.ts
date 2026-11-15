import 'dotenv/config';
import express, { type ErrorRequestHandler, type Request } from 'express';
import { createServer } from 'node:http';
import { resolve } from 'node:path';
import mongoose from 'mongoose';
import { MongoConfigError } from './mongoConfig.js';
import {
  addEmail,
  addKeyword,
  deleteEmail,
  deleteKeyword,
  connectDB,
  disconnectDB,
  getSetting,
  listEmails,
  listKeywords,
  listStats,
  isDBConnected,
  setSetting,
  upsertStat,
} from './db.js';
import { runOnce, startScheduler } from './scheduler.js';
import {
  getSmtpSettings,
  getYouTubeApiKey,
  setSmtpSettings,
  setYouTubeApiKey,
} from './secrets.js';
import { searchYouTube } from './youtube.js';

const app = express();
const port = Number(process.env.PORT || 8080);
const origin = process.env.CORS_ORIGIN || '*';

app.use(express.json());
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', origin);
  res.header('Access-Control-Allow-Methods', 'GET,POST,PUT,DELETE,OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') {
    res.sendStatus(204);
    return;
  }
  next();
});

function maxResults(req: Request): number {
  const raw = Array.isArray(req.query.max) ? req.query.max[0] : req.query.max;
  return Number(raw || 25);
}

function csvCell(value: string | number): string {
  const text = String(value ?? '');
  return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

function csvLine(values: Array<string | number>): string {
  return values.map(csvCell).join(',') + '\r\n';
}

app.get('/api/search', async (req, res) => {
  const query = String(req.query.q || '').trim();
  if (!query) {
    res.status(400).json({ error: 'missing q' });
    return;
  }
  try {
    res.json(await searchYouTube(query, maxResults(req)));
  } catch (error) {
    console.error(`${new Date().toISOString()} searchYouTube: Search failed.`);
    res.status(502).json({ error: 'Search failed. Please try again.' });
  }
});

app.get('/api/search/csv', async (req, res) => {
  const query = String(req.query.q || '').trim();
  if (!query) {
    res.status(400).json({ error: 'missing q' });
    return;
  }
  try {
    const result = await searchYouTube(query, maxResults(req));
    const date = new Date().toISOString().slice(0, 10);
    await upsertStat(date, query, result.totalHits);
    const lines = [csvLine(['date', 'keyword', 'title', 'url'])];
    lines.push(...result.videos.map((video) => csvLine([date, query, video.title, video.url])));
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', `attachment; filename="videos_${date}.csv"`);
    res.send('\ufeff' + lines.join(''));
  } catch (error) {
    console.error(`${new Date().toISOString()} searchCsv: Search or storage failed.`);
    res.status(502).json({ error: 'Search failed. Please try again.' });
  }
});

app.get('/api/stats', async (_req, res) => res.json(await listStats()));
app.get('/api/stats/csv', async (_req, res) => {
  const lines = [csvLine(['date', 'keyword', 'hits'])];
  lines.push(...(await listStats()).map((row) => csvLine([row.date, row.word, row.hits])));
  res.setHeader('Content-Type', 'text/csv; charset=utf-8');
  res.setHeader('Content-Disposition', 'attachment; filename="stats.csv"');
  res.send('\ufeff' + lines.join(''));
});

app.get('/api/keywords', async (_req, res) => res.json(await listKeywords()));
app.post('/api/keywords', async (req, res) => {
  const word = String(req.body?.word || '').trim();
  if (!word) {
    res.status(400).json({ error: 'Keyword is required.' });
    return;
  }
  res.status(201).json(await addKeyword(word));
});
app.delete('/api/keywords/:id', async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id)) {
    res.status(400).json({ error: 'Invalid identifier.' });
    return;
  }
  await deleteKeyword(req.params.id);
  res.sendStatus(204);
});

app.get('/api/emails', async (_req, res) => res.json(await listEmails()));
app.post('/api/emails', async (req, res) => {
  const address = String(req.body?.address || '').trim();
  if (!address.includes('@')) {
    res.status(400).json({ error: 'invalid email' });
    return;
  }
  res.status(201).json(await addEmail(address));
});
app.delete('/api/emails/:id', async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id)) {
    res.status(400).json({ error: 'Invalid identifier.' });
    return;
  }
  await deleteEmail(req.params.id);
  res.sendStatus(204);
});

app.get('/api/settings', async (_req, res) => {
  res.json({
    language: (await getSetting('language')) || 'ja',
    apiKeyConfigured: Boolean(await getYouTubeApiKey()),
    smtp: await getSmtpSettings(),
  });
});
app.post('/api/settings', async (req, res) => {
  if (req.body?.language !== undefined) {
    const language = String(req.body.language);
    if (!['ja', 'en', 'de'].includes(language)) {
      res.status(400).json({ error: 'unsupported language' });
      return;
    }
    await setSetting('language', language);
  }
  if (req.body?.apiKey !== undefined) {
    const apiKey = String(req.body.apiKey).trim();
    await setYouTubeApiKey(apiKey);
  }
  res.json({
    language: (await getSetting('language')) || 'ja',
    apiKeyConfigured: Boolean(await getYouTubeApiKey()),
    smtp: await getSmtpSettings(),
  });
});
app.post('/api/settings/smtp', async (req, res) => {
  const { host, port, user, from, password } = req.body || {};
  if (
    typeof host !== 'string' ||
    typeof from !== 'string' ||
    (user !== undefined && typeof user !== 'string')
  ) {
    res.status(400).json({ error: 'invalid SMTP settings' });
    return;
  }

  const smtpHost = host.trim();
  const smtpPort = Number(port);
  const smtpUser = typeof user === 'string' ? user.trim() : '';
  const smtpFrom = from.trim();

  if (!smtpHost || !Number.isInteger(smtpPort) || smtpPort < 1 || smtpPort > 65535) {
    res.status(400).json({ error: 'invalid SMTP host or port' });
    return;
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(smtpFrom) || /[\r\n]/.test(smtpFrom)) {
    res.status(400).json({ error: 'invalid SMTP sender address' });
    return;
  }
  if (password !== undefined && typeof password !== 'string') {
    res.status(400).json({ error: 'invalid SMTP password' });
    return;
  }

  try {
    await setSmtpSettings({
      host: smtpHost,
      port: smtpPort,
      user: smtpUser,
      from: smtpFrom,
      ...(password ? { password } : {}),
    });
    res.json(await getSmtpSettings());
  } catch (error) {
    console.error(`${new Date().toISOString()} setSmtpSettings: Failed to save SMTP settings.`);
    res.status(500).json({ error: 'Failed to save SMTP settings. Please try again.' });
  }
});

app.post('/api/run-now', async (_req, res) => {
  try {
    await runOnce();
    res.json({ status: 'ok' });
  } catch (error) {
    console.error(`${new Date().toISOString()} runOnce: Run failed.`);
    res.status(500).json({ error: 'Run failed. Please try again.' });
  }
});
app.get('/api/health', (_req, res) => {
  res.status(isDBConnected() ? 200 : 503).json({ status: isDBConnected() ? 'ok' : 'unavailable' });
});
app.get('/api/live', (_req, res) => res.json({ status: 'ok' }));

if (process.env.NODE_ENV === 'production') {
  const frontendPath = resolve('frontend/dist');
  app.use('/api', (_req, res) => res.sendStatus(404));
  app.use(express.static(frontendPath));
  app.get(/.*/, (_req, res) => res.sendFile(resolve(frontendPath, 'index.html')));
}

const errorHandler: ErrorRequestHandler = (_error, _req, res, _next) => {
  console.error(`${new Date().toISOString()} requestHandler: Request failed.`);
  res.status(500).json({ error: 'Request failed. Please try again.' });
};
app.use(errorHandler);

/** Connect to MongoDB before accepting requests and close it during shutdown. */
async function start(): Promise<void> {
  await connectDB();
  const server = createServer(app);
  const scheduler = startScheduler();
  server.listen(port, () => console.log(`TypeScript backend listening on :${port}`));

  const shutdown = (): void => {
    clearInterval(scheduler);
    server.close(() => {
      void disconnectDB().then(() => process.exit(0)).catch(() => {
        console.error(`${new Date().toISOString()} shutdown: Database disconnect failed.`);
        process.exit(1);
      });
    });
  };
  process.once('SIGINT', shutdown);
  process.once('SIGTERM', shutdown);
}

void start().catch((error: unknown) => {
  const message = error instanceof MongoConfigError
    ? error.message
    : 'MongoDB connection or initialisation failed. Check configuration and network access.';
  console.error(`${new Date().toISOString()} start: ${message}`);
  process.exitCode = 1;
  void disconnectDB().catch(() => {
    console.error(`${new Date().toISOString()} start: Database disconnect failed.`);
  });
});

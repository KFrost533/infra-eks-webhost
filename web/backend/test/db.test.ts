import assert from 'node:assert/strict';
import { after, mock, test } from 'node:test';
import mongoose from 'mongoose';
import { addEmail, addKeyword, connectDB, isDBConnected, streamVideoResults } from '../src/db.js';

const originalUri = process.env.ACCESS_MONGODB_URI;
const originalNodeEnv = process.env.NODE_ENV;

after(() => {
  if (originalUri === undefined) delete process.env.ACCESS_MONGODB_URI;
  else process.env.ACCESS_MONGODB_URI = originalUri;
  if (originalNodeEnv === undefined) delete process.env.NODE_ENV;
  else process.env.NODE_ENV = originalNodeEnv;
});

test('rejects missing and malformed MongoDB connection strings', async () => {
  delete process.env.ACCESS_MONGODB_URI;
  process.env.NODE_ENV = 'production';
  await assert.rejects(connectDB(), /ACCESS_MONGODB_URI/);
  process.env.ACCESS_MONGODB_URI = 'https://example.invalid';
  await assert.rejects(connectDB(), /ACCESS_MONGODB_URI/);
  assert.equal(isDBConnected(), false);
});

test('rejects empty keyword and email values before accessing the database', async () => {
  await assert.rejects(addKeyword(''), /Keyword is required/);
  await assert.rejects(addEmail(''), /Email address is required/);
});

test('defines uniqueness constraints for keywords, email and statistics', () => {
  const indexes = (name: string) => mongoose.model(name).schema.indexes();
  assert.ok(indexes('Keyword').some(([fields, options]) => fields.word === 1 && options.unique));
  assert.ok(indexes('Email').some(([fields, options]) => fields.address === 1 && options.unique));
  assert.ok(indexes('Stat').some(([fields, options]) => fields.date === 1 && fields.word === 1 && options.unique));
});

test('streams every saved video result and closes the cursor', async () => {
  const saved = [
    { date: '2026-01-01', word: 'example', videoId: 'one', title: 'First', url: 'https://example.test/1', channel: 'Channel', publishedAt: '2026-01-01' },
    { date: '2026-01-02', word: 'example', videoId: 'two', title: 'Second', url: 'https://example.test/2', channel: 'Channel', publishedAt: '2026-01-02' },
  ];
  let closed = false;
  const cursor = {
    async *[Symbol.asyncIterator]() { yield* saved; },
    async close() { closed = true; },
  };
  const query = {
    select(fields: string) { assert.equal(fields, 'date word videoId title url channel publishedAt'); return this; },
    sort(order: object) { assert.deepEqual(order, { _id: 1 }); return this; },
    lean() { return this; },
    cursor() { return cursor; },
  };
  const find = mock.method(mongoose.model('SearchResult'), 'find', () => query);
  try {
    const rows = [];
    for await (const row of streamVideoResults()) rows.push(row);
    assert.deepEqual(rows, saved);
    assert.deepEqual(find.mock.calls[0].arguments, []);
    assert.equal(closed, true);
  } finally {
    find.mock.restore();
  }
});

import mongoose, { Schema } from 'mongoose';
import { resolveMongoUri } from './mongoConfig.js';
import type { EmailEntry, Keyword, SavedVideoResult, StatRow, Video } from './types.js';

const keywordSchema = new Schema({
  word: { type: String, required: true, unique: true },
  createdAt: { type: String, required: true },
}, { versionKey: false });

const emailSchema = new Schema({
  address: { type: String, required: true, unique: true },
  createdAt: { type: String, required: true },
}, { versionKey: false });

const statSchema = new Schema({
  date: { type: String, required: true },
  word: { type: String, required: true },
  hits: { type: Number, required: true },
}, { versionKey: false });
statSchema.index({ date: 1, word: 1 }, { unique: true });

const resultSchema = new Schema({
  date: { type: String, required: true },
  word: { type: String, required: true },
  videoId: { type: String, required: true },
  title: { type: String, default: '' },
  url: { type: String, default: '' },
  channel: { type: String, default: '' },
  publishedAt: { type: String, default: '' },
}, { versionKey: false });

const settingSchema = new Schema({
  key: { type: String, required: true, unique: true },
  value: { type: String, default: '' },
}, { versionKey: false });

const KeywordModel = mongoose.model('Keyword', keywordSchema);
const EmailModel = mongoose.model('Email', emailSchema);
const StatModel = mongoose.model('Stat', statSchema);
const ResultModel = mongoose.model('SearchResult', resultSchema);
const SettingModel = mongoose.model('Setting', settingSchema);

/** Connect once and optionally initialise indexes before serving requests. */
export async function connectDB(options: { initialiseIndexes?: boolean } = {}): Promise<void> {
  const uri = await resolveMongoUri({
    environmentUri: process.env.ACCESS_MONGODB_URI,
    nodeEnv: process.env.NODE_ENV,
  });
  await mongoose.connect(uri, options.initialiseIndexes === false ? { autoIndex: false, autoCreate: false } : {});
  if (options.initialiseIndexes !== false) {
    await Promise.all([KeywordModel.init(), EmailModel.init(), StatModel.init(), ResultModel.init(), SettingModel.init()]);
  }
}

/** Close the shared MongoDB connection when the server shuts down. */
export async function disconnectDB(): Promise<void> {
  await mongoose.disconnect();
}

/** Return whether MongoDB is connected. */
export function isDBConnected(): boolean {
  return mongoose.connection.readyState === 1;
}

/** List saved keywords. */
export async function listKeywords(): Promise<Keyword[]> {
  const rows = await KeywordModel.find().sort({ _id: 1 }).lean();
  return rows.map((row) => ({ id: row._id.toString(), word: row.word, createdAt: row.createdAt }));
}

/** Create a keyword if necessary and return it. */
export async function addKeyword(word: string): Promise<Keyword> {
  if (!word) throw new Error('Keyword is required.');
  const row = await KeywordModel.findOneAndUpdate(
    { word }, { $setOnInsert: { word, createdAt: new Date().toISOString() } },
    { upsert: true, new: true, runValidators: true },
  ).orFail().lean();
  return { id: row._id.toString(), word: row.word, createdAt: row.createdAt };
}

/** Delete a keyword by its MongoDB identifier. */
export async function deleteKeyword(id: string): Promise<void> {
  await KeywordModel.deleteOne({ _id: id });
}

/** List saved email addresses. */
export async function listEmails(): Promise<EmailEntry[]> {
  const rows = await EmailModel.find().sort({ _id: 1 }).lean();
  return rows.map((row) => ({ id: row._id.toString(), address: row.address, createdAt: row.createdAt }));
}

/** Create an email address if necessary and return it. */
export async function addEmail(address: string): Promise<EmailEntry> {
  if (!address) throw new Error('Email address is required.');
  const row = await EmailModel.findOneAndUpdate(
    { address }, { $setOnInsert: { address, createdAt: new Date().toISOString() } },
    { upsert: true, new: true, runValidators: true },
  ).orFail().lean();
  return { id: row._id.toString(), address: row.address, createdAt: row.createdAt };
}

/** Delete an email address by its MongoDB identifier. */
export async function deleteEmail(id: string): Promise<void> {
  await EmailModel.deleteOne({ _id: id });
}

/** Replace the hit count for a date and keyword. */
export async function upsertStat(date: string, word: string, hits: number): Promise<void> {
  await StatModel.updateOne({ date, word }, { $set: { hits } }, { upsert: true, runValidators: true });
}

/** Store video results for a search run. */
export async function insertResults(date: string, word: string, videos: Video[]): Promise<void> {
  if (videos.length === 0) return;
  await ResultModel.insertMany(videos.map(({ videoId, title, url, channel, publishedAt }) => ({
    date, word, videoId, title, url, channel, publishedAt,
  })));
}

/**
 * Stream all saved video result rows in insertion order without loading the collection into memory.
 * @returns An async sequence of video result rows.
 * @throws When MongoDB cannot read the results.
 */
export async function* streamVideoResults(): AsyncGenerator<SavedVideoResult> {
  const cursor = ResultModel.find().select('date word videoId title url channel publishedAt').sort({ _id: 1 }).lean().cursor();
  try {
    for await (const row of cursor) {
      yield { date: row.date, word: row.word, videoId: row.videoId, title: row.title, url: row.url, channel: row.channel, publishedAt: row.publishedAt };
    }
  } finally {
    await cursor.close();
  }
}

/** List statistics ordered by date and keyword. */
export async function listStats(): Promise<StatRow[]> {
  const rows = await StatModel.find().sort({ date: 1, word: 1 }).lean();
  return rows.map(({ date, word, hits }) => ({ date, word, hits }));
}

/** Retrieve a setting or an empty string when it is absent. */
export async function getSetting(key: string): Promise<string> {
  const setting = await SettingModel.findOne({ key }).lean();
  return setting?.value ?? '';
}

/** Save a setting. */
export async function setSetting(key: string, value: string): Promise<void> {
  await SettingModel.updateOne({ key }, { $set: { value } }, { upsert: true, runValidators: true });
}

import { readFile } from 'node:fs/promises';

export class MongoConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'MongoConfigError';
  }
}

/**
 * Resolve the MongoDB URI without exposing its contents.
 * Environment configuration takes precedence; local JSON is not used in production.
 * @param options Environment values and optional local configuration file location.
 * @returns The validated connection URI.
 * @throws MongoConfigError when configuration is absent, unreadable or invalid.
 */
export async function resolveMongoUri(options: {
  environmentUri: string | undefined;
  nodeEnv: string | undefined;
  configFile?: URL;
}): Promise<string> {
  let uri: unknown = options.environmentUri;
  if (uri === undefined && options.nodeEnv !== 'production') {
    let raw: string;
    try {
      raw = await readFile(options.configFile ?? new URL('./config/db.json', import.meta.url), 'utf8');
    } catch {
      throw new MongoConfigError('Set ACCESS_MONGODB_URI or provide the local MongoDB JSON configuration.');
    }

    let config: unknown;
    try {
      config = JSON.parse(raw);
    } catch {
      throw new MongoConfigError('The local MongoDB JSON configuration is invalid.');
    }
    if (typeof config !== 'object' || config === null || !('ACCESS_MONGODB_URI' in config)) {
      throw new MongoConfigError('The local MongoDB JSON configuration must contain ACCESS_MONGODB_URI.');
    }
    uri = config.ACCESS_MONGODB_URI;
  }

  if (typeof uri !== 'string' || !/^mongodb(\+srv)?:\/\/\S+$/i.test(uri)) {
    throw new MongoConfigError('ACCESS_MONGODB_URI must be a valid MongoDB connection URI.');
  }
  return uri;
}

import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { test } from 'node:test';
import { resolveMongoUri } from '../src/mongoConfig.js';

test('uses local JSON only when the environment URI is absent outside production', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'mongo-config-test-'));
  const configFile = pathToFileURL(join(directory, 'db.json'));
  try {
    await writeFile(configFile, JSON.stringify({ ACCESS_MONGODB_URI: 'mongodb://localhost/test' }));
    assert.equal(await resolveMongoUri({ environmentUri: undefined, nodeEnv: 'development', configFile }), 'mongodb://localhost/test');
    assert.equal(await resolveMongoUri({ environmentUri: 'mongodb://localhost/override', nodeEnv: 'development', configFile }), 'mongodb://localhost/override');
    await assert.rejects(resolveMongoUri({ environmentUri: undefined, nodeEnv: 'production', configFile }), /ACCESS_MONGODB_URI/);
    await assert.rejects(resolveMongoUri({ environmentUri: '', nodeEnv: 'development', configFile }), /ACCESS_MONGODB_URI/);
    await writeFile(configFile, '{');
    await assert.rejects(resolveMongoUri({ environmentUri: undefined, nodeEnv: 'development', configFile }), /JSON configuration is invalid/);
    await writeFile(configFile, '{}');
    await assert.rejects(resolveMongoUri({ environmentUri: undefined, nodeEnv: 'development', configFile }), /must contain/);
    await rm(configFile);
    await assert.rejects(resolveMongoUri({ environmentUri: undefined, nodeEnv: 'development', configFile }), /provide the local/);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';
import { getSetting, setSetting } from './db.js';

const prefix = 'enc:v1:';

function encryptionKey(): Buffer {
  const rawKey = process.env.API_KEY_ENCRYPTION_KEY;
  if (!rawKey) {
    throw new Error('API_KEY_ENCRYPTION_KEY is not set');
  }
  return createHash('sha256').update(rawKey, 'utf8').digest();
}

export function encryptSecret(value: string): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', encryptionKey(), iv);
  const encrypted = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return [
    prefix,
    iv.toString('base64url'),
    tag.toString('base64url'),
    encrypted.toString('base64url'),
  ].join(':');
}

function decryptSecret(value: string): string {
  const parts = value.split(':');
  if (parts.length !== 5 || `${parts[0]}:${parts[1]}:` !== prefix) {
    throw new Error('Invalid encrypted secret format');
  }
  const iv = Buffer.from(parts[2], 'base64url');
  const tag = Buffer.from(parts[3], 'base64url');
  const encrypted = Buffer.from(parts[4], 'base64url');
  const decipher = createDecipheriv('aes-256-gcm', encryptionKey(), iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(encrypted), decipher.final()]).toString('utf8');
}

export async function getYouTubeApiKey(): Promise<string> {
  const stored = await getSetting('youtube_api_key');
  if (stored) {
    return stored.startsWith(prefix) ? decryptSecret(stored) : stored;
  }
  return process.env.YOUTUBE_API_KEY || '';
}

export async function setYouTubeApiKey(value: string): Promise<void> {
  await setSetting('youtube_api_key', encryptSecret(value));
}

export interface SmtpConfig {
  host: string;
  port: number;
  user: string;
  password: string;
  from: string;
}

export interface SmtpSettings {
  host: string;
  port: number;
  user: string;
  from: string;
  passwordConfigured: boolean;
}

export async function getSmtpConfig(): Promise<SmtpConfig> {
  const [configured, storedPassword, host, port, user, from] = await Promise.all([
    getSetting('smtp_configured'), getSetting('smtp_password'), getSetting('smtp_host'),
    getSetting('smtp_port'), getSetting('smtp_user'), getSetting('smtp_from'),
  ]);
  const configuredInApp = configured === '1';
  const password = storedPassword
    ? decryptSecret(storedPassword)
    : process.env.SMTP_PASS || '';

  return {
    host: configuredInApp ? host : process.env.SMTP_HOST || '',
    port: Number(configuredInApp ? port : process.env.SMTP_PORT || 587),
    user: configuredInApp ? user : process.env.SMTP_USER || '',
    password,
    from: configuredInApp
      ? from
      : process.env.SMTP_FROM || 'noreply@example.com',
  };
}

export async function getSmtpSettings(): Promise<SmtpSettings> {
  const { password, ...settings } = await getSmtpConfig();
  return { ...settings, passwordConfigured: Boolean(password) };
}

export async function setSmtpSettings(
  settings: Omit<SmtpConfig, 'password'> & { password?: string },
): Promise<void> {
  const encryptedPassword = settings.password
    ? encryptSecret(settings.password)
    : undefined;

  await setSetting('smtp_host', settings.host);
  await setSetting('smtp_port', String(settings.port));
  await setSetting('smtp_user', settings.user);
  await setSetting('smtp_from', settings.from);
  if (encryptedPassword) await setSetting('smtp_password', encryptedPassword);
  await setSetting('smtp_configured', '1');
}

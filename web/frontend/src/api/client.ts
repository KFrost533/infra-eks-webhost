import type {
  EmailEntry,
  Keyword,
  LanguageCode,
  SearchResult,
  SmtpSettings,
  SmtpSettingsInput,
  StatRow,
} from '../types';

const BASE = '/api';

async function req<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...(init?.headers || {}),
    },
  });
  if (!res.ok) {
    let msg = res.statusText;
    try {
      const body = (await res.json()) as { error?: string };
      if (body.error) msg = body.error;
    } catch {
      // ignore
    }
    throw new Error(msg);
  }
  if (res.status === 204) return undefined as T;
  return (await res.json()) as T;
}

export const api = {
  search(q: string, max = 25) {
    return req<SearchResult>(
      `/search?q=${encodeURIComponent(q)}&max=${max}`,
    );
  },
  searchCsvURL(q: string, max = 25) {
    return `${BASE}/search/csv?q=${encodeURIComponent(q)}&max=${max}`;
  },
  stats() {
    return req<StatRow[]>('/stats');
  },
  statsCsvURL() {
    return `${BASE}/stats/csv`;
  },
  listKeywords() {
    return req<Keyword[]>('/keywords');
  },
  addKeyword(word: string) {
    return req<Keyword>('/keywords', {
      method: 'POST',
      body: JSON.stringify({ word }),
    });
  },
  deleteKeyword(id: string) {
    return req<void>(`/keywords/${id}`, { method: 'DELETE' });
  },
  listEmails() {
    return req<EmailEntry[]>('/emails');
  },
  addEmail(address: string) {
    return req<EmailEntry>('/emails', {
      method: 'POST',
      body: JSON.stringify({ address }),
    });
  },
  deleteEmail(id: string) {
    return req<void>(`/emails/${id}`, { method: 'DELETE' });
  },
  getSettings() {
    return req<{
      language: LanguageCode;
      apiKeyConfigured: boolean;
      smtp: SmtpSettings;
    }>('/settings');
  },
  setSettings(language?: LanguageCode, apiKey?: string) {
    return req<{
      language: LanguageCode;
      apiKeyConfigured: boolean;
      smtp: SmtpSettings;
    }>('/settings', {
      method: 'POST',
      body: JSON.stringify({ language, ...(apiKey !== undefined ? { apiKey } : {}) }),
    });
  },
  setSmtpSettings(settings: SmtpSettingsInput) {
    return req<SmtpSettings>('/settings/smtp', {
      method: 'POST',
      body: JSON.stringify(settings),
    });
  },
  runNow() {
    return req<{ status: string }>('/run-now', { method: 'POST' });
  },
};

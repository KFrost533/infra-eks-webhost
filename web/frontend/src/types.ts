export interface Video {
  videoId: string;
  title: string;
  url: string;
  channel: string;
  publishedAt: string;
  thumbnail: string;
}

export interface SearchResult {
  query: string;
  totalHits: number;
  videos: Video[];
  fetchedAt: string;
}

export interface Keyword {
  id: string;
  word: string;
  createdAt: string;
}

export interface EmailEntry {
  id: string;
  address: string;
  createdAt: string;
}

export interface StatRow {
  date: string;
  word: string;
  hits: number;
}

export interface SmtpSettings {
  host: string;
  port: number;
  user: string;
  from: string;
  passwordConfigured: boolean;
}

export interface SmtpSettingsInput {
  host: string;
  port: number;
  user: string;
  from: string;
  password?: string;
}

export type LanguageCode = 'ja' | 'en' | 'de';

export type Video = {
  videoId: string;
  title: string;
  url: string;
  channel: string;
  publishedAt: string;
  thumbnail: string;
};

export type SearchResult = {
  query: string;
  totalHits: number;
  videos: Video[];
  fetchedAt: string;
};

export type Keyword = { id: string; word: string; createdAt: string };
export type EmailEntry = { id: string; address: string; createdAt: string };
export type StatRow = { date: string; word: string; hits: number };
export type SavedVideoResult = Pick<Video, 'videoId' | 'title' | 'url' | 'channel' | 'publishedAt'> & {
  date: string;
  word: string;
};

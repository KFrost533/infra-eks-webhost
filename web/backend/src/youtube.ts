import type { SearchResult, Video } from './types.js';
import { getYouTubeApiKey } from './secrets.js';

const endpoint = 'https://www.googleapis.com/youtube/v3/search';
const videoBaseUrl = 'https://www.youtube.com/watch?v=';

export async function searchYouTube(query: string, maxResults = 25): Promise<SearchResult> {
  const apiKey = await getYouTubeApiKey();
  if (!apiKey) throw new Error('YOUTUBE_API_KEY is not set');
  const max = maxResults > 0 && maxResults <= 50 ? maxResults : 25;
  const params = new URLSearchParams({
    part: 'snippet',
    type: 'video',
    q: query,
    maxResults: String(max),
    key: apiKey,
  });
  const response = await fetch(`${endpoint}?${params}`);
  const body = await response.json() as {
    pageInfo?: { totalResults?: number };
    items?: Array<{
      id?: { videoId?: string };
      snippet?: {
        title?: string;
        channelTitle?: string;
        publishedAt?: string;
        thumbnails?: { medium?: { url?: string } };
      };
    }>;
    error?: { code?: number; message?: string };
  };
  if (!response.ok || body.error) {
    throw new Error(`YouTube API error ${body.error?.code || response.status}: ${body.error?.message || response.statusText}`);
  }
  const videos: Video[] = (body.items || []).flatMap((item) => {
    const id = item.id?.videoId;
    if (!id) return [];
    return [{
      videoId: id,
      title: item.snippet?.title || '',
      url: videoBaseUrl + id,
      channel: item.snippet?.channelTitle || '',
      publishedAt: item.snippet?.publishedAt || '',
      thumbnail: item.snippet?.thumbnails?.medium?.url || '',
    }];
  });
  return {
    query,
    totalHits: body.pageInfo?.totalResults || 0,
    videos,
    fetchedAt: new Date().toISOString(),
  };
}

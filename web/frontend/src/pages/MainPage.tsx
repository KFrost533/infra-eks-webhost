import React, { useEffect, useMemo, useState } from "react";
import { useTranslation } from 'react-i18next';
import { api } from '../api/client';
import { StatsChart } from '../components/StatsChart';
import { VideoTable } from '../components/VideoTable';
import type { SearchResult, StatRow } from '../types';

export function MainPage() {
  const { t } = useTranslation();
  const [query, setQuery] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<SearchResult | null>(null);
  const [stats, setStats] = useState<StatRow[]>([]);
  const [filterWord, setFilterWord] = useState('');
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');

  const loadStats = async () => {
    try {
      const rows = await api.stats();
      setStats(rows);
    } catch (e) {
      // ignore stats errors on page load
      console.warn('load stats', e);
    }
  };

  useEffect(() => {
    void loadStats();
  }, []);

  const onSearch = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!query.trim()) return;
    setLoading(true);
    setError(null);
    try {
      const res = await api.search(query.trim());
      setResult(res);
      setFilterWord('');
      setDateFrom('');
      setDateTo('');
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      setError(message);
      console.error('search failed', err);
    } finally {
      setLoading(false);
    }
  };

  const filteredVideos = useMemo(() => {
    if (!result) return [];

    const normalizedWord = filterWord.trim().toLocaleLowerCase();
    return result.videos.filter((video) => {
      const publishedDate = video.publishedAt.slice(0, 10);
      const matchesDateFrom = !dateFrom || publishedDate >= dateFrom;
      const matchesDateTo = !dateTo || publishedDate <= dateTo;
      const searchableText = `${video.title} ${video.channel}`.toLocaleLowerCase();
      const matchesWord =
        !normalizedWord || searchableText.includes(normalizedWord);

      return matchesDateFrom && matchesDateTo && matchesWord;
    });
  }, [dateFrom, dateTo, filterWord, result]);

  const onRunNow = async () => {
    try {
      await api.runNow();
      await loadStats();
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      setError(message);
      console.error('run now failed', err);
    }
  };

  return (
    <div className="container">
      <div className="card">
        <h2>{t('app.title')}</h2>
        <form className="row" onSubmit={onSearch}>
          <input
            type="text"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={t('main.searchPlaceholder')}
          />
          <button type="submit" disabled={loading}>
            {t('main.search')}
          </button>
          {result && (
            <a href={api.searchCsvURL(result.query)}>
              <button type="button" className="secondary">
                {t('main.downloadCsv')}
              </button>
            </a>
          )}
        </form>
        {error && (
          <div className="error" style={{ marginTop: 12 }}>
            {t('main.error', { message: error })}
          </div>
        )}
        {loading && <p className="muted">{t('main.loading')}</p>}
        {result && (
          <>
            <p className="muted" style={{ marginTop: 12 }}>
              {t('main.totalHits', {
                count: result.totalHits,
                filteredCount: filteredVideos.length,
              })}
            </p>
            <div className="filter-panel">
              <strong>{t('main.filters')}</strong>
              <div className="row">
                <label>
                  {t('main.filterWord')}
                  <input
                    type="text"
                    value={filterWord}
                    onChange={(e) => setFilterWord(e.target.value)}
                    placeholder={t('main.filterWordPlaceholder')}
                  />
                </label>
                <label>
                  {t('main.dateFrom')}
                  <input
                    type="date"
                    value={dateFrom}
                    onChange={(e) => setDateFrom(e.target.value)}
                  />
                </label>
                <label>
                  {t('main.dateTo')}
                  <input
                    type="date"
                    value={dateTo}
                    onChange={(e) => setDateTo(e.target.value)}
                  />
                </label>
                <button
                  type="button"
                  className="secondary"
                  onClick={() => {
                    setFilterWord('');
                    setDateFrom('');
                    setDateTo('');
                  }}
                  disabled={!filterWord && !dateFrom && !dateTo}
                >
                  {t('main.clearFilters')}
                </button>
              </div>
            </div>
            <VideoTable videos={filteredVideos} />
          </>
        )}
      </div>

      <div className="card">
        <div className="row" style={{ justifyContent: 'space-between' }}>
          <h3 style={{ margin: 0 }}>{t('main.stats')}</h3>
          <div className="row">
            <button className="secondary" onClick={() => void loadStats()}>
              ↻
            </button>
            <button onClick={() => void onRunNow()}>{t('main.runNow')}</button>
            <a href={api.statsCsvURL()}>
              <button type="button" className="secondary">
                {t('main.downloadCsv')}
              </button>
            </a>
          </div>
        </div>
        <div style={{ marginTop: 16 }}>
          <StatsChart stats={stats} />
        </div>
        {stats.length > 0 && (
          <table style={{ marginTop: 16 }}>
            <thead>
              <tr>
                <th>date</th>
                <th>keyword</th>
                <th>hits</th>
              </tr>
            </thead>
            <tbody>
              {stats.map((s, i) => (
                <tr key={`${s.date}-${s.word}-${i}`}>
                  <td>{s.date}</td>
                  <td>{s.word}</td>
                  <td>{s.hits}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}

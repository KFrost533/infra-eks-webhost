import { useTranslation } from 'react-i18next';
import type { Video } from '../types';

interface Props {
  videos: Video[];
}

export function VideoTable({ videos }: Props) {
  const { t } = useTranslation();

  if (videos.length === 0) {
    return <p className="muted">{t('main.empty')}</p>;
  }
  
  return (
    <table>
      <thead>
        <tr>
          <th></th>
          <th>{t('main.columns.title')}</th>
          <th>{t('main.columns.channel')}</th>
          <th>{t('main.columns.publishedAt')}</th>
          <th>{t('main.columns.url')}</th>
        </tr>
      </thead>
      <tbody>
        {videos.map((v) => (
          <tr key={v.videoId}>
            <td>
              {v.thumbnail && (
                <img className="thumb" src={v.thumbnail} alt="" />
              )}
            </td>
            <td>{v.title}</td>
            <td>{v.channel}</td>
            <td>{v.publishedAt?.slice(0, 10)}</td>
            <td>
              <a href={v.url} target="_blank" rel="noreferrer">
                {v.url}
              </a>
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

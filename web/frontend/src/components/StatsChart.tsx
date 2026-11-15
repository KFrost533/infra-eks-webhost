import {
  Bar,
  BarChart,
  CartesianGrid,
  Legend,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import type { StatRow } from '../types';

interface Props {
  stats: StatRow[];
}

export function StatsChart({ stats }: Props) {
  if (stats.length === 0) return null;

  const byDate = new Map<string, Record<string, number | string>>();
  const words = new Set<string>();

  for (const row of stats) {
    words.add(row.word);
    const existing = byDate.get(row.date) ?? { date: row.date };
    existing[row.word] = row.hits;
    byDate.set(row.date, existing);
  }
  
  const data = Array.from(byDate.values()).sort((a, b) =>
    String(a.date).localeCompare(String(b.date)),
  );
  
  const wordList = Array.from(words);
  const palette = ['#ef4444', '#38bdf8', '#22c55e', '#f59e0b', '#a855f7', '#ec4899'];

  return (
    <div style={{ width: '100%', height: 320 }}>
      <ResponsiveContainer>
        <BarChart data={data}>
          <CartesianGrid strokeDasharray="3 3" stroke="#334155" />
          <XAxis dataKey="date" stroke="#94a3b8" />
          <YAxis stroke="#94a3b8" />
          <Tooltip
            contentStyle={{ background: '#1e293b', border: '1px solid #334155' }}
          />
          <Legend />
          {wordList.map((w, i) => (
            <Bar key={w} dataKey={w} fill={palette[i % palette.length]} />
          ))}
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}

import { useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';
import i18n from '../i18n';
import { api } from '../api/client';
import type { EmailEntry, Keyword, LanguageCode, SmtpSettings } from '../types';

export function SettingsPage() {
  const { t } = useTranslation();
  const [lang, setLang] = useState<LanguageCode>(
    (localStorage.getItem('lang') as LanguageCode) || 'ja',
  );
  const [keywords, setKeywords] = useState<Keyword[]>([]);
  const [emails, setEmails] = useState<EmailEntry[]>([]);
  const [newWord, setNewWord] = useState('');
  const [newEmail, setNewEmail] = useState('');
  const [apiKey, setApiKey] = useState('');
  const [apiKeyConfigured, setApiKeyConfigured] = useState(false);
  const [smtp, setSmtp] = useState<SmtpSettings>({
    host: '',
    port: 587,
    user: '',
    from: '',
    passwordConfigured: false,
  });
  const [smtpPassword, setSmtpPassword] = useState('');
  const [smtpSaving, setSmtpSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const load = async () => {
    try {
      const [kw, em, s] = await Promise.all([
        api.listKeywords(),
        api.listEmails(),
        api.getSettings(),
      ]);
      setKeywords(kw);
      setEmails(em);
      setLang(s.language);
      setApiKeyConfigured(s.apiKeyConfigured);
      setSmtp(s.smtp);
      void i18n.changeLanguage(s.language);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      setError(message);
      console.error('settings load failed', err);
    }
  };

  const saveApiKey = async () => {
    try {
      const result = await api.setSettings(undefined, apiKey.trim());
      setApiKey('');
      setApiKeyConfigured(result.apiKeyConfigured);
      setNotice(t('settings.saved'));
      setTimeout(() => setNotice(null), 1500);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      setError(message);
      console.error('save YouTube API key failed', err);
    }
  };

  const saveSmtp = async () => {
    setSmtpSaving(true);
    try {
      const saved = await api.setSmtpSettings({
        host: smtp.host.trim(),
        port: smtp.port,
        user: smtp.user.trim(),
        from: smtp.from.trim(),
        ...(smtpPassword ? { password: smtpPassword } : {}),
      });
      setSmtp(saved);
      setSmtpPassword('');
      setNotice(t('settings.saved'));
      setTimeout(() => setNotice(null), 1500);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      setError(message);
      console.error('save SMTP settings failed', err);
    } finally {
      setSmtpSaving(false);
    }
  };

  useEffect(() => {
    void load();
  }, []);

  const onChangeLang = async (l: LanguageCode) => {
    setLang(l);
    localStorage.setItem('lang', l);
    void i18n.changeLanguage(l);
    try {
      await api.setSettings(l);
      setNotice(t('settings.saved'));
      setTimeout(() => setNotice(null), 1500);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      setError(message);
      console.error('save lang failed', err);
    }
  };

  const addKeyword = async () => {
    if (!newWord.trim()) return;
    try {
      await api.addKeyword(newWord.trim());
      setNewWord('');
      await load();
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      setError(message);
      console.error('add keyword failed', err);
    }
  };

  const deleteKeyword = async (id: string) => {
    try {
      await api.deleteKeyword(id);
      await load();
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      setError(message);
      console.error('delete keyword failed', err);
    }
  };

  const addEmail = async () => {
    if (!newEmail.trim()) return;
    try {
      await api.addEmail(newEmail.trim());
      setNewEmail('');
      await load();
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      setError(message);
      console.error('add email failed', err);
    }
  };

  const deleteEmail = async (id: string) => {
    try {
      await api.deleteEmail(id);
      await load();
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      setError(message);
      console.error('delete email failed', err);
    }
  };

  return (
    <div className="container">
      {error && <div className="error">{error}</div>}
      {notice && <div className="notice">{notice}</div>}

      <div className="card">
        <h3>{t('settings.youtubeApi')}</h3>
        <p className="muted">
          {apiKeyConfigured ? t('settings.apiKeyConfigured') : t('settings.apiKeyMissing')}
        </p>
        <div className="row">
          <input
            type="password"
            placeholder={t('settings.apiKeyPlaceholder')}
            value={apiKey}
            onChange={(e) => setApiKey(e.target.value)}
            autoComplete="off"
          />
          <button onClick={() => void saveApiKey()} disabled={!apiKey.trim()}>
            {t('settings.save')}
          </button>
        </div>
      </div>

      <div className="card">
        <h3>{t('settings.language')}</h3>
        <div className="row">
          <select
            value={lang}
            onChange={(e) => void onChangeLang(e.target.value as LanguageCode)}
          >
            <option value="ja">{t('lang.ja')}</option>
            <option value="en">{t('lang.en')}</option>
            <option value="de">{t('lang.de')}</option>
          </select>
        </div>
      </div>

      <div className="card">
        <h3>{t('settings.smtp')}</h3>
        <p className="muted">{t('settings.smtpDescription')}</p>
        <form
          onSubmit={(event) => {
            event.preventDefault();
            void saveSmtp();
          }}
        >
          <div className="row">
            <label>
              {t('settings.smtpHost')}
              <input
                type="text"
                value={smtp.host}
                onChange={(event) =>
                  setSmtp((current) => ({ ...current, host: event.target.value }))
                }
                required
                autoComplete="off"
              />
            </label>
            <label>
              {t('settings.smtpPort')}
              <input
                type="number"
                min="1"
                max="65535"
                value={smtp.port}
                onChange={(event) =>
                  setSmtp((current) => ({
                    ...current,
                    port: Number(event.target.value),
                  }))
                }
                required
              />
            </label>
            <label>
              {t('settings.smtpUser')}
              <input
                type="text"
                value={smtp.user}
                onChange={(event) =>
                  setSmtp((current) => ({ ...current, user: event.target.value }))
                }
                autoComplete="username"
              />
            </label>
            <label>
              {t('settings.smtpPassword')}
              <input
                type="password"
                value={smtpPassword}
                onChange={(event) => setSmtpPassword(event.target.value)}
                placeholder={
                  smtp.passwordConfigured
                    ? t('settings.smtpPasswordKeep')
                    : t('settings.smtpPasswordPlaceholder')
                }
                autoComplete="new-password"
              />
            </label>
            <label>
              {t('settings.smtpFrom')}
              <input
                type="email"
                value={smtp.from}
                onChange={(event) =>
                  setSmtp((current) => ({ ...current, from: event.target.value }))
                }
                required
                autoComplete="email"
              />
            </label>
            <button type="submit" disabled={smtpSaving}>
              {smtpSaving ? t('main.loading') : t('settings.save')}
            </button>
          </div>
        </form>
      </div>

      <div className="card">
        <h3>{t('settings.keywords')}</h3>
        <div className="row">
          <input
            type="text"
            placeholder={t('settings.addKeyword')}
            value={newWord}
            onChange={(e) => setNewWord(e.target.value)}
          />
          <button onClick={() => void addKeyword()}>{t('settings.add')}</button>
        </div>
        <div style={{ marginTop: 12 }}>
          {keywords.map((k) => (
            <span key={k.id} className="tag">
              {k.word}{' '}
              <a
                href="#"
                onClick={(e) => {
                  e.preventDefault();
                  void deleteKeyword(k.id);
                }}
              >
                ×
              </a>
            </span>
          ))}
        </div>
      </div>

      <div className="card">
        <h3>{t('settings.emails')}</h3>
        <div className="row">
          <input
            type="email"
            placeholder={t('settings.addEmail')}
            value={newEmail}
            onChange={(e) => setNewEmail(e.target.value)}
          />
          <button onClick={() => void addEmail()}>{t('settings.add')}</button>
        </div>
        <table style={{ marginTop: 12 }}>
          <tbody>
            {emails.map((e) => (
              <tr key={e.id}>
                <td>{e.address}</td>
                <td style={{ textAlign: 'right' }}>
                  <button
                    className="danger"
                    onClick={() => void deleteEmail(e.id)}
                  >
                    {t('settings.delete')}
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

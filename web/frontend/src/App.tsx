import { NavLink, Route, Routes } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { MainPage } from './pages/MainPage';
import { SettingsPage } from './pages/SettingsPage';

export function App() {
  const { t } = useTranslation();
  return (
    <div className="app">
      <nav className="nav">
        <span className="brand">▶ {t('app.title')}</span>
        <NavLink
          to="/"
          end
          className={({ isActive }) => (isActive ? 'active' : '')}
        >
          {t('app.nav.main')}
        </NavLink>
        <NavLink
          to="/settings"
          className={({ isActive }) => (isActive ? 'active' : '')}
        >
          {t('app.nav.settings')}
        </NavLink>
      </nav>
      <Routes>
        <Route path="/" element={<MainPage />} />
        <Route path="/settings" element={<SettingsPage />} />
      </Routes>
    </div>
  );
}

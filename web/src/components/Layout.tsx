import { useState } from 'react';
import { NavLink, Outlet } from 'react-router-dom';

const LINKS = [
  { to: '/dashboard', label: 'Dashboard', ico: '📊' },
  { to: '/customers', label: 'Clientes', ico: '👥' },
  { to: '/accounts', label: 'Contas', ico: '💳' },
  { to: '/transactions', label: 'Transações', ico: '🔁' },
  { to: '/reversals', label: 'Estornos', ico: '↩️' },
  { to: '/audit', label: 'Auditoria', ico: '📋' },
  { to: '/batch', label: 'Lote', ico: '📦' },
  { to: '/system', label: 'Sistema', ico: '⚙️' },
];

function Brand() {
  return (
    <div className="brand">
      <h1>
        LEGACY<span className="bank">BANK</span>
      </h1>
      <p>web banking · núcleo COBOL</p>
    </div>
  );
}

function Nav({ onNavigate }: { onNavigate?: () => void }) {
  return (
    <nav className="nav" aria-label="Navegação principal">
      {LINKS.map((l) => (
        <NavLink
          key={l.to}
          to={l.to}
          className={({ isActive }) => (isActive ? 'active' : '')}
          onClick={onNavigate}
        >
          <span className="ico" aria-hidden>
            {l.ico}
          </span>
          {l.label}
        </NavLink>
      ))}
    </nav>
  );
}

export default function Layout() {
  const [drawerOpen, setDrawerOpen] = useState(false);
  const close = () => setDrawerOpen(false);

  return (
    <div className="app">
      <aside className="sidebar">
        <Brand />
        <Nav />
        <div className="side-foot">TESTE 5 · API v1.1.0</div>
      </aside>

      <div className="main">
        <header className="topbar">
          <button
            className="hamburger"
            aria-label="Abrir menu"
            aria-expanded={drawerOpen}
            onClick={() => setDrawerOpen(true)}
          >
            ☰
          </button>
          <span className="brand-mini">
            LEGACY<span className="bank">BANK</span>
          </span>
        </header>
        <main className="content">
          <Outlet />
        </main>
      </div>

      {drawerOpen && (
        <>
          <div className="drawer-scrim" onClick={close} aria-hidden />
          <div className="drawer" role="dialog" aria-label="Menu">
            <Brand />
            <Nav onNavigate={close} />
            <div className="side-foot">
              <button className="btn ghost small" onClick={close}>
                ✕ Fechar
              </button>
            </div>
          </div>
        </>
      )}
    </div>
  );
}

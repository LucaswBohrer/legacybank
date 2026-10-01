import { useState } from 'react';
import { getToken, setToken } from '../api';

/** Tela de acesso demo: pede o LBAPI_TOKEN quando a API retorna 401. */
export default function TokenGate({
  onSaved,
  onClose,
}: {
  onSaved: () => void;
  onClose: () => void;
}) {
  const [value, setValue] = useState(getToken() ?? '');
  const [show, setShow] = useState(false);

  const save = () => {
    const t = value.trim();
    if (!t) return;
    setToken(t);
    onSaved();
  };

  return (
    <div className="modal-scrim" role="dialog" aria-label="Acesso demo">
      <div className="modal">
        <h2>🔑 Acesso demo</h2>
        <p style={{ color: 'var(--muted)' }}>
          Este ambiente público exige o token de acesso demo
          (<code>LBAPI_TOKEN</code>). Ele é gerado no deploy e{' '}
          <strong>não</strong> é publicado no repositório.
        </p>
        <label style={{ display: 'block', marginTop: 12 }}>
          Token de acesso
          <div style={{ display: 'flex', gap: 8, marginTop: 4 }}>
            <input
              type={show ? 'text' : 'password'}
              value={value}
              onChange={(e) => setValue(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && save()}
              placeholder="cole o token aqui"
              autoFocus
              style={{ flex: 1 }}
            />
            <button
              className="btn ghost small"
              onClick={() => setShow((s) => !s)}
              type="button"
            >
              {show ? '🙈' : '👁️'}
            </button>
          </div>
        </label>
        <p style={{ color: 'var(--muted)', fontSize: '0.85em', marginTop: 8 }}>
          Dica: o link de acesso pode incluir <code>?token=...</code> na URL —
          o app captura e guarda automaticamente (localStorage, só neste
          navegador).
        </p>
        <div style={{ display: 'flex', gap: 8, marginTop: 16, justifyContent: 'flex-end' }}>
          <button className="btn ghost" onClick={onClose} type="button">
            Fechar
          </button>
          <button className="btn primary" onClick={save} disabled={!value.trim()} type="button">
            Entrar
          </button>
        </div>
      </div>
    </div>
  );
}

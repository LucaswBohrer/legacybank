import { useState } from 'react';
import { getAudit } from '../api';
import { EmptyState, ErrorBox, Loading, useFetch } from '../components/States';

export default function Audit() {
  const [limit, setLimit] = useState('100');
  const [applied, setApplied] = useState({});
  const { data, error, loading, reload } = useFetch(
    () => getAudit(parseInt(limit, 10) || 100),
    [applied],
  );

  const events = data?.events ?? [];

  return (
    <>
      <h2>Auditoria</h2>
      <p className="page-sub">
        Buffer circular do core (últimas 300 entradas): HTTP, lote e operações
        financeiras.
      </p>

      <form
        className="toolbar"
        onSubmit={(e) => {
          e.preventDefault();
          setApplied({});
        }}
      >
        <select
          value={limit}
          onChange={(e) => setLimit(e.target.value)}
          aria-label="Limite de entradas"
        >
          {['50', '100', '200', '300'].map((l) => (
            <option key={l} value={l}>
              últimas {l}
            </option>
          ))}
        </select>
        <button className="btn" type="submit">
          Aplicar
        </button>
        <span className="spacer" />
        <button className="btn ghost" type="button" onClick={reload}>
          ↻ Atualizar
        </button>
      </form>

      {loading && <Loading label="Carregando auditoria…" />}
      {error && <ErrorBox error={error} onRetry={reload} />}

      {!loading && !error && events.length === 0 && (
        <EmptyState
          icon="📋"
          title="Sem entradas de auditoria"
          hint="As operações da API aparecem aqui."
        />
      )}

      {!loading && !error && events.length > 0 && (
        <div className="audit-list">
          {events.map((ev, i) => (
            <div className="audit-row" key={i}>
              <span className="ts">{ev.timestamp || '—'}</span>
              <span>{ev.event}</span>
            </div>
          ))}
        </div>
      )}
    </>
  );
}

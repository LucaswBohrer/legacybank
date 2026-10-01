import { ApiError } from '../api';

export function Loading({ label = 'Carregando…' }: { label?: string }) {
  return (
    <div role="status" aria-label={label}>
      <div className="spinner" />
      <p style={{ textAlign: 'center', color: 'var(--muted)' }}>{label}</p>
    </div>
  );
}

export function SkeletonList({ rows = 5 }: { rows?: number }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }} aria-hidden>
      {Array.from({ length: rows }, (_, i) => (
        <div key={i} className="skeleton" style={{ height: 44 }} />
      ))}
    </div>
  );
}

export function EmptyState({
  icon = '📭',
  title,
  hint,
  action,
}: {
  icon?: string;
  title: string;
  hint?: string;
  action?: React.ReactNode;
}) {
  return (
    <div className="state-box">
      <div className="big-ico">{icon}</div>
      <h3>{title}</h3>
      {hint && <p>{hint}</p>}
      {action}
    </div>
  );
}

function describeError(err: unknown): { title: string; detail: string; kind: 'err' | 'warn' } {
  if (err instanceof ApiError) {
    if (err.isOffline) {
      return {
        title: 'API inacessível',
        detail:
          'Não foi possível alcançar a API. Verifique se o servidor (api/lbapi.py) está rodando e tente novamente.',
        kind: 'err',
      };
    }
    if (err.status === 503) {
      return {
        title: 'Core COBOL indisponível',
        detail: `A API respondeu, mas o núcleo COBOL falhou: ${err.message}`,
        kind: 'err',
      };
    }
    if (err.status === 422) {
      return {
        title: `Rejeitado pelo core${err.rc !== undefined ? ` (RC ${err.rc})` : ''}`,
        detail: err.message,
        kind: 'warn',
      };
    }
    if (err.status === 400) {
      return {
        title: 'Dados inválidos',
        detail: err.message,
        kind: 'warn',
      };
    }
    if (err.status === 404) {
      return {
        title: 'Não encontrado',
        detail: err.message,
        kind: 'warn',
      };
    }
    return { title: `Erro ${err.status}`, detail: err.message, kind: 'err' };
  }
  return {
    title: 'Erro inesperado',
    detail: err instanceof Error ? err.message : String(err),
    kind: 'err',
  };
}

export function ErrorBox({
  error,
  onRetry,
}: {
  error: unknown;
  onRetry?: () => void;
}) {
  const { title, detail, kind } = describeError(error);
  const icon = kind === 'err' ? '🔌' : '⚠️';
  return (
    <div className={`alert ${kind}`} role="alert">
      <strong>
        {icon} {title}
      </strong>
      <div style={{ marginTop: 4 }}>{detail}</div>
      {onRetry && (
        <div style={{ marginTop: 10 }}>
          <button className="btn small" onClick={onRetry}>
            ↻ Tentar novamente
          </button>
        </div>
      )}
    </div>
  );
}

/** Hook simples de fetch com estados loading/error. */
import { useCallback, useEffect, useState } from 'react';

export function useFetch<T>(fn: () => Promise<T>, deps: unknown[] = []) {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<unknown>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      setData(await fn());
    } catch (e) {
      setError(e);
    } finally {
      setLoading(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);

  useEffect(() => {
    load();
  }, [load]);

  return { data, error, loading, reload: load };
}

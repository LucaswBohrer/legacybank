import { useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { getTransaction, getTransactions } from '../api';
import { formatCents } from '../money';
import { EmptyState, ErrorBox, Loading, useFetch } from '../components/States';

export function resultBadge(r: string) {
  if (r === 'OK') return <span className="badge ok">OK</span>;
  if (r === 'REJEITADA') return <span className="badge err">rejeitada</span>;
  if (r === 'DUPLICADA') return <span className="badge warn">duplicada</span>;
  return <span className="badge neutral">{r}</span>;
}

const RESULT_OPTIONS = ['', 'OK', 'REJEITADA', 'DUPLICADA'];

export default function Transactions() {
  const [account, setAccount] = useState('');
  const [result, setResult] = useState('');
  const [q, setQ] = useState('');
  const [limit, setLimit] = useState('50');
  const [applied, setApplied] = useState({});

  const { data, error, loading, reload } = useFetch(
    () =>
      getTransactions({
        account: account.trim() || undefined,
        result: result || undefined,
        q: q.trim() || undefined,
        limit: parseInt(limit, 10) || 50,
      }),
    [applied],
  );

  function apply(e: React.FormEvent) {
    e.preventDefault();
    setApplied({});
  }

  const items = data?.transactions ?? [];

  return (
    <>
      <h2>Transações</h2>
      <p className="page-sub">
        Registry de TX-IDs do core. Rejeitadas mostram o motivo do COBOL.
      </p>

      <form className="toolbar" onSubmit={apply}>
        <input
          type="search"
          placeholder="Conta (8 dígitos)"
          value={account}
          onChange={(e) => setAccount(e.target.value.replace(/\D/g, '').slice(0, 8))}
          aria-label="Filtrar por conta"
          style={{ width: 150 }}
        />
        <select
          value={result}
          onChange={(e) => setResult(e.target.value)}
          aria-label="Filtrar por resultado"
        >
          {RESULT_OPTIONS.map((r) => (
            <option key={r} value={r}>
              {r === '' ? 'Todos os resultados' : r.toLowerCase()}
            </option>
          ))}
        </select>
        <input
          type="search"
          placeholder="Buscar TX-ID ou detalhe…"
          value={q}
          onChange={(e) => setQ(e.target.value)}
          aria-label="Buscar transação"
          style={{ minWidth: 200 }}
        />
        <select
          value={limit}
          onChange={(e) => setLimit(e.target.value)}
          aria-label="Limite"
        >
          {['20', '50', '100', '200'].map((l) => (
            <option key={l} value={l}>
              {l} itens
            </option>
          ))}
        </select>
        <button className="btn primary" type="submit">
          Filtrar
        </button>
      </form>

      {loading && <Loading label="Carregando transações…" />}
      {error && <ErrorBox error={error} onRetry={reload} />}

      {!loading && !error && items.length === 0 && (
        <EmptyState
          icon="🔁"
          title="Nenhuma transação encontrada"
          hint="Ajuste os filtros ou faça uma operação em uma conta."
        />
      )}

      {!loading && !error && items.length > 0 && (
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>TX-ID</th>
                <th>Data/hora</th>
                <th>Resultado</th>
                <th>Tipo</th>
                <th>Conta</th>
                <th className="num">Valor</th>
                <th className="num">Tarifa</th>
              </tr>
            </thead>
            <tbody>
              {items.map((t) => (
                <tr key={t.tx_id}>
                  <td className="mono">
                    <Link to={`/transactions/${encodeURIComponent(t.tx_id)}`}>
                      {t.tx_id}
                    </Link>
                  </td>
                  <td className="mono">{t.timestamp}</td>
                  <td>{resultBadge(t.result)}</td>
                  <td>
                    <span className="badge info">{t.kind}</span>
                  </td>
                  <td className="mono">
                    {t.account ? (
                      <Link to={`/accounts/${t.account}`}>{t.account}</Link>
                    ) : (
                      '—'
                    )}
                  </td>
                  <td className="num">
                    {t.value_cents !== null ? formatCents(t.value_cents) : '—'}
                  </td>
                  <td className="num">
                    {t.fee_cents ? formatCents(t.fee_cents) : '—'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}

export function TransactionDetail() {
  const { txId = '' } = useParams();
  const { data, error, loading, reload } = useFetch(
    () => getTransaction(txId),
    [txId],
  );

  return (
    <>
      <h2>
        Transação <span className="mono" style={{ fontSize: 18 }}>{txId}</span>
      </h2>
      <p className="page-sub">
        <Link to="/transactions">← Voltar para transações</Link>
      </p>

      {loading && <Loading label="Carregando transação…" />}
      {error && <ErrorBox error={error} onRetry={reload} />}

      {!loading && !error && data && (
        <div className="panel">
          <dl className="kv">
            <dt>TX-ID</dt>
            <dd className="mono">{data.tx_id}</dd>
            <dt>Data/hora</dt>
            <dd className="mono">{data.timestamp}</dd>
            <dt>Resultado</dt>
            <dd>{resultBadge(data.result)}</dd>
            <dt>Detalhe (core)</dt>
            <dd className="mono" style={{ whiteSpace: 'pre-wrap' }}>
              {data.detail}
            </dd>
          </dl>
          <div className="action-bar">
            <Link
              className="btn"
              to={`/reversals?original=${encodeURIComponent(data.tx_id)}`}
            >
              ↩️ Estornar esta transação
            </Link>
          </div>
        </div>
      )}
    </>
  );
}

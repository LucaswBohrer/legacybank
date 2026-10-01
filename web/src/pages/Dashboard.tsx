import { Link } from 'react-router-dom';
import { getDashboard } from '../api';
import { formatCents } from '../money';
import { EmptyState, ErrorBox, Loading, useFetch } from '../components/States';

export default function Dashboard() {
  const { data, error, loading, reload } = useFetch(getDashboard);

  if (loading) return <Loading label="Carregando dashboard…" />;
  if (error)
    return (
      <>
        <h2>Dashboard</h2>
        <ErrorBox error={error} onRetry={reload} />
      </>
    );
  if (!data) return null;

  const cards = [
    { label: 'Clientes', value: String(data.customers), detail: 'cadastrados no core' },
    { label: 'Contas', value: String(data.accounts), detail: `${data.accounts_active} ativas · ${data.accounts_blocked} bloqueadas · ${data.accounts_closed} encerradas` },
    { label: 'Saldo total', value: formatCents(data.total_balance_cents), money: true, detail: 'soma de todas as contas (core COBOL)' },
    { label: 'Transações', value: String(data.transactions), detail: `${data.movements} movimentos no journal` },
  ];

  return (
    <>
      <h2>Dashboard</h2>
      <p className="page-sub">
        Visão geral do núcleo bancário. Todos os valores vêm do core COBOL.
      </p>

      <div className="grid cards">
        {cards.map((c) => (
          <div className="card" key={c.label}>
            <h3>{c.label}</h3>
            <div className={`big${c.money ? ' money' : ''}`}>{c.value}</div>
            <div className="detail">{c.detail}</div>
          </div>
        ))}
      </div>

      <div className="panel">
        <h3>Movimentos recentes</h3>
        {data.recent.length === 0 ? (
          <EmptyState
            icon="📭"
            title="Nenhum movimento ainda"
            hint="Faça um depósito para ver o journal aqui."
          />
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Data/hora</th>
                  <th>Tipo</th>
                  <th>Conta</th>
                  <th className="num">Valor</th>
                  <th>TX-ID</th>
                </tr>
              </thead>
              <tbody>
                {data.recent.map((m) => (
                  <tr key={m.seq}>
                    <td className="mono">{m.timestamp}</td>
                    <td>
                      <span className="badge info">{m.type}</span>
                    </td>
                    <td className="mono">
                      <Link to={`/accounts/${m.account}`}>{m.account}</Link>
                      {m.dest_account ? (
                        <>
                          {' → '}
                          <Link to={`/accounts/${m.dest_account}`}>{m.dest_account}</Link>
                        </>
                      ) : null}
                    </td>
                    <td className="num">{formatCents(Number(m.value_cents) || 0)}</td>
                    <td className="mono">
                      <Link to={`/transactions/${encodeURIComponent(m.tx_id)}`}>
                        {m.tx_id}
                      </Link>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </>
  );
}

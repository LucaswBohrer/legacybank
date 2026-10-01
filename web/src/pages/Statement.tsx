import { Link, useParams } from 'react-router-dom';
import { getStatement } from '../api';
import { formatCents } from '../money';
import { effectBadge } from '../components/FinancialModal';
import { EmptyState, ErrorBox, Loading, useFetch } from '../components/States';

export default function Statement() {
  const { id = '' } = useParams();
  const { data, error, loading, reload } = useFetch(() => getStatement(id), [id]);

  return (
    <>
      <h2>
        Extrato — <span className="mono">{id}</span>
      </h2>
      <p className="page-sub">
        <Link to={`/accounts/${id}`}>← Voltar para a conta</Link>
      </p>

      {loading && <Loading label="Carregando extrato…" />}
      {error && <ErrorBox error={error} onRetry={reload} />}

      {!loading && !error && data && (
        <>
          <div className="grid cards" style={{ marginBottom: 16 }}>
            <div className="card">
              <h3>Saldo anterior</h3>
              <div className="big">{formatCents(data.opening_balance_cents)}</div>
            </div>
            <div className="card">
              <h3>Saldo atual</h3>
              <div className="big money">{formatCents(data.current_balance_cents)}</div>
              <div className="detail">calculado pelo core COBOL</div>
            </div>
            <div className="card">
              <h3>Movimentos</h3>
              <div className="big">{data.movements.length}</div>
            </div>
          </div>

          {data.movements.length === 0 ? (
            <EmptyState
              icon="📄"
              title="Sem movimentos"
              hint="Esta conta ainda não tem lançamentos no journal."
            />
          ) : (
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Data/hora</th>
                    <th>Tipo</th>
                    <th className="num">Efeito</th>
                    <th className="num">Saldo após</th>
                    <th>TX-ID</th>
                  </tr>
                </thead>
                <tbody>
                  {data.movements.map((m, i) => (
                    <tr key={`${m.tx_id}-${i}`}>
                      <td className="mono">{m.timestamp}</td>
                      <td>
                        <span className="badge info">{m.type}</span>
                      </td>
                      <td className="num">{effectBadge(m.effect_cents)}</td>
                      <td className="num">{formatCents(m.running_balance_cents)}</td>
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
        </>
      )}
    </>
  );
}

import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { ApiError, createAccount, getAccounts, getCustomers } from '../api';
import { formatCents } from '../money';
import Modal from '../components/Modal';
import { EmptyState, ErrorBox, Loading, useFetch } from '../components/States';

export function statusBadge(s: string) {
  if (s === 'A') return <span className="badge ok">ativa</span>;
  if (s === 'B') return <span className="badge warn">bloqueada</span>;
  if (s === 'E') return <span className="badge neutral">encerrada</span>;
  return <span className="badge neutral">{s}</span>;
}

export function typeBadge(t: string) {
  return t === 'CC' ? (
    <span className="badge info">CC</span>
  ) : (
    <span className="badge neutral">{t}</span>
  );
}

const STATUS_LABEL: Record<string, string> = {
  '': 'Todas',
  A: 'Ativas',
  B: 'Bloqueadas',
  E: 'Encerradas',
};

export default function Accounts() {
  const [status, setStatus] = useState('');
  const { data, error, loading, reload } = useFetch(
    () => getAccounts(status || undefined),
    [status],
  );
  const [showNew, setShowNew] = useState(false);

  const accounts = useMemo(() => data?.accounts ?? [], [data]);

  return (
    <>
      <h2>Contas</h2>
      <p className="page-sub">Contas correntes (CC) e poupança (CP) do core COBOL.</p>

      <div className="toolbar">
        <select
          value={status}
          onChange={(e) => setStatus(e.target.value)}
          aria-label="Filtrar por status"
        >
          {Object.entries(STATUS_LABEL).map(([v, l]) => (
            <option key={v} value={v}>
              {l}
            </option>
          ))}
        </select>
        <span className="spacer" />
        <button className="btn primary" onClick={() => setShowNew(true)}>
          ＋ Nova conta
        </button>
      </div>

      {loading && <Loading label="Carregando contas…" />}
      {error && <ErrorBox error={error} onRetry={reload} />}

      {!loading && !error && accounts.length === 0 && (
        <EmptyState
          icon="💳"
          title="Nenhuma conta encontrada"
          hint="Abra a primeira conta para um cliente existente."
          action={
            <button className="btn primary" onClick={() => setShowNew(true)}>
              ＋ Nova conta
            </button>
          }
        />
      )}

      {!loading && !error && accounts.length > 0 && (
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Conta</th>
                <th>Cliente</th>
                <th>Tipo</th>
                <th>Status</th>
                <th className="num">Saldo</th>
                <th>Abertura</th>
              </tr>
            </thead>
            <tbody>
              {accounts.map((a) => (
                <tr key={a.account}>
                  <td className="mono">
                    <Link to={`/accounts/${a.account}`}>{a.account}</Link>
                  </td>
                  <td className="mono">{a.customer_id}</td>
                  <td>{typeBadge(a.type)}</td>
                  <td>{statusBadge(a.status)}</td>
                  <td className="num">{formatCents(a.balance_cents)}</td>
                  <td className="mono">{a.opened}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {showNew && (
        <NewAccountModal onClose={() => setShowNew(false)} onCreated={reload} />
      )}
    </>
  );
}

function NewAccountModal({
  onClose,
  onCreated,
}: {
  onClose: () => void;
  onCreated: () => void;
}) {
  const { data: custData } = useFetch(getCustomers);
  const [customerId, setCustomerId] = useState('');
  const [type, setType] = useState('CC');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<unknown>(null);
  const [created, setCreated] = useState<string | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!customerId || busy) return;
    setBusy(true);
    setErr(null);
    try {
      const r = await createAccount({ customer_id: customerId, type });
      setCreated(r.account);
      onCreated();
    } catch (e2) {
      setErr(e2);
    } finally {
      setBusy(false);
    }
  }

  if (created) {
    return (
      <Modal title="Conta aberta" confirmLabel="Fechar" onConfirm={onClose} onCancel={onClose}>
        <div className="alert ok">
          ✅ Conta <strong className="mono">{created}</strong> aberta no core COBOL.{' '}
          <Link to={`/accounts/${created}`}>Ver detalhe →</Link>
        </div>
      </Modal>
    );
  }

  return (
    <Modal
      title="Nova conta"
      confirmLabel="Abrir conta"
      formId="new-account-form"
      onCancel={onClose}
      busy={busy}
    >
      <form
        id="new-account-form"
        className="form"
        onSubmit={submit}
        style={{ maxWidth: '100%' }}
      >
        <div className="field">
          <label htmlFor="na-customer">Cliente</label>
          <select
            id="na-customer"
            value={customerId}
            onChange={(e) => setCustomerId(e.target.value)}
            required
            autoFocus
          >
            <option value="">Selecione…</option>
            {(custData?.customers ?? []).map((c) => (
              <option key={c.id} value={c.id}>
                {c.id} — {c.name}
              </option>
            ))}
          </select>
        </div>
        <div className="field">
          <label htmlFor="na-type">Tipo</label>
          <select id="na-type" value={type} onChange={(e) => setType(e.target.value)}>
            <option value="CC">CC — conta corrente</option>
            <option value="CP">CP — poupança</option>
          </select>
        </div>
        {err instanceof ApiError && err.status === 422 ? (
          <div className="alert warn" role="alert">
            ⚠️ Rejeitado pelo core (RC {err.rc}): {err.message}
          </div>
        ) : err ? (
          <ErrorBox error={err} />
        ) : null}
      </form>
    </Modal>
  );
}

import { useMemo, useState } from 'react';
import { ApiError, createCustomer, getCustomers } from '../api';
import type { Customer } from '../types';
import Modal from '../components/Modal';
import { EmptyState, ErrorBox, Loading, useFetch } from '../components/States';

function statusBadge(s: string) {
  return s === 'A' ? (
    <span className="badge ok">ativo</span>
  ) : (
    <span className="badge neutral">{s}</span>
  );
}

export default function Customers() {
  const { data, error, loading, reload } = useFetch(getCustomers);
  const [q, setQ] = useState('');
  const [showNew, setShowNew] = useState(false);

  const filtered = useMemo(() => {
    const list = data?.customers ?? [];
    const t = q.trim().toLowerCase();
    if (!t) return list;
    return list.filter(
      (c) =>
        c.id.toLowerCase().includes(t) ||
        c.name.toLowerCase().includes(t) ||
        c.cpf.includes(t) ||
        c.email.toLowerCase().includes(t),
    );
  }, [data, q]);

  return (
    <>
      <h2>Clientes</h2>
      <p className="page-sub">Cadastro validado pelo core COBOL (CPF, unicidade).</p>

      <div className="toolbar">
        <input
          type="search"
          placeholder="Buscar por nome, CPF, e-mail ou ID…"
          value={q}
          onChange={(e) => setQ(e.target.value)}
          aria-label="Buscar clientes"
          style={{ minWidth: 240 }}
        />
        <span className="spacer" />
        <button className="btn primary" onClick={() => setShowNew(true)}>
          ＋ Novo cliente
        </button>
      </div>

      {loading && <Loading label="Carregando clientes…" />}
      {error && <ErrorBox error={error} onRetry={reload} />}

      {!loading && !error && filtered.length === 0 && (
        <EmptyState
          icon="👥"
          title={q ? 'Nenhum cliente encontrado' : 'Nenhum cliente cadastrado'}
          hint={
            q
              ? 'Ajuste a busca ou cadastre um novo cliente.'
              : 'Cadastre o primeiro cliente para começar.'
          }
          action={
            !q ? (
              <button className="btn primary" onClick={() => setShowNew(true)}>
                ＋ Novo cliente
              </button>
            ) : undefined
          }
        />
      )}

      {!loading && !error && filtered.length > 0 && (
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>ID</th>
                <th>Nome</th>
                <th>CPF</th>
                <th>E-mail</th>
                <th>Abertura</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map((c: Customer) => (
                <tr key={c.id}>
                  <td className="mono">{c.id}</td>
                  <td>{c.name}</td>
                  <td className="mono">{c.cpf}</td>
                  <td>{c.email}</td>
                  <td className="mono">{c.opened}</td>
                  <td>{statusBadge(c.status)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {showNew && (
        <NewCustomerModal onClose={() => setShowNew(false)} onCreated={reload} />
      )}
    </>
  );
}

function NewCustomerModal({
  onClose,
  onCreated,
}: {
  onClose: () => void;
  onCreated: () => void;
}) {
  const [name, setName] = useState('');
  const [cpf, setCpf] = useState('');
  const [email, setEmail] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<unknown>(null);
  const [createdId, setCreatedId] = useState<string | null>(null);

  const valid =
    name.trim().length > 0 && cpf.trim().length > 0 && email.trim().length > 0;

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!valid || busy) return;
    setBusy(true);
    setErr(null);
    try {
      const r = await createCustomer({
        name: name.trim(),
        cpf: cpf.trim(),
        email: email.trim(),
      });
      setCreatedId(r.id);
      onCreated();
    } catch (e2) {
      setErr(e2);
    } finally {
      setBusy(false);
    }
  }

  if (createdId) {
    return (
      <Modal title="Cliente criado" confirmLabel="Fechar" onConfirm={onClose} onCancel={onClose}>
        <div className="alert ok">
          ✅ Cliente <strong className="mono">{createdId}</strong> cadastrado no core COBOL.
        </div>
      </Modal>
    );
  }

  return (
    <Modal
      title="Novo cliente"
      confirmLabel="Cadastrar"
      formId="new-customer-form"
      onCancel={onClose}
      busy={busy}
    >
      <form
        className="form"
        onSubmit={submit}
        id="new-customer-form"
        style={{ maxWidth: '100%' }}
      >
        <div className="field">
          <label htmlFor="nc-name">Nome</label>
          <input
            id="nc-name"
            value={name}
            onChange={(e) => setName(e.target.value)}
            maxLength={60}
            required
            autoFocus
          />
        </div>
        <div className="field">
          <label htmlFor="nc-cpf">CPF</label>
          <input
            id="nc-cpf"
            value={cpf}
            onChange={(e) => setCpf(e.target.value)}
            maxLength={14}
            placeholder="000.000.000-00"
            required
          />
          <span className="hint">Validado pelo core (dígitos verificadores).</span>
        </div>
        <div className="field">
          <label htmlFor="nc-email">E-mail</label>
          <input
            id="nc-email"
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            maxLength={60}
            required
          />
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

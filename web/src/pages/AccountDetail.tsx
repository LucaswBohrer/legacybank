import { useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import {
  accountAction,
  deposit,
  getAccount,
  transfer,
  withdraw,
} from '../api';
import { formatCents } from '../money';
import FinancialModal, { type OpKind } from '../components/FinancialModal';
import Modal from '../components/Modal';
import { EmptyState, ErrorBox, Loading, useFetch } from '../components/States';
import { statusBadge, typeBadge } from './Accounts';

type StatusOp = 'block' | 'unblock' | 'close' | null;

const STATUS_OP_META: Record<
  Exclude<StatusOp, null>,
  { title: string; label: string; danger: boolean; hint: string }
> = {
  block: {
    title: 'Bloquear conta',
    label: 'Bloquear',
    danger: true,
    hint: 'Contas bloqueadas rejeitam débito/crédito no core até o desbloqueio.',
  },
  unblock: {
    title: 'Desbloquear conta',
    label: 'Desbloquear',
    danger: false,
    hint: 'A conta volta a aceitar operações normalmente.',
  },
  close: {
    title: 'Encerrar conta',
    label: 'Encerrar',
    danger: true,
    hint: 'O core só permite encerrar conta com saldo zero.',
  },
};

export default function AccountDetail() {
  const { id = '' } = useParams();
  const { data, error, loading, reload } = useFetch(() => getAccount(id), [id]);
  const [finOp, setFinOp] = useState<OpKind | null>(null);
  const [statusOp, setStatusOp] = useState<StatusOp>(null);
  const [busy, setBusy] = useState(false);
  const [opErr, setOpErr] = useState<unknown>(null);
  const [opOk, setOpOk] = useState<string | null>(null);

  async function runStatusOp() {
    if (!statusOp) return;
    setBusy(true);
    setOpErr(null);
    setOpOk(null);
    try {
      await accountAction(id, statusOp);
      setOpOk(STATUS_OP_META[statusOp].label + ' executado com sucesso.');
      setStatusOp(null);
      reload();
    } catch (e) {
      setOpErr(e);
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <h2>
        Conta <span className="mono">{id}</span>
      </h2>
      <p className="page-sub">
        <Link to="/accounts">← Voltar para contas</Link>
      </p>

      {loading && <Loading label="Carregando conta…" />}
      {error && <ErrorBox error={error} onRetry={reload} />}

      {!loading && !error && data && (
        <>
          {opOk && (
            <div className="alert ok" role="status">
              ✅ {opOk}
            </div>
          )}
          {opErr ? <ErrorBox error={opErr} /> : null}

          <div className="panel">
            <dl className="kv">
              <dt>Número</dt>
              <dd className="mono">{data.account}</dd>
              <dt>Cliente</dt>
              <dd className="mono">{data.customer_id}</dd>
              <dt>Tipo</dt>
              <dd>{typeBadge(data.type)}</dd>
              <dt>Status</dt>
              <dd>{statusBadge(data.status)}</dd>
              <dt>Saldo</dt>
              <dd style={{ fontSize: 20, fontWeight: 700 }}>
                {formatCents(data.balance_cents)}
              </dd>
              <dt>Abertura</dt>
              <dd className="mono">{data.opened}</dd>
            </dl>
          </div>

          <div className="action-bar">
            <button className="btn primary" onClick={() => setFinOp('deposit')}>
              💰 Depositar
            </button>
            <button className="btn" onClick={() => setFinOp('withdraw')}>
              💸 Sacar
            </button>
            <button className="btn" onClick={() => setFinOp('transfer')}>
              🔀 Transferir
            </button>
            <Link className="btn ghost" to={`/accounts/${id}/statement`}>
              📄 Extrato
            </Link>
            {data.status === 'A' && (
              <button className="btn danger" onClick={() => setStatusOp('block')}>
                🔒 Bloquear
              </button>
            )}
            {data.status === 'B' && (
              <button className="btn" onClick={() => setStatusOp('unblock')}>
                🔓 Desbloquear
              </button>
            )}
            {data.status !== 'E' && (
              <button className="btn danger" onClick={() => setStatusOp('close')}>
                🗑 Encerrar
              </button>
            )}
          </div>

          {data.status === 'B' && (
            <div className="alert warn">
              ⚠️ Conta bloqueada: o core rejeita novas operações até o desbloqueio.
            </div>
          )}
          {data.status === 'E' && (
            <div className="alert info">
              ℹ️ Conta encerrada: somente leitura (extrato e consultas).
            </div>
          )}
        </>
      )}

      {!loading && !error && !data && (
        <EmptyState icon="💳" title="Conta não encontrada" />
      )}

      {finOp && data && (
        <FinancialModal
          kind={finOp}
          account={data.account}
          onClose={() => setFinOp(null)}
          onDone={reload}
          run={(args) => {
            if (finOp === 'deposit') return deposit(args);
            if (finOp === 'withdraw') return withdraw(args);
            return transfer({
              tx_id: args.tx_id,
              from_account: args.from_account as string,
              to_account: args.to_account as string,
              amount: args.amount,
            });
          }}
        />
      )}

      {statusOp && (
        <Modal
          title={STATUS_OP_META[statusOp].title}
          danger={STATUS_OP_META[statusOp].danger}
          confirmLabel={STATUS_OP_META[statusOp].label}
          onConfirm={runStatusOp}
          onCancel={() => {
            setStatusOp(null);
            setOpErr(null);
          }}
          busy={busy}
        >
          <p>
            {STATUS_OP_META[statusOp].hint} Conta{' '}
            <strong className="mono">{id}</strong>.
          </p>
          {opErr ? <ErrorBox error={opErr} /> : null}
        </Modal>
      )}
    </>
  );
}

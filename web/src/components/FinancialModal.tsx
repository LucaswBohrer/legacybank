import { useState } from 'react';
import { ApiError } from '../api';
import type { FinancialResult } from '../types';
import { centsToAmount, formatCents, formatSignedCents, newTxId, parseBRLToCents } from '../money';
import Modal from './Modal';
import { ErrorBox } from './States';

export type OpKind = 'deposit' | 'withdraw' | 'transfer';

interface Props {
  kind: OpKind;
  account: string;
  onClose: () => void;
  onDone: () => void;
  run: (args: {
    tx_id: string;
    account: string;
    amount: string;
    from_account?: string;
    to_account?: string;
  }) => Promise<FinancialResult>;
}

const META: Record<OpKind, { title: string; danger: boolean; needsConfirm: boolean; destLabel: string }> = {
  deposit: { title: 'Depositar', danger: false, needsConfirm: false, destLabel: '' },
  withdraw: { title: 'Sacar', danger: true, needsConfirm: true, destLabel: '' },
  transfer: { title: 'Transferir', danger: true, needsConfirm: true, destLabel: 'Conta destino' },
};

/**
 * Modal de operação financeira. Gera tx_id automaticamente (editável),
 * valida o envelope localmente e deixa a regra financeira para o core.
 * Mostra replay idempotente de forma explícita.
 */
export default function FinancialModal({ kind, account, onClose, onDone, run }: Props) {
  const meta = META[kind];
  const [txId, setTxId] = useState(newTxId());
  const [amountRaw, setAmountRaw] = useState('');
  const [dest, setDest] = useState('');
  const [fieldErr, setFieldErr] = useState<string | null>(null);
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<FinancialResult | null>(null);
  const [err, setErr] = useState<unknown>(null);

  const cents = parseBRLToCents(amountRaw);

  function validate(): string | null {
    if (!/^[A-Za-z0-9_-]{1,24}$/.test(txId.trim()))
      return 'tx_id deve ter 1–24 caracteres [A-Za-z0-9_-].';
    if (cents === null || cents <= 0)
      return 'Informe um valor válido maior que zero (ex.: 1.250,50).';
    if (kind === 'transfer') {
      if (!/^\d{8}$/.test(dest.trim())) return 'Conta destino deve ter 8 dígitos.';
      if (dest.trim() === account) return 'Origem e destino não podem ser iguais.';
    }
    return null;
  }

  async function execute() {
    const problem = validate();
    if (problem) {
      setFieldErr(problem);
      return;
    }
    setFieldErr(null);
    if (meta.needsConfirm && !confirming) {
      setConfirming(true);
      return;
    }
    setBusy(true);
    setErr(null);
    try {
      const r = await run({
        tx_id: txId.trim(),
        account,
        amount: centsToAmount(cents as number),
        ...(kind === 'transfer'
          ? { from_account: account, to_account: dest.trim() }
          : {}),
      });
      setResult(r);
      setConfirming(false);
      onDone();
    } catch (e) {
      setErr(e);
      setConfirming(false);
    } finally {
      setBusy(false);
    }
  }

  function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    execute();
  }

  // ---- resultado -------------------------------------------------
  if (result) {
    const isReplay = result.replay === true || result.status === 'duplicate';
    return (
      <Modal title={meta.title} confirmLabel="Fechar" onConfirm={onClose} onCancel={onClose}>
        {isReplay ? (
          <div className="alert info" role="status">
            🔁 <strong>Replay idempotente.</strong> Esta transação (
            <code>{result.tx_id}</code>) já havia sido processada — o saldo não
            foi alterado novamente.
          </div>
        ) : (
          <div className="alert ok" role="status">
            ✅ Operação aceita pelo core (RC {result.rc}). TX-ID{' '}
            <code>{result.tx_id}</code>.
          </div>
        )}
      </Modal>
    );
  }

  // ---- confirmação forte -----------------------------------------
  if (confirming) {
    return (
      <Modal
        title={`Confirmar ${meta.title.toLowerCase()}`}
        danger={meta.danger}
        confirmLabel={`Confirmar ${meta.title.toLowerCase()}`}
        onConfirm={execute}
        onCancel={() => setConfirming(false)}
        busy={busy}
      >
        <p>
          {kind === 'withdraw' && (
            <>
              Sacar <strong>{formatCents(cents as number)}</strong> da conta{' '}
              <strong className="mono">{account}</strong>? A tarifa do core será
              aplicada pelo COBOL.
            </>
          )}
          {kind === 'transfer' && (
            <>
              Transferir <strong>{formatCents(cents as number)}</strong> de{' '}
              <strong className="mono">{account}</strong> para{' '}
              <strong className="mono">{dest.trim()}</strong>? A tarifa do core
              será aplicada pelo COBOL.
            </>
          )}
        </p>
        <p className="mono" style={{ fontSize: 12 }}>
          tx_id: {txId.trim()}
        </p>
        {err ? <ErrorBox error={err} /> : null}
      </Modal>
    );
  }

  // ---- formulário --------------------------------------------------
  return (
    <Modal
      title={`${meta.title} — conta ${account}`}
      confirmLabel={meta.title}
      danger={meta.danger}
      formId={`fin-${kind}-form`}
      onCancel={onClose}
      busy={busy}
    >
      <form id={`fin-${kind}-form`} className="form" onSubmit={onSubmit} style={{ maxWidth: '100%' }}>
        {kind === 'transfer' && (
          <div className="field">
            <label htmlFor={`fin-${kind}-dest`}>Conta destino</label>
            <input
              id={`fin-${kind}-dest`}
              value={dest}
              onChange={(e) => setDest(e.target.value.replace(/\D/g, '').slice(0, 8))}
              placeholder="8 dígitos"
              inputMode="numeric"
              required
              autoFocus
            />
          </div>
        )}
        <div className="field">
          <label htmlFor={`fin-${kind}-amount`}>Valor (R$)</label>
          <input
            id={`fin-${kind}-amount`}
            value={amountRaw}
            onChange={(e) => setAmountRaw(e.target.value)}
            placeholder="1.250,50"
            inputMode="decimal"
            required
            autoFocus={kind !== 'transfer'}
          />
          <span className="hint">
            Formato brasileiro. A validação financeira é do core COBOL.
          </span>
        </div>
        <div className="field">
          <label htmlFor={`fin-${kind}-txid`}>TX-ID (idempotência)</label>
          <input
            id={`fin-${kind}-txid`}
            value={txId}
            onChange={(e) => setTxId(e.target.value)}
            maxLength={24}
            className="mono"
            required
          />
          <span className="hint">
            Gerado automaticamente; reutilizar o mesmo TX-ID repete sem duplicar
            (replay).
          </span>
        </div>
        {fieldErr && (
          <div className="alert warn" role="alert">
            ⚠️ {fieldErr}
          </div>
        )}
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

/** Linha de resultado reutilizável p/ exibir efeito em extrato. */
export function effectBadge(cents: number) {
  return (
    <span style={{ color: cents >= 0 ? 'var(--green)' : 'var(--red)' }}>
      {formatSignedCents(cents)}
    </span>
  );
}

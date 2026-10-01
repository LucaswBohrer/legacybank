import { useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { ApiError, reversal } from '../api';
import type { FinancialResult } from '../types';
import { newTxId } from '../money';
import Modal from '../components/Modal';
import { ErrorBox } from '../components/States';

export default function Reversals() {
  const [search] = useSearchParams();
  const [txId, setTxId] = useState(newTxId());
  const [original, setOriginal] = useState(search.get('original') ?? '');
  const [fieldErr, setFieldErr] = useState<string | null>(null);
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<FinancialResult | null>(null);
  const [err, setErr] = useState<unknown>(null);

  function validate(): string | null {
    if (!/^[A-Za-z0-9_-]{1,24}$/.test(txId.trim()))
      return 'tx_id deve ter 1–24 caracteres [A-Za-z0-9_-].';
    if (!/^[A-Za-z0-9_-]{1,24}$/.test(original.trim()))
      return 'original_tx_id deve ter 1–24 caracteres [A-Za-z0-9_-].';
    if (txId.trim() === original.trim())
      return 'O tx_id do estorno deve ser diferente do original.';
    return null;
  }

  async function execute() {
    const problem = validate();
    if (problem) {
      setFieldErr(problem);
      return;
    }
    setFieldErr(null);
    if (!confirming) {
      setConfirming(true);
      return;
    }
    setBusy(true);
    setErr(null);
    try {
      const r = await reversal({
        tx_id: txId.trim(),
        original_tx_id: original.trim(),
      });
      setResult(r);
      setConfirming(false);
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

  function reset() {
    setTxId(newTxId());
    setOriginal('');
    setResult(null);
    setErr(null);
    setFieldErr(null);
    setConfirming(false);
  }

  return (
    <>
      <h2>Estornos</h2>
      <p className="page-sub">
        Estorna uma transação já processada. O core COBOL devolve o valor
        integral (incluindo tarifas), marca a original como estornada e garante
        idempotência pelo novo TX-ID.
      </p>

      <div className="panel">
        <h3>Regras do estorno (core COBOL)</h3>
        <ul style={{ margin: '0 0 4px', paddingLeft: 20, color: 'var(--muted)', fontSize: 14 }}>
          <li>Só transações existentes e ainda não estornadas podem ser estornadas.</li>
          <li>Transações rejeitadas ou duplicadas não são estornáveis.</li>
          <li>O estorno gera um movimento novo no journal; o original é carimbado.</li>
          <li>Reutilizar o mesmo TX-ID de estorno faz replay idempotente.</li>
        </ul>
      </div>

      <div className="panel">
        {result ? (
          result.replay || result.status === 'duplicate' ? (
            <div className="alert info" role="status">
              🔁 <strong>Replay idempotente.</strong> Este estorno (
              <code>{result.tx_id}</code>) já havia sido processado.
              <div style={{ marginTop: 10 }}>
                <button className="btn" onClick={reset}>
                  Novo estorno
                </button>
              </div>
            </div>
          ) : (
            <div className="alert ok" role="status">
              ✅ Estorno aceito pelo core (RC {result.rc}). TX-ID{' '}
              <code>{result.tx_id}</code>.
              <div style={{ marginTop: 10 }}>
                <button className="btn" onClick={reset}>
                  Novo estorno
                </button>
              </div>
            </div>
          )
        ) : (
          <form className="form" onSubmit={onSubmit}>
            <div className="field">
              <label htmlFor="rev-original">TX-ID original (a estornar)</label>
              <input
                id="rev-original"
                className="mono"
                value={original}
                onChange={(e) => setOriginal(e.target.value)}
                maxLength={24}
                placeholder="TX-ID da transação original"
                required
                autoFocus
              />
            </div>
            <div className="field">
              <label htmlFor="rev-txid">TX-ID do estorno (novo)</label>
              <input
                id="rev-txid"
                className="mono"
                value={txId}
                onChange={(e) => setTxId(e.target.value)}
                maxLength={24}
                required
              />
              <span className="hint">
                Gerado automaticamente; edite se precisar.
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
            <div>
              <button className="btn danger" type="submit" disabled={busy}>
                {busy ? 'Processando…' : '↩️ Estornar'}
              </button>
            </div>
          </form>
        )}
      </div>

      {confirming && (
        <Modal
          title="Confirmar estorno"
          danger
          confirmLabel="Confirmar estorno"
          onConfirm={execute}
          onCancel={() => setConfirming(false)}
          busy={busy}
        >
          <p>
            Estornar a transação <strong className="mono">{original.trim()}</strong>{' '}
            com novo TX-ID <strong className="mono">{txId.trim()}</strong>? O
            core devolverá o valor integral ao(s) saldo(s).
          </p>
          {err ? <ErrorBox error={err} /> : null}
        </Modal>
      )}
    </>
  );
}

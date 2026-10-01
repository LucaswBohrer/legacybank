import { useState } from 'react';
import { ApiError, postBatch } from '../api';
import type { BatchResult } from '../types';
import { ErrorBox, Loading } from '../components/States';

const EXAMPLE = `# Exemplo de lote LEGACYBANK (linhas ignoradas começam com #)
DEPOSITO;WEB-LOTE-001;10000001;500.00
SAQUE;WEB-LOTE-002;10000001;100.00
TRANSFERENCIA;WEB-LOTE-003;10000001;10000002;200.00
ESTORNO;WEB-LOTE-004;WEB-LOTE-001`;

export default function Batch() {
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<BatchResult | null>(null);
  const [err, setErr] = useState<unknown>(null);

  const lineCount = text.split('\n').filter((l) => l.trim() && !l.trim().startsWith('#')).length;

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!text.trim() || busy) return;
    setBusy(true);
    setErr(null);
    setResult(null);
    try {
      setResult(await postBatch(text));
    } catch (e2) {
      setErr(e2);
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <h2>Lote</h2>
      <p className="page-sub">
        Processa um arquivo de lote com o motor COBOL (<code>bin/lb-lote</code>).
        Cada linha usa TX-ID próprio — duplicadas fazem replay.
      </p>

      <div className="panel">
        <form className="form" onSubmit={submit} style={{ maxWidth: '100%' }}>
          <div className="field">
            <label htmlFor="batch-text">Conteúdo do lote</label>
            <textarea
              id="batch-text"
              rows={10}
              value={text}
              onChange={(e) => setText(e.target.value)}
              placeholder={EXAMPLE}
              className="mono"
              style={{ fontFamily: 'ui-monospace, Menlo, Consolas, monospace', fontSize: 13 }}
            />
            <span className="hint">
              {lineCount} linha(s) útil(eis). Formato: TIPO;TX-ID;conta(s);valor
              — ex.: DEPOSITO;SAQUE;TRANSFERENCIA;ESTORNO.
            </span>
          </div>
          <div className="row">
            <button className="btn primary" type="submit" disabled={busy || !text.trim()}>
              {busy ? 'Processando…' : '📦 Processar lote'}
            </button>
            <button
              className="btn ghost"
              type="button"
              onClick={() => setText(EXAMPLE)}
              disabled={busy}
            >
              Carregar exemplo
            </button>
            <button
              className="btn ghost"
              type="button"
              onClick={() => {
                setText('');
                setResult(null);
                setErr(null);
              }}
              disabled={busy}
            >
              Limpar
            </button>
          </div>
        </form>
      </div>

      {busy && <Loading label="Processando lote no COBOL…" />}

      {err instanceof ApiError && err.status === 400 ? (
        <div className="alert warn" role="alert">
          ⚠️ {err.message}
        </div>
      ) : err ? (
        <ErrorBox error={err} />
      ) : null}

      {result && (
        <div className="panel">
          <h3>Resultado do lote</h3>
          <div className="grid cards">
            <div className="card">
              <h3>Processadas</h3>
              <div className="big">{result.processed}</div>
            </div>
            <div className="card">
              <h3>Aceitas</h3>
              <div className="big" style={{ color: 'var(--green)' }}>
                {result.accepted}
              </div>
            </div>
            <div className="card">
              <h3>Rejeitadas</h3>
              <div className="big" style={{ color: 'var(--red)' }}>
                {result.rejected}
              </div>
            </div>
            <div className="card">
              <h3>Duplicadas</h3>
              <div className="big" style={{ color: 'var(--amber)' }}>
                {result.duplicates}
              </div>
            </div>
            <div className="card">
              <h3>Inválidas</h3>
              <div className="big">{result.invalid}</div>
            </div>
          </div>

          {result.errors.length > 0 && (
            <>
              <h3 style={{ marginTop: 18 }}>Erros por linha</h3>
              <div className="log-box">
                {result.errors.map((e, i) => (
                  <div key={i} className="log-err">
                    {e}
                  </div>
                ))}
              </div>
            </>
          )}

          {result.report && (
            <>
              <h3 style={{ marginTop: 18 }}>Relatório do core</h3>
              <div className="log-box">{result.report}</div>
            </>
          )}
        </div>
      )}
    </>
  );
}

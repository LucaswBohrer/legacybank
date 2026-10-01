import { getHealth } from '../api';
import { ErrorBox, Loading, useFetch } from '../components/States';

export default function System() {
  const { data, error, loading, reload } = useFetch(getHealth);

  const coreOk = data?.core === 'ok';

  return (
    <>
      <h2>Sistema</h2>
      <p className="page-sub">Estado da API Python e do núcleo COBOL.</p>

      {loading && <Loading label="Consultando /health…" />}
      {error && <ErrorBox error={error} onRetry={reload} />}

      {!loading && !error && data && (
        <>
          <div className="grid cards">
            <div className="card">
              <h3>API REST</h3>
              <div className="big">
                <span className="badge ok">{data.api}</span>
              </div>
              <div className="detail">api/lbapi.py · v{data.version}</div>
            </div>
            <div className="card">
              <h3>Core COBOL</h3>
              <div className="big">
                {coreOk ? (
                  <span className="badge ok">ok</span>
                ) : (
                  <span className="badge err">{data.core}</span>
                )}
              </div>
              <div className="detail">
                {coreOk
                  ? `GnuCOBOL respondeu (RC ${data.rc ?? '?'})`
                  : (data.reason ?? 'núcleo indisponível')}
              </div>
            </div>
          </div>

          <div className="panel">
            <h3>Arquitetura</h3>
            <dl className="kv">
              <dt>Frontend</dt>
              <dd>React + TypeScript + Vite (esta página)</dd>
              <dt>API</dt>
              <dd className="mono">api/lbapi.py — Python 3, só stdlib</dd>
              <dt>Core</dt>
              <dd className="mono">bin/lb-api → COBOL (GnuCOBOL 3.2.0)</dd>
              <dt>Regras financeiras</dt>
              <dd>100% no COBOL — o frontend só exibe</dd>
              <dt>Idempotência</dt>
              <dd>por TX-ID, no core</dd>
              <dt>Dinheiro</dt>
              <dd>centavos inteiros; nenhum float no frontend</dd>
              <dt>Ambiente</dt>
              <dd>
                {data.demo ? (
                  <span className="badge warn">DEMO — storage efêmero</span>
                ) : (
                  <span className="badge ok">local</span>
                )}
              </dd>
              <dt>Acesso</dt>
              <dd>
                {data.demo
                  ? 'Token demo (LBAPI_TOKEN) — demo pública ≠ produção bancária'
                  : 'Livre (LBAPI_TOKEN não definido)'}
              </dd>
            </dl>
            <div className="action-bar">
              <button className="btn" onClick={reload}>
                ↻ Verificar novamente
              </button>
            </div>
          </div>
        </>
      )}
    </>
  );
}

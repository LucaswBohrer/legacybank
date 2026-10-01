import { createContext, useContext, useEffect, useState } from 'react';
import type { ReactNode } from 'react';
import { ApiError, captureTokenFromUrl, getHealth } from '../api';
import type { Health } from '../types';
import TokenGate from './TokenGate';
import DemoBadge from './DemoBadge';
import { Loading, ErrorBox } from './States';

const HealthCtx = createContext<Health | null>(null);
export const useHealth = () => useContext(HealthCtx);

/** Tentativas de health durante o cold start (plano gratuito "dorme"). */
const MAX_START_ATTEMPTS = 18; // ~90 s
const RETRY_MS = 5000;

type Boot = 'loading' | 'starting' | 'ready' | 'failed';

/**
 * Boot global do app:
 * - captura ?token= da URL (link de acesso demo);
 * - consulta /health com retry (cold start no plano gratuito pode levar ~1 min);
 * - diferencia "iniciando serviço" de "core indisponível" (adendo §13);
 * - abre o TokenGate quando qualquer chamada recebe 401.
 */
export default function BootGate({ children }: { children: ReactNode }) {
  const [boot, setBoot] = useState<Boot>('loading');
  const [health, setHealth] = useState<Health | null>(null);
  const [bootError, setBootError] = useState<unknown>(null);
  const [gateOpen, setGateOpen] = useState(false);
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    captureTokenFromUrl();
    let cancelled = false;
    let n = 0;

    const attemptHealth = async () => {
      n++;
      setAttempt(n);
      try {
        const h = await getHealth();
        if (cancelled) return;
        setHealth(h);
        setBoot('ready');
      } catch (e) {
        if (cancelled) return;
        // Offline + tentativas restantes = provavelmente cold start.
        if (e instanceof ApiError && e.isOffline && n < MAX_START_ATTEMPTS) {
          setBoot('starting');
          setTimeout(attemptHealth, RETRY_MS);
        } else {
          setBootError(e);
          setBoot('failed');
        }
      }
    };
    attemptHealth();

    const onUnauth = () => setGateOpen(true);
    window.addEventListener('lbapi:unauthorized', onUnauth);
    return () => {
      cancelled = true;
      window.removeEventListener('lbapi:unauthorized', onUnauth);
    };
  }, []);

  if (boot === 'loading' || boot === 'starting') {
    return (
      <div className="boot-screen">
        <div className="brand">
          <h1>
            LEGACY<span className="bank">BANK</span>
          </h1>
          <p>web banking · núcleo COBOL</p>
        </div>
        <Loading
          label={
            boot === 'starting'
              ? `Iniciando serviço… (tentativa ${attempt}/${MAX_START_ATTEMPTS}) — o plano gratuito pode levar ~1 min para acordar`
              : 'Conectando…'
          }
        />
      </div>
    );
  }

  if (boot === 'failed') {
    return (
      <div className="boot-screen">
        <div className="brand">
          <h1>
            LEGACY<span className="bank">BANK</span>
          </h1>
        </div>
        <div style={{ maxWidth: 480 }}>
          <ErrorBox
            error={bootError}
            onRetry={() => window.location.reload()}
          />
        </div>
      </div>
    );
  }

  return (
    <HealthCtx.Provider value={health}>
      <DemoBadge health={health} />
      {children}
      {gateOpen && (
        <TokenGate
          onSaved={() => {
            setGateOpen(false);
            window.location.reload();
          }}
          onClose={() => setGateOpen(false)}
        />
      )}
    </HealthCtx.Provider>
  );
}

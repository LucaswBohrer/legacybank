import type { Health } from '../types';

/** Selo persistente de ambiente demo (adendo TESTE 5 §12). */
export default function DemoBadge({ health }: { health: Health | null }) {
  if (!health?.demo) return null;
  return (
    <div
      className="demo-badge"
      role="note"
      aria-label="Ambiente de demonstração"
      title="Ambiente de demonstração — dados efêmeros, não é um banco real"
    >
      <strong>DEMO ENVIRONMENT</strong>
      <span>
        Storage: {health.storage === 'ephemeral' ? 'EPHEMERAL' : (health.storage ?? '?').toUpperCase()}
        {' · '}Core: COBOL
      </span>
    </div>
  );
}

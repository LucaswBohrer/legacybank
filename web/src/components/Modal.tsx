import { useEffect } from 'react';

interface Props {
  title: string;
  children: React.ReactNode;
  confirmLabel?: string;
  danger?: boolean;
  onConfirm?: () => void;
  onCancel: () => void;
  busy?: boolean;
  /** Se informado, o botão de confirmação vira submit deste form. */
  formId?: string;
  hideActions?: boolean;
}

/** Modal de confirmação forte (saque, transferência, estorno, bloqueio, encerramento). */
export default function Modal({
  title,
  children,
  confirmLabel = 'Confirmar',
  danger = false,
  onConfirm,
  onCancel,
  busy = false,
  formId,
  hideActions = false,
}: Props) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onCancel();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onCancel]);

  return (
    <div className="modal-scrim" onClick={onCancel}>
      <div
        className={`modal${danger ? ' danger' : ''}`}
        role="dialog"
        aria-modal="true"
        aria-label={title}
        onClick={(e) => e.stopPropagation()}
      >
        <h3>{title}</h3>
        <div>{children}</div>
        {!hideActions && (
          <div className="actions" style={{ marginTop: 18 }}>
            <button className="btn ghost" onClick={onCancel} disabled={busy}>
              Cancelar
            </button>
            {formId ? (
              <button
                type="submit"
                form={formId}
                className={`btn ${danger ? 'danger' : 'primary'}`}
                disabled={busy}
              >
                {busy ? 'Processando…' : confirmLabel}
              </button>
            ) : (
              <button
                className={`btn ${danger ? 'danger' : 'primary'}`}
                onClick={onConfirm}
                disabled={busy}
              >
                {busy ? 'Processando…' : confirmLabel}
              </button>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

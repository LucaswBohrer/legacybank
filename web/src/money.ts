// Utilidades de dinheiro — NUNCA usar float.
// A unidade canônica é o centavo (inteiro). A API fala "1000.00"
// (string) e balance_cents (inteiro); aqui só formatamos/exibimos.

const brl = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
});

/** "1000.00" ou 100000 (cents) -> "R$ 1.000,00". Aceita cents ou string decimal. */
export function formatMoney(value: number | string): string {
  const cents =
    typeof value === 'number' ? Math.trunc(value) : decimalStringToCents(value);
  if (cents === null || !Number.isSafeInteger(cents)) return '—';
  // Intl espera valor em reais; divisão por 100 aqui é só apresentação
  // (o arredondamento já foi feito em centavos inteiros).
  return brl.format(cents / 100);
}

/** cents (inteiro) -> "R$ 1.000,00". */
export function formatCents(cents: number): string {
  if (!Number.isSafeInteger(cents)) return '—';
  return brl.format(cents / 100);
}

/** cents (inteiro, pode ser negativo) -> "+R$ 50,00" / "-R$ 50,00". */
export function formatSignedCents(cents: number): string {
  if (!Number.isSafeInteger(cents)) return '—';
  const sign = cents > 0 ? '+' : cents < 0 ? '−' : '';
  return sign + brl.format(Math.abs(cents) / 100);
}

/** cents -> "1000.00" (formato que a API espera no campo amount). */
export function centsToAmount(cents: number): string {
  const c = Math.trunc(cents);
  const neg = c < 0 ? '-' : '';
  const abs = Math.abs(c);
  return `${neg}${Math.trunc(abs / 100)}.${String(abs % 100).padStart(2, '0')}`;
}

/**
 * Converte entrada do usuário ("1.000,50", "1000,50", "1000.50", "1000")
 * para centavos (inteiro). Retorna null se inválido.
 * Sem float: só manipulação de string + parseInt.
 */
export function parseBRLToCents(raw: string): number | null {
  const s = raw.trim().replace(/\s/g, '');
  if (!/^[0-9.,]+$/.test(s) || s === '') return null;
  let intPart: string;
  let decPart: string;
  if (s.includes(',')) {
    // Formato BR: pontos são milhar, vírgula é decimal.
    const noThousands = s.replace(/\./g, '');
    const parts = noThousands.split(',');
    if (parts.length !== 2) return null;
    [intPart, decPart] = parts;
  } else if (s.includes('.')) {
    const groups = s.split('.');
    const head = groups[0];
    const tail = groups.slice(1);
    if (
      /^\d+$/.test(head) &&
      tail.length >= 1 &&
      tail.every((g) => /^\d{3}$/.test(g))
    ) {
      // Separador de milhar brasileiro: "1.000", "1.000.000".
      intPart = groups.join('');
      decPart = '';
    } else if (
      groups.length === 2 &&
      /^\d+$/.test(groups[0]) &&
      /^\d{1,2}$/.test(groups[1])
    ) {
      // Ponto como separador decimal: "1000.50".
      [intPart, decPart] = groups;
    } else {
      return null;
    }
  } else {
    intPart = s;
    decPart = '';
  }
  if (!/^\d+$/.test(intPart)) return null;
  if (!/^\d{0,2}$/.test(decPart)) return null;
  if (intPart.length > 13) return null; // limite do core
  const padded = (decPart + '00').slice(0, 2);
  const cents = parseInt(intPart, 10) * 100 + parseInt(padded, 10);
  if (!Number.isSafeInteger(cents)) return null;
  return cents;
}

/** "1000.00" -> 100000 (cents). Null se inválido. */
export function decimalStringToCents(s: string): number | null {
  const t = s.trim();
  if (!/^-?\d+(\.\d{1,2})?$/.test(t)) return null;
  const neg = t.startsWith('-');
  const digits = (neg ? t.slice(1) : t).split('.');
  const intPart = parseInt(digits[0], 10);
  const decPart = parseInt((digits[1] ?? '00').padEnd(2, '0'), 10);
  const cents = intPart * 100 + decPart;
  return neg ? -cents : cents;
}

/**
 * Gera um tx_id único válido para a API: 1-24 chars [A-Za-z0-9_-].
 * Formato: "WEB-<base36 timestamp>-<4 aleatórios>".
 */
export function newTxId(): string {
  const ts = Date.now().toString(36).toUpperCase();
  const rnd = Array.from({ length: 4 }, () =>
    'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'.charAt(
      Math.floor(Math.random() * 36),
    ),
  ).join('');
  return `WEB-${ts}-${rnd}`;
}

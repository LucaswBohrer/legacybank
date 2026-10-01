// Tipos espelhando 1:1 o contrato da API (api/lbapi.py v1.1.0).
// Dinheiro: sempre em centavos (number inteiro) ou string decimal "1000.00".
// NUNCA float.

export interface Health {
  api: string;
  core: string;
  version: string;
  rc?: string;
  reason?: string;
}

export interface JournalLine {
  seq: string;
  timestamp: string;
  type: string;
  account: string;
  dest_account: string;
  value_cents: string;
  tx_id: string;
  description: string;
  /** string "1000.00" adicionada pela API para exibição */
  value?: string;
}

export interface DashboardData {
  customers: number;
  accounts: number;
  accounts_active: number;
  accounts_blocked: number;
  accounts_closed: number;
  total_balance_cents: number;
  total_balance: string;
  transactions: number;
  movements: number;
  recent: JournalLine[];
}

export interface Customer {
  id: string;
  name: string;
  cpf: string;
  email: string;
  opened: string;
  status: string;
}

export type AccountStatus = 'A' | 'B' | 'E';
export type AccountType = 'CC' | 'CP';

export interface Account {
  account: string;
  customer_id: string;
  type: string;
  status: string;
  balance_cents: number;
  /** string "1000.00" vinda da API */
  balance: string;
  opened: string;
}

export interface Movement {
  timestamp: string;
  type: string;
  effect_cents: number;
  effect: string;
  running_balance_cents: number;
  running_balance: string;
  tx_id: string;
}

export interface Statement {
  account: string;
  opening_balance_cents: number;
  opening_balance: string;
  movements: Movement[];
  current_balance_cents: number;
  current_balance: string;
}

export interface TxListItem {
  tx_id: string;
  timestamp: string;
  /** "OK" | "REJEITADA" | "DUPLICADA" */
  result: string;
  detail: string;
  /** primeira palavra do detalhe, ex. "DEPOSITO" */
  kind: string;
  account: string | null;
  value_cents: number | null;
  fee_cents: number | null;
}

export interface TxDetail {
  tx_id: string;
  timestamp: string;
  result: string;
  detail: string;
}

export interface AuditEvent {
  timestamp: string;
  event: string;
}

export interface BatchResult {
  processed: number;
  accepted: number;
  rejected: number;
  duplicates: number;
  invalid: number;
  errors: string[];
  report: string | null;
}

/** Resposta de operação financeira (201 aceita, 200 replay). */
export interface FinancialResult {
  tx_id: string;
  operation: string;
  /** "accepted" | "duplicate" | "rejected" */
  status: string;
  replay?: boolean;
  rc: number;
  rc_message: string;
  original?: TxDetail | Record<string, unknown>;
}

/** Corpo de erro da API: {error, message, rc?, ...} */
export interface ApiErrorBody {
  error: string;
  message: string;
  rc?: number;
  tx_id?: string;
  [k: string]: unknown;
}

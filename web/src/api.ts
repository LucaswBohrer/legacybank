// Cliente tipado da API REST (api/lbapi.py).
// Base: /api/v1 (o proxy do Vite repassa para 127.0.0.1:8123 em dev;
// em produção o próprio lbapi.py serve o frontend estático).

import type {
  Account,
  ApiErrorBody,
  AuditEvent,
  BatchResult,
  Customer,
  DashboardData,
  FinancialResult,
  Health,
  Statement,
  TxDetail,
  TxListItem,
} from './types';

const BASE = '/api/v1';

const TOKEN_KEY = 'lbapi_token';

/** Token demo lido do localStorage (ou ?token= na URL, capturado no boot). */
export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY);
}

export function setToken(token: string): void {
  if (token) localStorage.setItem(TOKEN_KEY, token);
  else localStorage.removeItem(TOKEN_KEY);
}

/** Captura ?token= da URL no primeiro carregamento (link de acesso demo). */
export function captureTokenFromUrl(): boolean {
  try {
    const u = new URL(window.location.href);
    const t = u.searchParams.get('token');
    if (t) {
      setToken(t);
      u.searchParams.delete('token');
      window.history.replaceState(null, '', u.toString());
      return true;
    }
  } catch {
    /* URL inválida — ignora */
  }
  return false;
}

/** Erro HTTP da API (ou falha de rede = status 0). */
export class ApiError extends Error {
  status: number;
  code: string;
  rc?: number;
  body?: ApiErrorBody;

  constructor(status: number, code: string, message: string, body?: ApiErrorBody) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.code = code;
    this.rc = typeof body?.rc === 'number' ? body.rc : undefined;
    this.body = body;
  }

  /** true quando o fetch nem chegou ao servidor (API offline). */
  get isOffline(): boolean {
    return this.status === 0;
  }

  /** true quando o servidor exige token demo (401 unauthorized). */
  get isUnauthorized(): boolean {
    return this.status === 401;
  }
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' };
  const token = getToken();
  if (token) headers['Authorization'] = `Bearer ${token}`;
  let resp: Response;
  try {
    resp = await fetch(BASE + path, {
      headers: { ...headers, ...(init?.headers as Record<string, string> | undefined) },
      ...init,
    });
  } catch (e) {
    // Rede falhou: API fora do ar ou sem conectividade.
    throw new ApiError(
      0,
      'offline',
      'Não foi possível alcançar a API. Verifique se o servidor está rodando.',
    );
  }
  let body: unknown = null;
  try {
    body = await resp.json();
  } catch {
    body = null;
  }
  if (!resp.ok) {
    const b = (body ?? {}) as ApiErrorBody;
    const err = new ApiError(
      resp.status,
      b.error ?? `http_${resp.status}`,
      b.message ?? `Erro HTTP ${resp.status}`,
      b,
    );
    // 401 = token demo ausente/invalido: avisa a UI global (TokenGate).
    if (resp.status === 401) {
      window.dispatchEvent(new CustomEvent('lbapi:unauthorized'));
    }
    throw err;
  }
  return body as T;
}

const get = <T>(path: string): Promise<T> => request<T>(path);

function post<T>(path: string, payload?: unknown): Promise<T> {
  return request<T>(path, {
    method: 'POST',
    body: payload === undefined ? undefined : JSON.stringify(payload),
  });
}

// ---------------------------------------------------------------- saúde
export const getHealth = (): Promise<Health> => get<Health>('/health');

// ------------------------------------------------------------ dashboard
export const getDashboard = (): Promise<DashboardData> =>
  get<DashboardData>('/dashboard');

// ------------------------------------------------------------ clientes
export const getCustomers = (): Promise<{ customers: Customer[]; count: number }> =>
  get('/customers');

export const getCustomer = (id: string): Promise<Customer> =>
  get<Customer>(`/customers/${encodeURIComponent(id)}`);

export const createCustomer = (data: {
  name: string;
  cpf: string;
  email: string;
}): Promise<{ id: string; status: string; rc: number; rc_message: string }> =>
  post('/customers', data);

// -------------------------------------------------------------- contas
export const getAccounts = (
  status?: string,
  customerId?: string,
): Promise<{ accounts: Account[]; count: number }> => {
  const qs = new URLSearchParams();
  if (status) qs.set('status', status);
  if (customerId) qs.set('customer_id', customerId);
  const q = qs.toString();
  return get(`/accounts${q ? `?${q}` : ''}`);
};

export const getAccount = (id: string): Promise<Account> =>
  get<Account>(`/accounts/${encodeURIComponent(id)}`);

export const createAccount = (data: {
  customer_id: string;
  type: string;
}): Promise<{ account: string; customer_id: string; type: string }> =>
  post('/accounts', data);

export const accountAction = (
  id: string,
  action: 'block' | 'unblock' | 'close',
): Promise<{ account: string; action: string; status: string }> =>
  post(`/accounts/${encodeURIComponent(id)}/${action}`);

export const getStatement = (id: string): Promise<Statement> =>
  get<Statement>(`/accounts/${encodeURIComponent(id)}/statement`);

// ---------------------------------------------------------- transações
export interface TxFilters {
  account?: string;
  result?: string;
  q?: string;
  limit?: number;
}

export const getTransactions = (
  f: TxFilters = {},
): Promise<{ transactions: TxListItem[]; count: number }> => {
  const qs = new URLSearchParams();
  if (f.account) qs.set('account', f.account);
  if (f.result) qs.set('result', f.result);
  if (f.q) qs.set('q', f.q);
  if (f.limit) qs.set('limit', String(f.limit));
  const q = qs.toString();
  return get(`/transactions${q ? `?${q}` : ''}`);
};

export const getTransaction = (txId: string): Promise<TxDetail> =>
  get<TxDetail>(`/transactions/${encodeURIComponent(txId)}`);

export const deposit = (data: {
  tx_id: string;
  account: string;
  amount: string;
}): Promise<FinancialResult> => post('/transactions/deposit', data);

export const withdraw = (data: {
  tx_id: string;
  account: string;
  amount: string;
}): Promise<FinancialResult> => post('/transactions/withdraw', data);

export const transfer = (data: {
  tx_id: string;
  from_account: string;
  to_account: string;
  amount: string;
}): Promise<FinancialResult> => post('/transactions/transfer', data);

export const reversal = (data: {
  tx_id: string;
  original_tx_id: string;
}): Promise<FinancialResult> => post('/transactions/reversal', data);

// ------------------------------------------------------------ auditoria
export const getAudit = (
  limit = 100,
): Promise<{ events: AuditEvent[]; count: number }> =>
  get(`/audit?limit=${limit}`);

// ----------------------------------------------------------------- lote
export async function postBatch(text: string): Promise<BatchResult> {
  let resp: Response;
  try {
    resp = await fetch(BASE + '/batch', {
      method: 'POST',
      headers: { 'Content-Type': 'text/plain; charset=utf-8' },
      body: text,
    });
  } catch {
    throw new ApiError(
      0,
      'offline',
      'Não foi possível alcançar a API. Verifique se o servidor está rodando.',
    );
  }
  const body = (await resp.json().catch(() => null)) as ApiErrorBody | BatchResult | null;
  if (!resp.ok) {
    const b = (body ?? {}) as ApiErrorBody;
    throw new ApiError(
      resp.status,
      b.error ?? `http_${resp.status}`,
      b.message ?? `Erro HTTP ${resp.status}`,
      b,
    );
  }
  return body as BatchResult;
}

import { beforeEach, describe, expect, it, vi } from 'vitest';
import {
  ApiError,
  deposit,
  getAudit,
  getDashboard,
  getHealth,
} from '../api';

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

beforeEach(() => {
  vi.stubGlobal('fetch', vi.fn());
});

describe('ApiError', () => {
  it('mapeia 422 do core com RC', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(
      jsonResponse(422, {
        error: 'customer_rejected',
        message: 'CPF inválido',
        rc: 5,
      }),
    );
    const p = getHealth();
    await expect(p).rejects.toMatchObject({
      status: 422,
      code: 'customer_rejected',
      rc: 5,
    } satisfies Partial<ApiError>);
    await expect(p).rejects.toThrow('CPF inválido');
  });

  it('mapeia 503 quando o core cai', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(
      jsonResponse(503, { error: 'core_unavailable', message: 'timeout no core' }),
    );
    await expect(getDashboard()).rejects.toMatchObject({
      status: 503,
      code: 'core_unavailable',
    } satisfies Partial<ApiError>);
  });

  it('falha de rede vira status 0 (offline)', async () => {
    vi.mocked(fetch).mockRejectedValueOnce(new TypeError('Failed to fetch'));
    const err = await getHealth().catch((e) => e);
    expect(err).toBeInstanceOf(ApiError);
    expect(err.status).toBe(0);
    expect(err.isOffline).toBe(true);
  });

  it('400 de envelope carrega a mensagem', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(
      jsonResponse(400, { error: 'invalid_payload', message: 'amount inválido' }),
    );
    await expect(
      deposit({ tx_id: 'X', account: '10000001', amount: '0' }),
    ).rejects.toMatchObject({ status: 400, message: 'amount inválido' });
  });
});

describe('replay idempotente', () => {
  it('200 com replay:true passa como sucesso (não erro)', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(
      jsonResponse(200, {
        tx_id: 'WEB-1',
        operation: 'deposit',
        status: 'duplicate',
        replay: true,
        rc: 6,
        rc_message: 'transação duplicada',
      }),
    );
    const r = await deposit({
      tx_id: 'WEB-1',
      account: '10000001',
      amount: '10.00',
    });
    expect(r.replay).toBe(true);
    expect(r.status).toBe('duplicate');
  });
});

describe('contratos de leitura', () => {
  it('getAudit usa o campo events da API', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(
      jsonResponse(200, {
        events: [{ timestamp: '2026-10-01 10:00:00', event: 'HTTP 200' }],
        count: 1,
      }),
    );
    const r = await getAudit(50);
    expect(r.events).toHaveLength(1);
    expect(vi.mocked(fetch).mock.calls[0][0]).toContain('limit=50');
  });

  it('getHealth expõe api/core/version', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(
      jsonResponse(200, { api: 'ok', core: 'ok', version: '1.1.0', rc: '0' }),
    );
    const h = await getHealth();
    expect(h).toMatchObject({ api: 'ok', core: 'ok', version: '1.1.0' });
  });
});

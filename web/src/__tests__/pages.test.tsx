import { describe, expect, it, vi, beforeEach } from 'vitest';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import App from '../App';
import Layout from '../components/Layout';
import { ApiError } from '../api';

vi.mock('../api', async (importOriginal) => {
  const mod = await importOriginal<typeof import('../api')>();
  return {
    ...mod,
    getDashboard: vi.fn(),
    getCustomers: vi.fn(),
    getAccounts: vi.fn(),
    getTransactions: vi.fn(),
    getHealth: vi.fn(),
  };
});

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const api = (await import('../api')) as any;

beforeEach(() => {
  vi.resetAllMocks();
});

function renderApp(path: string) {
  return render(
    <MemoryRouter initialEntries={[path]}>
      <App />
    </MemoryRouter>,
  );
}

const DASH = {
  customers: 2,
  accounts: 3,
  accounts_active: 2,
  accounts_blocked: 1,
  accounts_closed: 0,
  total_balance_cents: 250000,
  total_balance: '2500.00',
  transactions: 30,
  movements: 34,
  recent: [],
};

describe('Dashboard', () => {
  it('renderiza os cartões com dados da API', async () => {
    api.getDashboard.mockResolvedValue(DASH);
    renderApp('/dashboard');
    // 'Saldo total' só existe quando os dados carregaram
    await screen.findByText('Saldo total');
    expect(screen.getByText(`R$ 2.500,00`)).toBeInTheDocument();
    expect(screen.getAllByText('Transações').length).toBeGreaterThanOrEqual(1);
  });

  it('mostra estado offline com botão tentar de novo', async () => {
    api.getDashboard
      .mockRejectedValueOnce(new ApiError(0, 'offline', 'caiu'))
      .mockResolvedValueOnce(DASH);
    renderApp('/dashboard');
    await screen.findByText(/API inacessível/);
    await userEvent.click(
      screen.getByRole('button', { name: /Tentar novamente/ }),
    );
    await screen.findByText('Saldo total');
    expect(api.getDashboard).toHaveBeenCalledTimes(2);
  });
});

describe('Transactions', () => {
  it('mostra erro 503 do core com distinção', async () => {
    api.getTransactions.mockRejectedValue(
      new ApiError(503, 'core_unavailable', 'timeout no core', {
        error: 'core_unavailable',
        message: 'timeout no core',
      }),
    );
    renderApp('/transactions');
    await screen.findByText(/Core COBOL indisponível/);
    expect(screen.getByText(/timeout no core/)).toBeInTheDocument();
  });

  it('renderiza a lista com resultado e tarifa', async () => {
    api.getTransactions.mockResolvedValue({
      transactions: [
        {
          tx_id: 'WEB-ABC',
          timestamp: '2026-10-01 10:00:00',
          result: 'OK',
          detail: 'SAQUE conta=10000001 valor=10000 tarifa=150',
          kind: 'SAQUE',
          account: '10000001',
          value_cents: 10000,
          fee_cents: 150,
        },
      ],
      count: 1,
    });
    renderApp('/transactions');
    await screen.findByText('WEB-ABC');
    expect(screen.getByText(`R$ 100,00`)).toBeInTheDocument();
    expect(screen.getByText(`R$ 1,50`)).toBeInTheDocument();
  });
});

describe('Customers', () => {
  it('renderiza a tabela de clientes', async () => {
    api.getCustomers.mockResolvedValue({
      customers: [
        {
          id: 'C000001',
          name: 'Ada Lovelace',
          cpf: '123.456.789-00',
          email: 'ada@example.com',
          opened: '2026-10-01',
          status: 'A',
        },
      ],
      count: 1,
    });
    renderApp('/customers');
    await screen.findByText('Ada Lovelace');
    expect(screen.getByText('C000001')).toBeInTheDocument();
  });

  it('busca filtra a lista localmente', async () => {
    api.getCustomers.mockResolvedValue({
      customers: [
        { id: 'C000001', name: 'Ada Lovelace', cpf: '111', email: 'a@a', opened: 'x', status: 'A' },
        { id: 'C000002', name: 'Alan Turing', cpf: '222', email: 'b@b', opened: 'x', status: 'A' },
      ],
      count: 2,
    });
    renderApp('/customers');
    await screen.findByText('Alan Turing');
    await userEvent.type(screen.getByLabelText('Buscar clientes'), 'ada');
    await waitFor(() => {
      expect(screen.queryByText('Alan Turing')).not.toBeInTheDocument();
    });
    expect(screen.getByText('Ada Lovelace')).toBeInTheDocument();
  });
});

describe('System', () => {
  it('mostra API ok e core ok', async () => {
    api.getHealth.mockResolvedValue({
      api: 'ok',
      core: 'ok',
      version: '1.1.0',
      rc: '0',
    });
    renderApp('/system');
    await screen.findByText('API REST');
    expect(screen.getByText('Core COBOL')).toBeInTheDocument();
    expect(screen.getAllByText(/v1\.1\.0/).length).toBeGreaterThanOrEqual(1);
  });
});

describe('Layout / hamburger', () => {
  function renderLayout() {
    return render(
      <MemoryRouter initialEntries={['/dashboard']}>
        <Routes>
          <Route element={<Layout />}>
            <Route path="/dashboard" element={<div>conteúdo</div>} />
            <Route path="/customers" element={<div>clientes</div>} />
          </Route>
        </Routes>
      </MemoryRouter>,
    );
  }

  it('abre o drawer no hamburger e navega ao clicar', async () => {
    renderLayout();
    expect(screen.queryByRole('dialog', { name: 'Menu' })).not.toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Abrir menu' }));
    const dialog = await screen.findByRole('dialog', { name: 'Menu' });
    // clica no link Clientes DENTRO do drawer (a sidebar desktop também tem um)
    await userEvent.click(within(dialog).getByText('Clientes'));
    await waitFor(() => {
      expect(screen.getByText('clientes')).toBeInTheDocument();
    });
    expect(screen.queryByRole('dialog', { name: 'Menu' })).not.toBeInTheDocument();
  });

  it('fecha o drawer pelo botão fechar', async () => {
    renderLayout();
    await userEvent.click(screen.getByRole('button', { name: 'Abrir menu' }));
    const dialog = await screen.findByRole('dialog', { name: 'Menu' });
    await userEvent.click(within(dialog).getByText('✕ Fechar'));
    expect(screen.queryByRole('dialog', { name: 'Menu' })).not.toBeInTheDocument();
  });
});

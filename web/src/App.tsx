import { Navigate, Route, Routes } from 'react-router-dom';
import Layout from './components/Layout';
import BootGate from './components/BootGate';
import Dashboard from './pages/Dashboard';
import Customers from './pages/Customers';
import Accounts from './pages/Accounts';
import AccountDetail from './pages/AccountDetail';
import Statement from './pages/Statement';
import Transactions, { TransactionDetail } from './pages/Transactions';
import Reversals from './pages/Reversals';
import Audit from './pages/Audit';
import Batch from './pages/Batch';
import System from './pages/System';

export default function App() {
  return (
    <BootGate>
      <Routes>
        <Route element={<Layout />}>
          <Route index element={<Navigate to="/dashboard" replace />} />
          <Route path="/dashboard" element={<Dashboard />} />
          <Route path="/customers" element={<Customers />} />
          <Route path="/accounts" element={<Accounts />} />
          <Route path="/accounts/:id" element={<AccountDetail />} />
          <Route path="/accounts/:id/statement" element={<Statement />} />
          <Route path="/transactions" element={<Transactions />} />
          <Route path="/transactions/:txId" element={<TransactionDetail />} />
          <Route path="/reversals" element={<Reversals />} />
          <Route path="/audit" element={<Audit />} />
          <Route path="/batch" element={<Batch />} />
          <Route path="/system" element={<System />} />
          <Route path="*" element={<Navigate to="/dashboard" replace />} />
        </Route>
      </Routes>
    </BootGate>
  );
}

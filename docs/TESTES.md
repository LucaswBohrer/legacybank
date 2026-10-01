# TESTES — LEGACYBANK

## Como rodar

```bash
./scripts/build.sh     # compila os 3 executaveis
./tests/run_all.sh          # suite completa (63 assercoes)
./tests/run_all.sh --carga  # inclui o teste de carga (100k transacoes)
```

## Suítes

| Suite | Arquivo | O que cobre |
|---|---|---|
| Funcionais | `tests/test_funcional.sh` | Cadastro, abertura de conta, depósito, saque (+tarifa), transferência (+tarifa), todas as rejeições com RC correto, extrato, relatório. 22 asserções. |
| Integridade | `tests/test_integridade.sh` | Rejeição não altera saldo; transferência não debita sem creditar; reload preserva saldos e journal; checkpoint detecta journal além/aquém do esperado. 8 asserções. |
| Batch | `tests/test_batch.sh` | Contadores ok/rejeitada/duplicada/inválida; reenvio integral do lote é idempotente (saldos inalterados); relatório do lote é gerado. 10 asserções. |
| Carga | `tests/test_carga.sh` | 100.000 transações (seed fixa 42, 60% depósitos / 20% saques / 20% transferências); confere que a soma dos saldos bate com o lote. |

`tests/lib.sh` tem os helpers (`assert_eq`, `assert_contains`, `parse_saldo`, `run_menu`).

## Resultado da última execução (2026-10-01)

```
funcionais:   22 passaram, 0 falharam
integridade:   8 passaram, 0 falharam
batch:        10 passaram, 0 falharam
```

## Teste de carga — 100.000 transações

Executado em 2026-10-01 (lote determinístico `/tmp/lote100k.txt`,
`TX-LOAD-000001`…`TX-LOAD-100000`, conta `10000001` com saldo inicial de
R$ 1.000.000,00 para não haver rejeição por saldo):

- **Resultado:** `0100000 ok, 0000000 rejeitadas, 0000000 duplicadas,
  0000000 invalidas` — relatório em `relatorio_lote_*.txt`.
- **Duração:** ~30 minutos (início ~11:12, término 11:42).
- **Reconciliação:** soma dos saldos finais confere **exatamente** com o
  cálculo independente a partir do arquivo de lote (conta 10000001 =
  R$ 12.998.127,44; conta 10000002 = R$ 2.000.287,68).
- **Arquivos finais:** `movimentos.dat` com 140.006 linhas (operações +
  tarifas), `tx_registry.dat` com 100.001 entradas, `auditoria.log` com
  100.004 eventos.
- **Observação de desempenho:** o tempo cresce quadraticamente com o
  volume, porque a verificação de idempotência (`LB-TX-FIND`) é uma busca
  linear no registro de transações — O(n) por operação, O(n²) no lote.
  Para 100k transações, o processamento levou ~30 min. Ver
  `docs/LIMITACOES.md` (L02) para o caminho de otimização
  (índice hash do TX-ID).

## Bugs encontrados pelos testes (e corrigidos)

1. `LB-CTA-FIND` recebia `X(8)` onde esperava `X(24)` → "conta inexistente" fantasma (D13).
2. `STRING ... INTO` sem limpar o destino → caudas corrompidas nos arquivos (D14).
3. `LB-TX-ADD` sobrescrevia `LK-RC` → toda rejeição reportada como "OK:" (D15).
4. Expectativa errada no teste de batch (linha malformada conta como *inválida*, não *rejeitada*) — corrigido o teste, não o código.

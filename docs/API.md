# Manual da API REST — LEGACYBANK

Camada de integração HTTP sobre o core COBOL (TESTE 4, D25).
O COBOL continua sendo a única fonte de verdade financeira.

## Arquitetura

```
HTTP Client → api/lbapi.py (Python 3, somente stdlib)
            → bin/lb-api (driver COBOL, subprocesso por operação)
            → core COBOL (regras, journal, auditoria, idempotência)
```

- A API **não** implementa regra financeira: valida o envelope HTTP,
  converte valores para centavos inteiros e despacha para o driver.
- Cada operação roda `lb-api` como **subprocesso isolado** (argv, sem
  shell): crash/timeout do runtime COBOL não derruba a API.
- Todas as invocações ao core são **serializadas por um lock global**
  (D28), pois o core é single-user (L01). Sem o lock há lost updates
  (demonstrado na Fase F: 20 depósitos concorrentes perderam R$ 180,00).
- **Dinheiro sem float**: o campo `amount` é string decimal (`"100.50"`);
  a conversão para centavos usa `Decimal`. Respostas trazem
  `balance_cents` (int) e `balance` (string `"1000.00"`).

## Execução

```bash
./scripts/build.sh            # gera bin/lb-api junto com os demais
LBAPI_DATA_DIR=./data LBAPI_PORT=8123 python3 api/lbapi.py
```

Variáveis de ambiente:

| Variável         | Padrão              | Descrição                              |
|------------------|---------------------|----------------------------------------|
| `LBAPI_DATA_DIR` | `./data`            | Diretório de dados do LEGACYBANK       |
| `LBAPI_HOST`     | `127.0.0.1`         | Interface de escuta (`0.0.0.0` no Docker) |
| `LBAPI_PORT`     | `8123`              | Porta (`$PORT` como fallback no deploy) |
| `LBAPI_BIN`      | `../bin/lb-api`     | Caminho do driver COBOL                |
| `LBAPI_WEB_DIR`  | `../web/dist`       | Frontend estático servido pela API     |
| `LBAPI_TIMEOUT`  | `30`                | Timeout por operação, em segundos      |

A API escuta apenas em `127.0.0.1` por desenho (integração local).
Não há autenticação: exponha via reverse proxy com auth se necessário.

## Endpoints

Base: `/api/v1`

| Método | Rota                                      | Descrição                    |
|--------|-------------------------------------------|------------------------------|
| GET    | `/health`                                 | API + core (200/503)         |
| GET    | `/accounts/{conta}`                       | Dados da conta + saldo       |
| GET    | `/accounts/{conta}/statement`             | Extrato máquina-legível      |
| GET    | `/transactions/{tx_id}`                   | Consulta por TX-ID           |
| POST   | `/transactions/deposit`                    | Depósito                     |
| POST   | `/transactions/withdraw`                   | Saque (+ tarifa R$ 1,50)     |
| POST   | `/transactions/transfer`                   | Transferência (+ R$ 2,00)    |
| POST   | `/transactions/reversal`                   | Estorno                      |
| GET    | `/dashboard`                              | Agregados (TESTE 5)          |
| GET    | `/customers`                              | Lista clientes (TESTE 5)     |
| GET    | `/customers/{id}`                         | Um cliente (TESTE 5)         |
| POST   | `/customers`                              | Novo cliente (TESTE 5)       |
| GET    | `/accounts`                               | Lista contas `?status=` (TESTE 5) |
| POST   | `/accounts`                               | Nova conta (TESTE 5)         |
| POST   | `/accounts/{id}/block`                    | Bloqueia (TESTE 5)           |
| POST   | `/accounts/{id}/unblock`                  | Desbloqueia (TESTE 5)        |
| POST   | `/accounts/{id}/close`                    | Encerra (TESTE 5)            |
| GET    | `/transactions`                           | Lista `?account=&result=&limit=` (TESTE 5) |
| GET    | `/audit`                                  | Auditoria `?limit=` (TESTE 5)|
| POST   | `/batch`                                  | Lote texto (TESTE 5)         |

### Formato de valores

- `amount` (entrada): **string** decimal, `"100.50"` ou `"100"`.
  Números JSON (`10.5`) são rejeitados com 400 — JSON não distingue
  float de decimal, e float é proibido para dinheiro.
- Respostas: `*_cents` (inteiro) + versão string `"1234.56"`.

### Exemplos

```bash
# depósito
curl -X POST localhost:8123/api/v1/transactions/deposit \
  -d '{"tx_id":"API-001","account":"10000001","amount":"1000.00"}'
# → 201 {"tx_id":"API-001","operation":"deposit","status":"accepted",
#        "rc":0,"rc_message":"Deposito efetuado."}

# replay idempotente (mesmo tx_id)
curl -X POST localhost:8123/api/v1/transactions/deposit \
  -d '{"tx_id":"API-001","account":"10000001","amount":"1000.00"}'
# → 200 {"status":"duplicate","replay":true,"rc":6, "original":{...}}

# saldo
curl localhost:8123/api/v1/accounts/10000001
# → 200 {"account":"10000001","type":"CC","status":"A",
#        "balance_cents":100000,"balance":"1000.00"}

# extrato
curl localhost:8123/api/v1/accounts/10000001/statement
# → 200 {"account":"10000001","opening_balance_cents":0,
#        "movements":[{"timestamp":"...","type":"DEPOSITO",
#        "effect_cents":100000,"effect":"1000.00",
#        "running_balance_cents":100000,"running_balance":"1000.00",
#        "tx_id":"API-001"}, ...],
#        "current_balance_cents":100000,"current_balance":"1000.00"}

# estorno
curl -X POST localhost:8123/api/v1/transactions/reversal \
  -d '{"tx_id":"API-REV-1","original_tx_id":"API-001"}'
# → 201 {"status":"accepted","rc":0,"rc_message":"Estorno efetuado."}
```

### Endpoints do TESTE 5 (web banking)

```bash
# dashboard
curl localhost:8123/api/v1/dashboard
# → 200 {"customers":1,"accounts":1,"accounts_active":1,
#        "accounts_blocked":0,"accounts_closed":0,
#        "total_balance_cents":100000,"total_balance":"1000.00",
#        "transactions":1,"movements":1,"recent":[...]}

# novo cliente
curl -X POST localhost:8123/api/v1/customers \
  -d '{"name":"Ana","cpf":"12345678901","email":"ana@x.com"}'
# → 201 {"id":"C000001","name":"Ana",...}
# → 422 {"rc":5,"message":"CPF invalido."} (regra do core)

# nova conta
curl -X POST localhost:8123/api/v1/accounts \
  -d '{"customer_id":"C000001","type":"CC"}'
# → 201 {"account":"10000001",...}

# bloquear / desbloquear / encerrar
curl -X POST localhost:8123/api/v1/accounts/10000001/block
# → 200 {"account":"10000001","status":"B",...}
# → 422 {"rc":9,...} ao encerrar conta com saldo != 0

# lote (text/plain)
curl -X POST localhost:8123/api/v1/batch --data-binary @lote.txt
# → 200 {"processed":3,"accepted":2,"rejected":0,"duplicates":0,
#        "invalid":1,"errors":["Linha 0000003: operacao desconhecida."],
#        "report":"..."}
```

O `POST /batch` grava o corpo num temporário dentro do diretório de
dados, executa `bin/lb-lote` sob o mesmo lock global das demais
operações e remove o temporário. O Python só transporta e interpreta
o relatório — nenhuma regra do lote é reimplementada.

## Contrato de erros (D27)

| HTTP | Significado                                          |
|------|------------------------------------------------------|
| 200  | Consulta ok; **replay idempotente** (`replay: true`) |
| 201  | Operação financeira aceita (primeira execução)       |
| 400  | Payload inválido (JSON, formato de `amount`/`tx_id`/conta) |
| 404  | Recurso consultado inexistente (conta, transação, rota) |
| 422  | Rejeição semântica do core (saldo insuficiente, conta bloqueada, etc.) |
| 500  | Erro interno da API / RC inesperado do core          |
| 503  | Core indisponível (binário ausente, timeout, crash, resposta inválida) |

Toda resposta de operação financeira inclui `rc` e `rc_message`
do COBOL — o RC nunca é escondido.

Principais RCs do core (ver `docs/DECISOES.md` e código-fonte):

| RC | Significado → HTTP |
|----|--------------------|
| 0  | ok → 201           |
| 1  | conta inexistente → 422 |
| 2  | conta bloqueada/encerrada → 422 |
| 4  | saldo insuficiente → 422 |
| 5  | valor inválido → 422 |
| 6  | transação duplicada → **200 replay** |
| 12 | original inexistente (estorno) → 422 |
| 13 | não-estornável → 422 |
| 14 | já estornada → 422 |

## Idempotência

- A chave é o `tx_id`, validado pela API (`[A-Za-z0-9_-]{1,24}`) e
  registrado no `tx_registry.dat` do core.
- Reenviar o mesmo `tx_id` retorna **200** com `replay: true` e o
  resultado original — sem reexecutar.
- A idempotência **sobrevive ao restart da API** (estado no core,
  não na API). Validado em `tests/test_api.sh`.
- Thundering herd (30 threads, mesmo TX-ID): 1×201 + 29×200.

## Concorrência e performance (D28, Fase F)

- Lock global: operações ao core são estritamente seriais.
- Validado: 20/50/100 requisições concorrentes → 100% 201 e saldo exato.
- Sem o lock (acesso direto ao driver): `FS=61` e **lost updates**
  (R$ 180,00 perdidos em 20 depósitos) — por isso o lock existe.
- Throughput medido: ~15-18 op/s (~60-95ms por operação, dominado pelo
  spawn do processo COBOL + I/O de arquivos).
- Limitação honesta: a API não aumenta a capacidade do core; ela apenas
  o expõe com segurança. Para mais throughput seria preciso mudar a
  arquitetura de persistência do core (fora do escopo).

## Falhas e limites honestos

- **Core indisponível** (binário ausente, diretório de dados ausente,
  timeout, crash, saída ilegível) → **503** `core_unavailable`.
  `/health` distingue `api: ok` de `core: unavailable` (também 503).
- **Queda no meio da operação**: o driver faz INIT→LOAD→ENTRY→SAVE num
  único processo. Se o processo morre entre o journal e o SAVE, o
  `LB-DATA-CHECK` detecta divergência na próxima operação e o driver
  aborta com RC 11 → **503**. É necessário intervenção do operador
  (investigar journal × mestres). A API não tenta "auto-reparo"
  silencioso.
- **Atomicidade**: garantida dentro de uma operação do driver
  (processo único). Não há transação distribuída — a API não promete
  o que a arquitetura não suporta.
- A API não faz retry automático: retry seguro é o próprio replay
  idempotente pelo cliente (mesmo `tx_id`).

## Logs

Uma linha por requisição no stderr (ou arquivo):

```
2026-10-01T13:32:14 INFO method=POST path=/api/v1/transactions/deposit \
  tx_id=API-001 op=deposit duration_ms=95 rc=0 http=201
```

Não registra valores, contas ou dados sensíveis além do `tx_id`.

## Testes

```bash
./tests/test_api.sh   # 36 testes: contrato, erros, idempotência,
                      # restart, concorrência, reconciliação CLI×API
./tests/run_all.sh    # suíte completa (inclui a da API)
```

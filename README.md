# LEGACYBANK 🏦

Sistema bancário educacional com o **núcleo 100% em COBOL** — do cadastro
ao razão, passando por tarifas, idempotência e persistência em arquivos.

> Projeto de estudo: como um core bancário funciona por dentro, escrito
> na linguagem que ainda move grande parte do sistema financeiro mundial.

## O que faz

- Cadastro de clientes e contas (CC/CP), bloqueio, desbloqueio e encerramento
- **Depósito**, **saque** (tarifa R$ 1,50) e **transferência** (tarifa R$ 2,00)
- **Estorno** de transações (devolve valor + tarifa; original carimbada, sem duplo estorno)
- **Idempotência** por TX-ID: reenviar a mesma transação nunca duplica
- Rejeições (saldo insuficiente, conta bloqueada, etc.) **não alteram nada**
- Extrato com saldo corrido, relatório geral, processamento em **lote**
- Persistência em arquivos texto; checkpoint do journal detecta anomalias
- Suíte de testes automatizados (funcionais, integridade, batch, índice, estorno e carga)

## Stack

| Camada | Tecnologia |
|---|---|
| Núcleo | **COBOL** (GnuCOBOL 3.2.0, formato livre) |
| Persistência | Arquivos `LINE SEQUENTIAL` (`;` como separador) |
| Build/testes | Shell scripts (apenas automação — zero lógica de negócio) |
| Geração do lote de carga | Python (só gera dados de teste) |

Dinheiro é tratado em **centavos inteiros** (`PIC 9(13)`) — nunca float.

## Começo rápido

```bash
# 1. Compilar (requer cobc no PATH)
./scripts/build.sh

# 2. Inicializar o diretório de dados
./bin/lb-init ./data

# 3. Usar o menu interativo
./bin/legacybank ./data

# 4. Ou processar um lote
./bin/lb-lote ./data exemplos/lote-exemplo.txt

# 5. Rodar os testes
./tests/run_all.sh
```

Sessão de exemplo (entradas prontas para redirecionar):

```bash
./bin/legacybank ./data < exemplos/sessao-exemplo.txt
```

### Windows

Funciona com GnuCOBOL via [MSYS2](https://www.msys2.org/) (não validado
pelo autor ainda — rode `./tests/run_all.sh` e confira 63/63):

```bash
# no terminal MSYS2 MinGW64
pacman -Syu
pacman -S mingw-w64-x86_64-gnucobol
cobc -V   # deve mostrar GnuCOBOL 3.x
```

Depois clone o repo, abra o **Git Bash** (ou o terminal MinGW64) na pasta
do projeto e rode os mesmos comandos do começo rápido (`build.sh`,
`lb-init`, `legacybank`, `lb-lote`). Os executáveis saem como `.exe`
em `bin/`.

## Exemplo de uso

```
Opcao: 4
Conta: 10000001
Valor (ex.: 150.75): 1000.00
OK: Deposito efetuado.
Opcao: 7
Conta: 10000001

================ EXTRATO ================
Conta: 10000001
Saldo anterior: R$ 0,00
------------------------------------------
2026-10-01 11:12  DEPOSITO       +R$ 1.000,00
2026-10-01 11:12  SAQUE          -R$ 100,00
2026-10-01 11:12  TARIFA         -R$ 1,50
------------------------------------------
Saldo atual:    R$ 898,50
==========================================
```

## Arquitetura

```
legacybank / lb-lote / lb-init   (programas de entrada)
        │ CALL (ENTRY points)
┌───────┼───────────────────┐
▼       ▼                   ▼
lb-financ  lb-cad    lb-consulta   (regras de negócio)
        │       │           │
        └───────┼───────────┘
                ▼
            lb-dados               (persistência e journal)
                ▼
        arquivos LINE SEQUENTIAL
```

- **`lb-dados`**: única camada que toca arquivos. Tabelas em memória,
  sequências, TX-IDs, journal em append e reescrita dos masters via
  temporário + rename atômico.
- **`lb-financ`**: valida tudo **antes** de mutar; transferência debita e
  credita na mesma unidade (impossível debitar sem creditar).
- **`lb-cad`**: clientes e ciclo de vida das contas.
- **`lb-consulta`**: extrato, saldo, listagens, relatório, formatação pt-BR.

Detalhes em [`docs/ARQUITETURA.md`](docs/ARQUITETURA.md).

## Documentação

| Documento | Conteúdo |
|---|---|
| [`docs/MANUAL-CLI.md`](docs/MANUAL-CLI.md) | Uso do menu e do lote, sessão de exemplo |
| [`docs/ARQUITETURA.md`](docs/ARQUITETURA.md) | Módulos, fluxo de operação, RCs |
| [`docs/FORMATO-DADOS.md`](docs/FORMATO-DADOS.md) | Layout de cada arquivo de dados |
| [`docs/DECISOES.md`](docs/DECISOES.md) | Decisões técnicas e motivos (D01–D28) |
| [`docs/API.md`](docs/API.md) | Manual da API REST (`/api/v1`) |
| [`docs/TESTES.md`](docs/TESTES.md) | Suítes, como rodar, bugs encontrados |
| [`docs/LIMITACOES.md`](docs/LIMITACOES.md) | Limitações honestas e próximos passos |

## Testes

```bash
./tests/run_all.sh           # 161 asserções: funcionais + integridade + batch + índice + estorno + API
./tests/run_all.sh --carga   # + 100.000 transações em lote
```

Última execução: **161/161 passando** (125 legados + 36 da API).
O teste de carga (100k transações, seed determinística, ~13 s após a
otimização do índice hash — era ~30 min na v1.0) valida que a soma dos
saldos confere exatamente com o lote. Detalhes em `docs/PERFORMANCE.md`.

## Estrutura

```
legacybank/
├── src/            # fontes COBOL (+ copy/ com os layouts)
├── bin/            # executáveis (gerados pelo build)
├── data/           # diretório de dados padrão (criado pelo lb-init)
├── docs/           # documentação
├── exemplos/       # lote e sessão de exemplo
├── scripts/        # build.sh
└── tests/          # suíte de testes
```

## API REST

Camada de integração HTTP (`/api/v1`) sobre o core COBOL — o COBOL
continua sendo a única fonte de verdade financeira.

```bash
LBAPI_DATA_DIR=./data LBAPI_PORT=8123 python3 api/lbapi.py
curl -X POST localhost:8123/api/v1/transactions/deposit \
  -d '{"tx_id":"API-001","account":"10000001","amount":"1000.00"}'
```

Manual completo em [`docs/API.md`](docs/API.md): contrato, erros,
idempotência, concorrência, falhas e limites honestos.

## Status

Funcional e testado em Linux x86_64 (GnuCOBOL 3.2.0, Python 3 stdlib).
A API REST é camada de integração: chama os mesmos ENTRY points do
core via driver dedicado, nunca reimplementa as regras.

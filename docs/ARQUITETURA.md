# ARQUITETURA — LEGACYBANK

Sistema bancário educacional com o núcleo 100% em COBOL (GnuCOBOL 3.2.0,
formato livre). Operação via menu interativo (`legacybank`),
processamento em lote (`lb-lote`), API REST (`api/lbapi.py`, TESTE 4)
e web banking (`web/`, TESTE 5).

## Diagrama de módulos

```
                    ┌────────────────────┐
                    │    legacybank      │  menu interativo (14 opções)
                    │    lb-lote         │  processador batch
                    │    lb-init         │  inicializador do diretório
                    └────────┬───────────┘
                             │ CALL (ENTRY points)
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
       ┌────────────┐ ┌────────────┐ ┌────────────┐
       │ lb-financ  │ │  lb-cad    │ │lb-consulta │
       │ núcleo     │ │ cadastros  │ │consultas   │
       │ financeiro │ │            │ │e relatórios│
       └─────┬──────┘ └─────┬──────┘ └─────┬──────┘
             │              │              │
             └──────────────┼──────────────┘
                            ▼
                     ┌────────────┐
                     │  lb-dados  │  persistência, tabelas em
                     │            │  memória, sequências, journal
                     └─────┬──────┘
                           ▼
                 arquivos LINE SEQUENTIAL
              (clientes/contas/movimentos/tx_registry/
               sequencia/auditoria)
```

## Responsabilidades

| Módulo | Papel |
|---|---|
| `lb-dados` | Única camada que toca arquivos. Mantém tabelas em memória (`OCCURS`), gera sequências e TX-IDs, escreve o journal (`movimentos.dat` + `auditoria.log`) e reescreve os masters via temporário + rename atômico. |
| `lb-financ` | Regras de negócio: depósito, saque (tarifa R$ 1,50), transferência (tarifa R$ 2,00), **estorno** (D22). Valida tudo **antes** de mutar; registra OK e rejeições no registro de idempotência. |
| `lb-cad` | Cadastro/atualização de clientes, abertura/bloqueio/desbloqueio/encerramento de contas. Encerrar exige saldo zero. |
| `lb-consulta` | Extrato (reconstrói saldo anterior e corrido a partir do journal), saldo, listagens, relatório geral, formatação monetária pt-BR. |
| `legacybank` | Menu interativo; gera TX-ID automático por operação; persiste após cada operação. |
| `lb-lote` | Lê arquivo de lote, despacha para `lb-financ`, conta ok/rejeitada/duplicada/inválida, gera relatório. `SAVE` + `REOPEN` a cada 1.000 linhas. |
| `lb-init` | Cria o diretório de dados. |

## Fluxo de uma operação financeira

1. `FIN-*` recebe `(TX-ID, conta(s), valor)`.
2. Validações (valor positivo, conta existe e ativa, origem ≠ destino, saldo ≥ valor + tarifa, TX-ID inédito). Qualquer falha → registra `REJEITADA`, **nada é mutado**.
3. Aplica débito/crédito **em memória** (transferência: valida as duas contas antes de tocar qualquer saldo; os dois `UPD`s ocorrem na mesma unidade).
4. Escreve journal (`movimentos.dat`: operação + tarifa separadas) e auditoria.
5. Registra o TX-ID como `OK` no `tx_registry.dat` (idempotência).
6. O chamador (`legacybank`/`lb-lote`) faz `SAVE`: reescreve masters via `.tmp` + rename, atualiza o checkpoint.

## Persistência

- Arquivos texto `LINE SEQUENTIAL`, campos separados por `;` (ver `docs/FORMATO-DADOS.md`).
- Dinheiro sempre em **centavos inteiros** (`PIC 9(13)`); nunca float.
- Masters (`clientes.dat`, `contas.dat`, `tx_registry.dat`, `sequencia.dat`) reescritos por completo a cada `SAVE`, via arquivo temporário + `CBL_RENAME_FILE` (troca atômica no POSIX).
- Journal (`movimentos.dat`, `auditoria.log`) em append contínuo.
- `sequencia.dat` guarda um **checkpoint**: nº de linhas do journal no último `SAVE`. Na abertura, `LB-DATA-CHECK` compara e avisa sobre journal além do checkpoint (possível queda antes do `SAVE`) ou aquém (possível perda). Detecção apenas — sem recuperação automática (ver `docs/LIMITACOES.md`).

## Idempotência

Cada transação carrega um `TX-ID`. O `tx_registry.dat` mapeia `TX-ID → resultado`. Reenvio do mesmo TX-ID retorna o resultado anterior sem reexecutar — inclusive para rejeições (D18).

## Códigos de retorno das operações financeiras

| RC | Significado |
|---|---|
| 0 | OK |
| 1 | Conta inexistente |
| 2 | Conta bloqueada |
| 3 | Conta encerrada |
| 4 | Saldo insuficiente |
| 5 | Valor inválido (não positivo) |
| 6 | Transação duplicada |
| 9 | Conta com saldo não pode ser encerrada (cadastro) |
| 10 | Erro interno |
| 11 | Origem e destino iguais |
| 12 | (estorno) Transação original inexistente |
| 13 | (estorno) Transação original não pode ser estornada (rejeitada, é estorno, ou sem metadados) |
| 14 | (estorno) Transação original já estornada |

## Estorno (D22)

`FIN-ESTORNO(TX-ID-novo, TX-ID-original)` reverte uma transação OK:

1. Valida o TX-ID novo (idempotência, RC 6) e a original (RC 12/13/14).
2. Extrai tipo/conta(s)/valor/tarifa do DETALHE (D21); formato antigo usa o journal (D23).
3. Valida as contas e o saldo da perna de débito **antes** de mutar.
4. Aplica os movimentos compensatórios (`ESTORNO` no journal, tarifa incluída quando houver).
5. Registra o novo TX-ID como OK e carimba a original com `;ESTORNADA` via `LB-TX-UPD` (só o DETALHE muda; TX-ID e índice preservados).

## O que NÃO é COBOL (e por quê)

- `scripts/build.sh`, `tests/*.sh`: ferramentas auxiliares de build e teste (shell). Exigência: só automação, nunca lógica de negócio.
- `tests/test_carga.sh` usa Python apenas para **gerar** o lote de 100k linhas (dados de teste); o processamento é 100% COBOL.
- `api/lbapi.py` (TESTE 4) e `web/` (TESTE 5): camadas de integração e apresentação. Exigência: nenhuma regra financeira — saldo, tarifas, validações, RCs, idempotência e estorno são decididos exclusivamente pelo core COBOL; Python/React apenas transportam e exibem.

## Web banking (TESTE 5)

```
Browser
  → React + TypeScript + Vite (web/)
  → REST /api/v1 (api/lbapi.py, Python stdlib)
  → bin/lb-api (driver COBOL, subprocesso por operação)
  → core COBOL (única autoridade financeira)
  → arquivos LINE SEQUENTIAL (journal/persistência/auditoria)
```

- O frontend nunca calcula dinheiro com `float`: valores transitam como strings decimais e centavos inteiros.
- `POST /batch` executa `bin/lb-lote` sob o lock global da API; o Python só transporta o texto e interpreta o relatório.
- Em produção local a API serve `web/dist` (build estático); em dev, o Vite faz proxy de `/api` para `127.0.0.1:8123` (`scripts/dev-web.sh`).
- Deploy gratuito (Docker + Render, `Dockerfile`/`render.yaml`): container único com GnuCOBOL 3.2.0 compilado do fonte, API e frontend estático; filesystem efêmero → **modo demo** (dados somem em restart/redeploy), sinalizado na UI.

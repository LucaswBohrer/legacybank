# ARQUITETURA — LEGACYBANK

Sistema bancário educacional com o núcleo 100% em COBOL (GnuCOBOL 3.2.0,
formato livre). Sem camada web nesta entrega: a operação é via menu
interativo (`legacybank`) e processamento em lote (`lb-lote`).

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
| `lb-financ` | Regras de negócio: depósito, saque (tarifa R$ 1,50), transferência (tarifa R$ 2,00). Valida tudo **antes** de mutar; registra OK e rejeições no registro de idempotência. |
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

## O que NÃO é COBOL (e por quê)

- `scripts/build.sh`, `tests/*.sh`: ferramentas auxiliares de build e teste (shell). Exigência: só automação, nunca lógica de negócio.
- `tests/test_carga.sh` usa Python apenas para **gerar** o lote de 100k linhas (dados de teste); o processamento é 100% COBOL.

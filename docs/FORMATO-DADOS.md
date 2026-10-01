# FORMATO DOS ARQUIVOS DE DADOS — LEGACYBANK

Todos os arquivos ficam no diretório de dados (padrão `./data`,
configurável por argumento). Texto, `LINE SEQUENTIAL`, campos separados
por `;`, sem cabeçalho. Valores monetários em **centavos inteiros**,
com zeros à esquerda até a largura do campo.

## clientes.dat

```
ID;NOME;CPF;EMAIL;DATA-CAD;STATUS
```

| Campo | Tipo | Exemplo |
|---|---|---|
| ID | X(7) | `C000001` |
| NOME | X(60) | `Ana Silva` |
| CPF | X(14) | `123.456.789-00` |
| EMAIL | X(60) | `ana@email.com` |
| DATA-CAD | X(10) | `2026-10-01` |
| STATUS | X(1) | `A` (ativo) |

Exemplo:

```
C000001;Ana Silva;123.456.789-00;ana@email.com;2026-10-01;A
```

## contas.dat

```
NUMERO;CLIENTE-ID;TIPO;STATUS;SALDO-CENTAVOS;DATA-ABERT
```

| Campo | Tipo | Exemplo |
|---|---|---|
| NUMERO | X(8) | `10000001` |
| CLIENTE-ID | X(7) | `C000001` |
| TIPO | X(2) | `CC` / `CP` |
| STATUS | X(1) | `A` ativa, `B` bloqueada, `E` encerrada |
| SALDO-CENTAVOS | 9(13) | `0000000069650` (= R$ 696,50) |
| DATA-ABERT | X(10) | `2026-10-01` |

Exemplo:

```
10000001;C000001;CC;A;0000000069650;2026-10-01
```

## movimentos.dat (journal, append)

```
SEQ;DATAHORA;TIPO;CONTA;CONTA-DEST;VALOR-CENTAVOS;TX-ID;DESCRICAO
```

| Campo | Tipo | Exemplo |
|---|---|---|
| SEQ | 9(9) | `000000001` |
| DATAHORA | X(19) | `2026-10-01 11:12:40` |
| TIPO | X(13) | `DEPOSITO`, `SAQUE`, `TRANSFERENCIA`, `TARIFA` |
| CONTA | X(8) | `10000001` |
| CONTA-DEST | X(8) | `10000002` ou vazio |
| VALOR-CENTAVOS | 9(13) | `0000000000150` (= R$ 1,50) |
| TX-ID | X(24) | `TX-20261001111240-0001` |
| DESCRICAO | X(40) | `Tarifa de saque` |

Exemplo:

```
000000001;2026-10-01 11:12:40;DEPOSITO;10000001;;0000000100000;TX-20261001111240-0001;Deposito em conta
000000003;2026-10-01 11:12:40;TARIFA;10000001;;0000000000150;TX-20261001111240-0002;Tarifa de saque
```

Tarifas são movimentos próprios (`TARIFA`), sempre vinculados ao TX-ID
da operação que as gerou. O extrato reconstrói o saldo corrido a partir
deste arquivo.

## tx_registry.dat (idempotência)

```
TX-ID;DATAHORA;RESULTADO;DETALHE
```

| Campo | Tipo | Exemplo |
|---|---|---|
| TX-ID | X(24) | `TX-BATCH-0001` |
| DATAHORA | X(19) | `2026-10-01 11:12:46` |
| RESULTADO | X(9) | `OK` / `REJEITADA` |
| DETALHE | X(80) | `DEPOSITO conta=10000001` |

## sequencia.dat

```
ULT-CLIENTE;ULT-CONTA;ULT-MOV;ULT-TX;JOURNAL-CKPT
```

Cinco inteiros separados por `;`: últimos valores das sequências de
cliente, conta, movimento e TX, mais o **checkpoint** (nº de linhas de
`movimentos.dat` no último `SAVE`).

Exemplo:

```
000002;10000003;000000006;0004;0000000000005
```

## auditoria.log (append)

```
DATAHORA | EVENTO
```

Exemplo:

```
2026-10-01 11:12:46 | OK TX-BATCH-0001 conta=10000001
2026-10-01 11:12:46 | DUPLICADA TX-BATCH-0001
2026-10-01 11:12:46 | REJEITADA TX-BATCH-0002 conta=99999999 motivo=Conta inexistente.
```

## Notas

- Nenhum campo contém `;` ou quebra de linha (validação de entrada rejeita).
- Arquivos ausentes na abertura = base vazia (sem erro).
- `sequencia.dat` com formato antigo (4 campos) é aceito; o checkpoint assume 0.

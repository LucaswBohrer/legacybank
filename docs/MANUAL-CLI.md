# MANUAL DO CLI — LEGACYBANK

## Programas

| Programa | Uso |
|---|---|
| `lb-init [dir]` | Cria o diretório de dados (padrão `./data`). |
| `legacybank [dir]` | Menu interativo. |
| `lb-lote [dir] arquivo` | Processa um lote de transações. |

Todos aceitam o diretório de dados como argumento opcional/posicional.

## Menu interativo (`legacybank`)

```
 1 Cadastrar cliente      8  Saldo
 2 Atualizar cliente      9  Listar clientes
 3 Abrir conta            10 Listar contas
 4 Depositar              11 Bloquear conta
 5 Sacar                  12 Desbloquear conta
 6 Transferir             13 Encerrar conta
 7 Extrato                14 Relatorio geral
 0 Sair
```

- Valores aceitam ponto ou vírgula decimal: `150.75` ou `150,75`.
- Cada operação financeira gera um TX-ID automático (`TX-AAAAMMDDHHMMSS-nnnn`).
- Após cada operação que altera dados, o sistema faz `SAVE` (persiste tudo).
- Na abertura, o sistema verifica o checkpoint do journal e avisa sobre anomalias.

### Regras de negócio

- **Depósito:** valor positivo, conta ativa. Sem tarifa.
- **Saque:** valor positivo, conta ativa, saldo ≥ valor + **R$ 1,50** de tarifa.
- **Transferência:** valor positivo, ambas as contas ativas, origem ≠ destino, saldo da origem ≥ valor + **R$ 2,00** de tarifa. Débito e crédito são aplicados na mesma unidade — impossível debitar sem creditar.
- **Bloqueio:** conta bloqueada rejeita depósito, saque e transferência (como origem ou destino).
- **Encerramento:** só com saldo zero.

### Sessão de exemplo

```
$ ./bin/lb-init ./data
Diretorio de dados inicializado: ./data

$ ./bin/legacybank ./data
Opcao: 1
Nome: Ana Silva
CPF: 123.456.789-00
E-mail: ana@email.com
OK: Cliente cadastrado.
ID do cliente: C000001
Opcao: 3
ID do cliente: C000001
Tipo (CC/CP): CC
OK: Conta aberta.
Numero da conta: 10000001
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
------------------------------------------
Saldo atual:    R$ 1.000,00
==========================================
Opcao: 0
```

## Processamento em lote (`lb-lote`)

```
$ ./bin/lb-lote ./data lote.txt
```

Formato do arquivo de lote (um comando por linha; `#` inicia comentário;
linhas vazias são ignoradas):

```
DEPOSITO;TX-ID;CONTA;VALOR
SAQUE;TX-ID;CONTA;VALOR
TRANSFERENCIA;TX-ID;ORIGEM;DESTINO;VALOR
```

Exemplo (`exemplos/lote-exemplo.txt`):

```
# lote de exemplo
DEPOSITO;TX-EX-0001;10000001;1000.00
SAQUE;TX-EX-0002;10000001;100,00
TRANSFERENCIA;TX-EX-0003;10000001;10000002;200.00
```

Saída:

```
Lote concluido: 0000003 ok, 0000000 rejeitadas, 0000000 duplicadas, 0000000 invalidas.
Relatorio: ./data/relatorio_lote_2026_10_01_11_12_46.txt
```

- Linhas rejeitadas são listadas com o motivo; o lote **continua**.
- `TX-ID` repetido (no mesmo lote ou em lotes anteriores) = **duplicada**: não reexecuta.
- `SAVE` + `REOPEN` a cada 1.000 linhas e ao final.
- O relatório do lote é gravado no diretório de dados.

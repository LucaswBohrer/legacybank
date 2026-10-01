# Performance — otimização do índice de TX-ID

Histórico da evolução de desempenho do processamento em lote do LEGACYBANK.

## O problema original

O benchmark de 100.000 transações levava ~30 minutos. A causa, localizada
por leitura do código (não por suposição):

- `src/lb-dados.cbl`, `LB-TX-FIND`: varredura linear de `TXR-ITEM`
  (`PERFORM VARYING ... UNTIL WS-IDX > TXR-COUNT`), chamada 1× por
  transação via `P-VERIFICA-DUPLICADA` em `lb-financ.cbl`.
- `src/lb-dados.cbl`, `P-TX-FIND-DUP`: **segunda** varredura linear do
  mesmo vetor, chamada 1× por transação via `LB-TX-ADD`.

Cada transação financeira executava portanto 2 buscas O(n) → o lote
inteiro era O(n²): ~10¹⁰ comparações de strings para 100k transações.

Outros custos O(n) foram investigados e descartados como gargalo:

- `P-SALVA-TXREG` reescreve `tx_registry.dat` inteiro a cada SAVE (100× no
  lote de 100k): ~320 MB de I/O no total — segundos, não minutos, e
  necessário para a semântica de crash/recovery. Mantido como está.
- `LB-CTA-FIND` é linear mas sobre o vetor de contas (n pequeno).
- Journal é append-only, O(1) por operação.

## A solução

Índice hash com encadeamento, implementado **dentro de `lb-dados.cbl`**
(o módulo dono do registro de idempotência) — ver D20 em `DECISOES.md`.

- 65536 buckets (`IDX-BKT`), elos em `IDX-NXT` (1 por posição de
  `TXR-ITEM`, até 500000).
- Hash djb2 sobre o TX-ID sem espaços; colisões por lista ligada com
  inserção na cabeça.
- `LB-TX-FIND` e `P-TX-FIND-DUP` viraram lookup O(1) médio; `LB-TX-ADD`
  encadeia a nova posição; `P-CARREGA-TXREG` reconstrói o índice.
- O índice é **estado derivado**: nunca persistido, reconstruído a cada
  LOAD a partir de `tx_registry.dat`. Crash não o corrompe.
- `TXR-ITEM` é append-only (nunca há remoção/alteração de TX-ID), então o
  índice nunca precisa de remoção.
- Semântica de "primeira ocorrência" preservada exatamente: o lookup
  percorre a cadeia guardando o último match (= posição mais antiga),
  idêntico ao retorno da busca linear mesmo em caso de TX-ID duplicado
  no arquivo (só possível com adulteração externa).
- Assinaturas dos ENTRY points inalteradas; nenhum outro programa mudou.

## Alternativas consideradas

| Alternativa | Por que não |
|---|---|
| Busca binária sobre vetor ordenado | Inserção O(n) por TX (deslocamento); pior que o problema |
| Índice em arquivo auxiliar persistido | Duplica fonte da verdade; risco de divergência pós-crash; I/O extra |
| Checar só a última posição (TX sequenciais) | Heurística frágil; quebra com TX fora de ordem |
| Tabela hash em módulo separado (`lb-idx.cbl`) | Acoplamento idêntico (o índice mapeia posições de `TXR-ITEM`, que pertence a `lb-dados`); separar só espalharia o estado sem ganho |
| Reescrever o sistema | Fora do escopo; a missão era otimizar sem regressão |

## Resultados (medidos no ambiente, sem arredondamento)

| Lote | Antes (busca linear) | Depois (índice hash) | Speedup |
|---|---|---|---|
| 10.000 | 28,289 s | 0,689 s | 41,1× |
| 50.000 | 521,704 s | 4,984 s | 104,7× |
| 100.000 | 1.680,997 s | 13,395 s | 125,5× |

Mesmos arquivos de lote (seed fixa 42) nas duas execuções; tempos de
parede medidos com `date +%s.%N`. O speedup cresce com n, como esperado
de O(n²) → O(n): o custo por transação ficou ~constante (~0,13 ms).

## Integridade

Reconciliação independente (`scripts/reconciliar.py`) entre os diretórios
de dados do run antes/depois, sobre o **mesmo** lote:

- saldos das contas: equivalentes
- nº de movimentos, totais por tipo, tx_registry por resultado: equivalentes
- auditoria (nº linhas e distribuição de eventos): equivalente
- sequência de TX-IDs: idêntica

Suíte completa: **63/63** (funcionais 22 + integridade 8 + batch 10 +
23 novos testes de regressão do índice em `tests/test_indice.sh`:
TX nova, duplicada, rejeitada, reinicialização/reconstrução do índice,
atomicidade de transferência, reenvio e volume de 3.000 TXs).

## Trade-offs

- **Memória:** +~5 MB (590 KB buckets + 4,5 MB elos) — desprezível frente
  aos ~67 MB da tabela `TXR-ITEM`.
- **Persistência:** nenhuma mudança; arquivos e formatos idênticos.
- **Recuperação:** nenhuma mudança; índice reconstruído no LOAD em O(n).
- **Complexidade:** +~90 linhas concentradas em `lb-dados.cbl`, com
  invariante documentado no próprio fonte.
- **Manutenção:** quem tocar em `TXR-ITEM` precisa manter o invariante do
  índice (hoje: só `LB-TX-ADD` e `P-CARREGA-TXREG` escrevem).

## Limitações restantes

- `P-IDX-LIMPA` zera 65536 buckets a cada LOAD (milissegundos; irrelevante).
- `P-SALVA-TXREG` continua O(n) por SAVE — aceitável e necessário.
- O teto de 500000 TXs por diretório de dados permanece (`MAX-TXREG`).

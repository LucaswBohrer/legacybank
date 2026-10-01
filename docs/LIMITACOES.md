# LIMITAÇÕES CONHECIDAS — LEGACYBANK

Limitações honestas da entrega atual. Nada aqui é defeito escondido:
é o mapa do que evoluir a seguir.

## L01 — Sem concorrência

O sistema é single-user. Duas instâncias sobre o mesmo diretório de
dados corromperiam os arquivos (sem locking). Para multiusuário seria
necessário lock de arquivo (`fcntl`) ou um gerenciador transacional.

## L02 — Idempotência O(n) por operação — RESOLVIDA

~~`LB-TX-FIND` varre o registro linearmente. O custo por transação cresce
com o total de transações já processadas (O(n²) no lote). Medido: 100k
transações levam dezenas de minutos.~~

**Resolvida** com o índice hash em memória sobre o TX-ID
(`docs/PERFORMANCE.md`, D20): lookup O(1) médio, mesma semântica,
mesmos arquivos. Medido: 100k transações em 13,4 s (era 1.681 s).
Mantida aqui como registro histórico — era a limitação honesta da v1.0.

## L03 — Checkpoint detecta, não recupera

`LB-DATA-CHECK` avisa sobre journal além do checkpoint (queda entre o
append e o `SAVE`) ou aquém (perda), mas não reaplica nada
automaticamente. Recuperação hoje é manual: a linha do journal contém
todos os campos necessários para reconstituir a operação.

## L04 — Capacidades fixas em memória

| Tabela | Limite |
|---|---|
| Clientes | 20.000 |
| Contas | 20.000 |
| Transações (idempotência) | 500.000 |

Acima disso, `LB-*-ADD` retorna erro em vez de corromper. São constantes
no fonte (`MAX-*` em `lb-dados.cbl`), ajustáveis com recompilação —
à custa de memória (a tabela de transações ocupa ~66 MB).

## L05 — Sem autenticação ou autorização

Qualquer pessoa com acesso ao diretório de dados opera qualquer conta.
É um sistema educacional, não um produto bancário.

## L06 — Validações simplificadas

CPF: apenas formato (11 dígitos); sem dígito verificador. E-mail: exige
exatamente um `@`. Nomes e descrições não aceitam `;` (separador dos
arquivos).

## L07 — Sem fuso horário

`LB-NOW` usa o horário local da máquina.

## L08 — Sem camada web

Por decisão de escopo (D12): a entrega atual é CLI + batch. Uma API/web
deverá chamar os mesmos ENTRY points do núcleo — nunca reimplementar
as regras.

## L09 — Estorno de transação antiga varre o journal

Transações criadas antes do DETALHE enriquecido (D21) são estornadas via
`LB-MOV-FIND-TX`, que varre `movimentos.dat` em disco (O(n)). É o caminho
de compatibilidade/migração (D23): transações novas usam o índice hash
O(1). Em bases com milhões de movimentos e muitas reversões legadas,
considerar migração assistida do registry antigo para o formato D21.

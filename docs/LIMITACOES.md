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

## L08 — Camada web: API REST de integração (TESTE 4, 2026-10-01)

~~Por decisão de escopo (D12): a entrega atual é CLI + batch.~~

**Implementada** como camada fina de integração (`api/lbapi.py` +
`bin/lb-api`, D25–D28, `docs/API.md`). Limites honestos da camada:

- **Throughput**: ~15-18 op/s (lock global + spawn de subprocesso por
  operação, ~60-95ms cada). A API não aumenta a capacidade do core.
- **Sem autenticação**: escuta só em 127.0.0.1; expor publicamente
  exige reverse proxy com auth/TLS (fora do escopo).
- **Sem retry automático**: o retry seguro é o replay idempotente pelo
  cliente (mesmo `tx_id`).
- **Queda mid-operação**: se o driver morre entre journal e SAVE, o
  `LB-DATA-CHECK` (L03) faz a próxima operação retornar 503 até
  intervenção manual — a API não faz auto-reparo silencioso.

## L09 — Estorno de transação antiga varre o journal

Transações criadas antes do DETALHE enriquecido (D21) são estornadas via
`LB-MOV-FIND-TX`, que varre `movimentos.dat` em disco (O(n)). É o caminho
de compatibilidade/migração (D23): transações novas usam o índice hash
O(1). Em bases com milhões de movimentos e muitas reversões legadas,
considerar migração assistida do registry antigo para o formato D21.

## L10 — Portabilidade Windows/MSYS2 (D29–D32, 2026-10-01)

**Status:** dependências de shell/SO eliminadas do produto; validação
real no Windows/MSYS2-UCRT64 pendente (executada pelo Lucas).

Corrigido:
- `lb-init` não usa mais `CALL "SYSTEM"` (caía no cmd.exe no Windows);
  cria diretórios via `CBL_CREATE_DIR` (D29) **e** cria os 6 arquivos
  de dados ausentes via `LB-DATA-CREATE-FILES` (D32, sem truncar).
- `P-RENAME-ATOMICO`: `rename()` do UCRT falha com destino existente;
  fallback delete+rename só nesse caso (D30). No Linux o caminho é o
  rename atômico de antes.
- Recuperação 35 do journal/auditoria simplificada para `OPEN OUTPUT`
  único (D32): equivale ao EXTEND em arquivo novo e evita a sequência
  de 4 passos que não se recuperava no Windows.
- `api/lbapi.py` resolve `lb-api.exe` no Windows (D31).

Limites honestos restantes no Windows:
- **MSYS2 converte argv, não env vars:** caminhos absolutos estilo
  `/tmp/...` passados como *argumento* chegam convertidos ao .exe, mas
  em *variável de ambiente* (`LBAPI_DATA_DIR`) o Python nativo vê o
  caminho cru. Por isso os testes usam diretório relativo.
- **Concorrência entre processos:** no Windows o bloqueio de arquivo é
  mais estrito que no Linux; o desenho continua sendo um escritor por
  vez (lock da API, D28). CLI e API concorrentes nunca foram suportados.
- **Acentos no terminal:** mensagens com ç/ã podem sair com encoding
  trocado no cmd.exe; cosmético, não afeta dados (testes usam `R$`).
- `scripts/benchmark.sh` ainda assume `/tmp` (ferramenta de dev, fora
  da suíte).

## L05 — Web banking é educacional, não production-ready

O TESTE 5 entrega um web banking funcional, mas: sem autenticação
(qualquer um com acesso à URL opera tudo), sem HTTPS próprio (depende
do provedor), sem rate limiting, sem CSRF, API escuta em `127.0.0.1`
por desenho local. Não expor sem uma camada de auth na frente.

## L06 — Deploy gratuito = filesystem efêmero (modo demo)

No plano gratuito (Render e similares) o disco é efêmero: cada
restart/redeploy zera clientes, contas e transações. A UI sinaliza
"modo demo". Para persistência real seria preciso disco persistente
(plano pago) ou backend de dados externo — fora do escopo educacional.

## L07 — Quirk GnuCOBOL 3.2.0: ENTRY no fim do programa

Documentado em D34: novas ENTRYs devem ficar no meio do arquivo
(antes dos parágrafos auxiliares), nunca como última instrução da
`PROCEDURE DIVISION`. Válido para a versão 3.2.0; outras versões não
foram testadas.

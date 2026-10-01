# DECISÕES TÉCNICAS — LEGACYBANK

Registro das decisões de arquitetura tomadas durante o desenvolvimento.
Cada decisão traz o motivo; nada aqui é arbitrário.

---

## D01 — Compilador: GnuCOBOL 3.2.0

**Decisão:** usar o GnuCOBOL 3.2.0, compilado a partir do código-fonte.

**Motivo:** era o único compilador COBOL realista disponível. O ambiente
(Linux x86_64) não possuía nenhum compilador COBOL instalado e o `apt`
estava com os repositórios inacessíveis (update travado por vários minutos).
As alternativas reais eram:

- GnuCOBOL via pacote da distro → indisponível (repositório inacessível);
- GnuCOBOL compilado do fonte → **escolhido** (funcionou);
- Micro Focus / IBM Enterprise COBOL → proprietários, sem licença;
- "COBOL" emulado em outra linguagem → proibido pela restrição fundamental.

**Como foi obtido:** tarball oficial de `ftp.gnu.org/gnu/gnucobol/`
(baixado com retry, pois o mirror do SourceForge abortava a conexão).
Dependências compiladas na ordem: `m4-1.4.19` → `gmp-6.3.0` →
`gnucobol-3.2`, com `./configure --without-db --without-curses`
(sem Berkeley DB e sem ncurses, recursos não necessários ao projeto).
Instalado em `/usr/local`. Tarballs preservados em
`~/workspace/tools/legacybank-toolchain/` para reconstrução.

**Verificação:** `cobc --version` → `cobc (GnuCOBOL) 3.2.0`; programa
"HELLO WORLD" compilado com `cobc -x` e executado com sucesso.

## D02 — Formato do código-fonte: FREE

**Decisão:** `>>SOURCE FORMAT IS FREE` em todos os fontes.

**Motivo:** formato livre é suportado pelo GnuCOBOL 3.x, elimina a rigidez
de colunas do COBOL clássico (área A/B), melhora a legibilidade e o `diff`
no Git. O projeto é educacional; não há mainframe de destino que exija
formato fixo.

## D03 — Persistência: arquivos texto LINE SEQUENTIAL delimitados

**Decisão:** persistência em arquivos texto, um registro por linha, campos
separados por `;` (ponto-e-vírgula), via `ORGANIZATION IS LINE SEQUENTIAL`.

**Motivo:**
- Sem banco de dados externo (exigência do projeto: "não introduza um
  banco de dados externo sem necessidade").
- Sem Berkeley DB: o GnuCOBOL foi compilado `--without-db`, logo arquivos
  `INDEXED` não estão disponíveis. Mesmo que estivessem, arquivos texto
  são inspecionáveis com `cat`/`grep`, o que é pedagógico e facilita debug
  e testes.
- `;` como separador em vez de `,` porque valores monetários usam `.`
  como separador decimal e nomes podem conter vírgula.

Arquivos (todos sob o diretório de dados, padrão `./data`):

| Arquivo            | Conteúdo                                              | Padrão de escrita        |
|--------------------|-------------------------------------------------------|--------------------------|
| `clientes.dat`     | cadastro de clientes (master)                         | reescrito por completo   |
| `contas.dat`       | cadastro de contas + saldos (master)                  | reescrito por completo   |
| `movimentos.dat`   | journal de movimentações (append-only)                | append                   |
| `tx_registry.dat`  | registro de transações processadas (idempotência)     | reescrito por completo   |
| `sequencia.dat`    | contadores de IDs                                     | reescrito por completo   |
| `auditoria.log`    | log de auditoria legível por humanos (append-only)    | append                   |

O formato exato de cada linha está em `docs/FORMATO_ARQUIVOS.md`.

## D04 — Dinheiro em centavos inteiros, nunca float

**Decisão:** todos os valores monetários são armazenados e calculados como
inteiros de centavos (`PIC 9(13)`, até R$ 99.999.999.999,99). A entrada
do usuário (`150.75`) é convertida com `FUNCTION NUMVAL` × 100 e
arredondada; a exibição usa máscara `ZZZ.ZZZ.ZZZ.ZZ9,99`.

**Motivo:** aritmética de ponto flutuante não representa valores decimais
exatamente (0.1 + 0.2 ≠ 0.3). Em sistema bancário isso é inaceitável.
Centavos inteiros eliminam a classe inteira de erros de arredondamento.

## D05 — Arquitetura em módulos com ENTRY points

**Decisão:** em vez de um programa monolítico, o sistema é dividido em
programas COBOL com múltiplos `ENTRY`:

- `LB-DADOS` — camada de dados: carrega tudo para tabelas `OCCURS` na
  memória, expõe busca/inserção/atualização, grava de volta ao final.
- `LB-FINANC` — regras financeiras: depósito, saque, transferência,
  tarifas. Sem `DISPLAY`; retorna código de erro + mensagem.
- `LB-CAD` — cadastros: cliente e conta (CRUD, bloqueio/desbloqueio).
- `LB-LOTE` — executável batch (lê arquivo, processa, emite relatório).
- `LEGACYBANK` — executável interativo (menu de terminal).
- `LB-INIT` — inicializa o diretório de dados.

**Motivo:** separação de responsabilidades (exigência §23), testabilidade
(os testes chamam `LB-FINANC`/`LB-CAD` sem passar pelo menu) e compilação
única: `cobc -x -o bin/legacybank src/*.cbl` resolve os `CALL`s no link.

## D06 — Atomicidade via "validar tudo, depois mutar" + rewrite atômico

**Decisão:** toda operação financeira segue o protocolo:

1. validar todos os pré-requisitos (conta existe, status, valor, saldo);
2. verificar idempotência (TX já processada?);
3. **só então** mutar o saldo em memória, gravar journal e registrar TX.

Para persistência dos masters: escreve-se em arquivo temporário e faz-se
`rename` por cima do original (operação atômica no POSIX). O journal é
append-only: cada linha é um registro completo e independente.

**Motivo:** garante que "operação rejeitada não altera saldo" (§14) e que
transferência nunca debita sem creditar (§8): débito e crédito acontecem
na mesma unidade de validação, sem ponto de falha entre eles.

## D07 — Idempotência por registro de TX_ID

**Decisão:** todo processamento gera ou recebe um `TX-ID`. Antes de
executar, o sistema consulta `tx_registry.dat`; se o ID existir, retorna
o resultado anterior sem tocar em saldos. Formato do ID:
`TX-AAAAMMDDHHMMSS-NNNN` (timestamp + sequencial de 4 dígitos).

**Motivo:** exigência §12. O registro guarda também o resultado anterior
(`OK`/`REJEITADA`), de modo que a retentativa devolve exatamente a mesma
resposta.

## D08 — Tarifas fixas e explícitas

**Decisão:**
- `SAQUE`: tarifa de R$ 1,50 debitada da conta junto com o saque.
- `TRANSFERENCIA`: tarifa de R$ 2,00 debitada da conta de origem.
- `DEPOSITO`: isento.

A tarifa aparece no extrato como movimento próprio do tipo `TARIFA`,
vinculado ao mesmo `TX-ID` da operação. A tarifa **faz parte da
validação de saldo**: saque de R$ 100,00 exige saldo ≥ R$ 101,50;
se não houver, a operação inteira é rejeitada (nada é debitado).

**Motivo:** §10 pede simplicidade + documentação. Tarifa embutida no
movimento principal esconderia informação do extrato; movimento separado
é auditável.

## D09 — Estados de conta: A / B / E

**Decisão:** `A`=ATIVA, `B`=BLOQUEADA, `E`=ENCERRADA.
- Movimentação financeira: somente `A`.
- Conta `B` rejeita débito **e** crédito (inclusive depósito e
  transferência de entrada): conta bloqueada é conta congelada.
- `E` só é permitido com saldo zero; conta encerrada nunca volta.
- `B` ↔ `A` livre (bloquear/desbloquear).

**Motivo:** regras coerentes e simples (§5), sem meio-termo ambíguo.

## D10 — Diretório de dados configurável por argumento

**Decisão:** todo executável aceita o diretório de dados como primeiro
argumento de linha de comando (`ACCEPT ... FROM COMMAND-LINE`).
Padrão: `./data`.

**Motivo:** os testes precisam de um diretório isolado por cenário sem
conflitar com os dados "reais". Variável de ambiente foi evitada porque a
leitura de env no GnuCOBOL exigiria chamadas não-portáveis; argumento de
linha de comando é padrão e explícito.

## D11 — Testes em shell script (ferramenta auxiliar)

**Decisão:** a suíte de testes é um harness em `bash`
(`tests/run_tests.sh`) que executa os binários COBOL reais com entradas
roteirizadas e valida stdout, códigos de saída e conteúdo dos arquivos
de dados. Geração de massa para o teste de carga também em shell.

**Motivo:** §2 permite outras linguagens em "ferramentas auxiliares,
scripts de build/testes". Testar o binário real (não um mock) é o que
dá valor; o núcleo bancário permanece 100% COBOL.

## D12 — Sem camada web nesta entrega

**Decisão:** nenhuma API, nenhum frontend. Interface = terminal.

**Motivo:** exigência explícita (§15, §29: "Não implemente essa camada
agora").

---

## D13 — Campos X(8) nunca passam direto para parâmetros X(24)

**Decisão:** todo `CALL` para `LB-CTA-FIND`/`LB-TX-FIND` passa por um
campo intermediário `X(24)` (`WS-ID24`) preenchido com
`FUNCTION TRIM(...)`.

**Motivo:** bug real encontrado em teste: `LK-CONTA PIC X(8)` era passado
para `LK-ID PIC X(24)`; o callee lia 16 bytes além do campo (lixo da
memória adjacente) e nenhuma conta era encontrada. Em COBOL, `CALL..USING`
passa endereço — o tamanho é o do item no programa chamado.

## D14 — `STRING ... INTO` sempre precedido de limpeza do destino

**Decisão:** antes de cada `STRING`, `MOVE SPACES TO <destino>`.

**Motivo:** bug real: `STRING` não preenche o restante do destino; restos
de strings anteriores vazavam para os arquivos (`contas.dat`,
`movimentos.dat`, `tx_registry.dat`, `sequencia.dat` com caudas
corrompidas). 28 pontos corrigidos mecanicamente. Efeito colateral
aprendido: a linha inserida não pode terminar com `.` dentro de
`PERFORM...END-PERFORM` (o ponto encerra o escopo inline).

## D15 — Rejeição preserva o código de erro de negócio

**Decisão:** `P-REGISTRA-REJEITADA` e `P-TX-OK-*` usam `WS-RC-TX`
próprio; nunca `LK-RC`.

**Motivo:** bug real: `LB-TX-ADD ... USING ... LK-RC` sobrescrevia o RC
(1–5, 11) com 0, e toda rejeição era reportada como "OK:".

## D16 — Falha de invariante interna aborta (STOP RUN)

**Decisão:** se `LB-CTA-UPD` falhar após `FIND` bem-sucedido (conta sumiu
da memória — invariante violada), o programa aborta com `STOP RUN
RETURNING 3` em vez de continuar.

**Motivo:** continuar significaria persistir um razão inconsistente.
Como o caso é inalcançável em execução normal, abortar alto é mais
honesto que mascarar.

## D17 — `lb-init` sem shell injection

**Decisão:** o caminho é envolvido em aspas simples; caminhos contendo
`'` são rejeitados; retorno do `mkdir` é verificado.

**Motivo:** a versão anterior interpolava o caminho cru em
`mkdir -p <caminho>` via `CALL "SYSTEM"`.

## D18 — Idempotência inclui rejeições

**Decisão:** transações rejeitadas também são registradas no
`tx_registry.dat` com resultado `REJEITADA`; o reenvio do mesmo TX-ID
retorna "duplicada" sem reexecutar.

**Motivo:** idempotência por identificador, sem exceção: o mesmo TX-ID
sempre produz o mesmo resultado observável.

---

## D19 — Checagem de duplicada antes de qualquer validação de negócio

**Decisão:** nos três ENTRY points financeiros (`FIN-DEPOSITO`,
`FIN-SAQUE`, `FIN-TRANSFERENCIA`), `P-VERIFICA-DUPLICADA` roda logo após
`P-INICIO-OP`, antes da validação de valor, contas e saldo.

**Motivo:** bug real de semântica: com a ordem antiga (validar → depois
checar duplicada), o reenvio de um TX-ID rejeitado re-executava a
validação e era contado como "rejeitada" de novo, em vez de "duplicada".
Idempotência correta: o mesmo TX-ID sempre retorna o resultado anterior
sem reexecutar — inclusive quando o resultado anterior foi rejeição.

---

## D20 — Índice hash de TX-ID em memória (otimização do lote)

**Decisão:** substituir as duas buscas lineares de TX-ID por transação
(`LB-TX-FIND` e `P-TX-FIND-DUP`, ambas O(n) sobre `TXR-ITEM`) por um índice
hash com encadeamento implementado dentro de `lb-dados.cbl`.

**Motivo:** investigação do código mostrou que cada transação financeira
executava 2 varreduras completas do registro de idempotência → lote O(n²)
(~10¹⁰ comparações para 100k TXs; ~30 min medidos). O índice (65536
buckets, hash djb2, ~5 MB) reduz o lookup a O(1) médio sem alterar nenhum
formato de arquivo, nenhuma assinatura de ENTRY point e nenhuma semântica:
idempotência (inclusive de rejeições), journal, checkpoint, auditoria,
persistência e atomicidade de transferências permanecem idênticos —
ver `docs/PERFORMANCE.md` e a reconciliação antes/depois.

**Alternativas descartadas:** busca binária (inserção O(n)); índice
persistido em arquivo auxiliar (duplica fonte da verdade, risco pós-crash);
módulo separado `lb-idx.cbl` (o índice mapeia posições de `TXR-ITEM`, que
pertence a `lb-dados` — separar espalharia o estado sem ganho); checagem
só da última posição (heurística frágil para TX fora de ordem).

**Correção durante a implementação:** o contador `WS-IDX-J` foi declarado
`PIC 9(4)` mas `P-IDX-LIMPA` itera até 65536 — estouro que travaria em loop
infinito no primeiro LOAD. Corrigido para `PIC 9(5)` antes do primeiro
rebuild; pego por revisão do fonte, não por teste (o binário otimizado
nunca chegou a rodar com o defeito).

---

## D21 — DETALHE enriquecido no registro de idempotência

**Decisão:** `P-TX-OK-DEPOSITO/SAQUE/TRANSFERENCIA` passam a gravar no
`TXR-DETALHE` metadados estruturados (`conta=`, `valor=`, `tarifa=`,
`origem->destino`) em vez do texto livre anterior (`DEPOSITO 150.75`).

**Motivo:** o estorno (D22) precisa reconstruir tipo, conta(s), valor e
tarifa da transação original sem reexecutar lógica de negócio. Guardar os
metadados no próprio registro de idempotência torna o estorno uma operação
local O(1) via índice hash, sem varredura do journal no caminho quente.

**Alternativas descartadas:** re-derivar do journal a cada estorno
(varredura O(n) em disco no fluxo normal); tabela auxiliar persistida
(duplica fonte da verdade).

---

## D22 — Estorno de transações (`FIN-ESTORNO`)

**Decisão:** novo ENTRY `FIN-ESTORNO` em `lb-financ.cbl` que reverte
integralmente uma transação OK anterior, com novo TX-ID, movimentos
compensatórios do tipo `ESTORNO` no journal e carimbo `;ESTORNADA` no
`TXR-DETALHE` da original (via `LB-TX-UPD`, que altera só o detalhe
preservando TX-ID e índice).

**Regras:** idempotência do novo TX-ID (RC 6); original inexistente (RC 12);
original rejeitada/estorno/sem metadados (RC 13); original já estornada
(RC 14); estorno de estorno proibido; devolução integral de tarifas;
validação das contas antes de qualquer mutação; transferência revertida
atomicamente (débito no destino + crédito na origem com tarifa na mesma
unidade); saldo insuficiente na perna de débito rejeita sem alterar nada
(RC 4). Depósito→debita valor; saque→credita valor+tarifa;
transferência→debita destino e credita origem valor+tarifa.

**Motivo:** chargeback/estorno é operação bancária básica; o desenho segue
as garantias existentes (idempotência, journal append-only, auditoria,
atomicidade) em vez de criar um caminho especial.

---

## D23 — Compatibilidade do estorno com o formato antigo (journal como fonte da verdade)

**Decisão:** transações criadas antes de D21 (DETALHE sem `valor=`) são
estornáveis via fallback `P-EST-LEGADO-JOURNAL`: `LB-MOV-FIND-TX` varre
`movimentos.dat`, localiza o movimento principal pelo TX-ID e soma os
movimentos `TARIFA` do mesmo TX-ID.

**Motivo:** o formato antigo não guarda conta/valor no DETALHE, mas o
journal sempre guardou (SEQ;DATAHORA;TIPO;CONTA;DEST;VALOR;TX-ID;...).
Usar o journal como fonte da verdade evita migração de dados e preserva
o formato dos arquivos. O custo O(n) em disco ocorre só no caminho
legado, nunca no fluxo quente (transações novas usam D21, O(1)).

**Detalhe de implementação:** `ARQ-MOV` fica aberto em EXTEND durante a
sessão; o FIND-TX fecha, abre em INPUT, varre e **reabre em EXTEND**
(`P-ABRE-APPEND-MOV`) para os appends seguintes não falharem. Pegou-se
isso por `FS=41` em teste real, não por revisão.

---

## D24 — Parser do registry preserva `;` no DETALHE

**Decisão:** `P-PARSE-TXREG` não faz mais `UNSTRING ... INTO 4 campos`
(que descartava tudo após o 4º `;`). Agora localiza o 3º `;` e trata
tudo após ele como DETALHE integral.

**Motivo:** bug real encontrado em teste: o carimbo `;ESTORNADA` (D22)
era gravado corretamente no SAVE, mas o LOAD o descartava — qualquer
processo que carregasse e salvasse (inclusive consultar saldo no menu)
apagava o carimbo e permitia o segundo estorno. O `UNSTRING` em 4 campos
silenciosamente perdia o 5º campo. A correção preserva o formato do
arquivo e é compatível com linhas antigas (sem `;` extra).

---

## D25 — Estratégia de integração HTTP↔COBOL (TESTE 4)

**Decisão:** API em Python (stdlib apenas) que invoca um driver COBOL fino
(`bin/lb-api`, novo `src/lb-api.cbl`) como **subprocesso por operação**.
O driver faz `INIT → LOAD → 1 ENTRY → SAVE → stdout legível por máquina`
e nada mais. Toda invocação ao core é serializada por um lock na API.

**Alternativas comparadas e descartadas:**

1. **Biblioteca compartilhada** (`cobc -b` + ctypes/cffi): tecnicamente
   possível, mas os módulos usam WORKING-STORAGE global (tabelas em
   memória, índice hash, file descriptors). O runtime GnuCOBOL não oferece
   garantias de thread-safety para esse uso; chamadas concorrentes
   corromperiam o estado. Um segfault no core derrubaria a API inteira.
   Ganho de latência não justifica o risco (prioridades 1–5 da missão).
2. **Wrapper C ABI dedicado**: mesmos problemas de (1), mais camada extra.
3. **Daemon COBOL persistente** (pipe/socket): COBOL não tem sockets
   nativos; exigiria interop C, protocolo próprio e gerenciamento de ciclo
   de vida — complexidade sem benefício, já que o estado vive nos arquivos.
4. **Reuso do `lb-lote` via arquivo de 1 linha**: saída human-readable
   (frágil para parse) e efeito colateral (relatório por execução).

**Por que subprocesso:** isolamento de processo (crash/timeout do core não
derruba a API; `kill` é o controle de timeout); alinhado à arquitetura
existente (CLI e batch já são processos separados — L01 estende-se
naturalmente: a API é o único escritor); sem estado compartilhado;
custo medido de ~90 ms/operação (spawn + LOAD + SAVE), aceitável para o
critério de performance da missão ("descobrir o custo", não otimizar
prematuramente).

**Fronteira:** dinheiro atravessa como **centavos inteiros** (argv);
o driver nunca calcula tarifa, saldo ou regra — só despacha ENTRYs
existentes e formata a saída. Leitura e escrita passam pelo mesmo lock
porque até consultas disparam SAVE (rewrite via temp+rename).

**Revisão de D12:** "nenhuma API" era escopo da entrega original; o TESTE 4
autoriza a camada de integração, mantendo o core como única fonte de
verdade financeira.

---

## D26 — Novos ENTRYs de formatação (boundary, não core)

**Decisão:** `CONS-EXTRATO-API` em `lb-consulta.cbl` emite o extrato em
linhas máquina-legíveis (`STMT-*:`); o driver formata `LB-TX-FIND` e
`LB-CTA-FIND` da mesma forma. Nenhum ENTRY existente foi alterado.

**Motivo:** o parse do journal (sinais, saldo corrido) continua no COBOL;
a API só converte linhas `CHAVE: valor` em JSON. Aditivo, sem mudança de
comportamento do core.

---

## D27 — Mapeamento RC → HTTP

| Situação | HTTP | Corpo |
|---|---|---|
| Operação executada (RC 0, 1ª vez) | 201 | tx_id, rc, message, detalhes |
| Replay idempotente (RC 6) | 200 | mesmos dados + `"replay": true` |
| Consulta OK | 200 | dados |
| Payload inválido | 400 | erro, campo |
| Conta/transação inexistente (consulta) | 404 | erro |
| Rejeição semântica do core (RC 1–5, 11–14) | 422 | tx_id, rc, message |
| Core indisponível/timeout/crash | 503 | erro |
| Erro interno da API | 500 | erro |

409 não é usado: replay idempotente retorna 200 (padrão de idempotency-key).
O RC financeiro original é sempre preservado no corpo.

---

## D28 — Concorrência: serialização por desenho (VALIDADA na Fase F, 2026-10-01)

**Decisão:** um lock global na API serializa **todas** as invocações ao
`lb-api` (leitura e escrita).

**Motivo:** L01 — o core é single-user sem file locking; dois processos
escrevendo simultaneamente disputariam `contas.dat`/`tx_registry.dat`
(rewrite via temp+rename) e o journal (append).

**Validação experimental (Fase F):**
- SEM o lock (20 depósitos concorrentes diretos no driver): 11 falharam
  com `FS=61` (contenção de arquivo), 9 retornaram RC 00 mas o saldo só
  subiu 2×1000 em vez de 20×1000 — **lost updates**: R$ 180,00 perdidos.
  Demonstração reproduzível de que o core NÃO é seguro para concorrência.
- COM o lock (via HTTP): 20/20, 50/50 e 100/100 requisições concorrentes
  retornaram 201 com reconciliação EXATA do saldo (2700,00 = 100×10,00
  + 170×10,00). Thundering herd (30 threads, mesmo TX-ID): exatamente
  1×201 + 29×200 (replay), saldo +5,00 exato.
- Custo: ~60-95ms por operação serializada (~15-18 op/s). Documentado
  como limitação, não como defeito.

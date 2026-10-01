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

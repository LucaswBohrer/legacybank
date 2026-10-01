>>SOURCE FORMAT IS FREE
*>==============================================================*
*> LEGACYBANK - LB-DADOS
*> Camada de persistencia. Mantem os cadastros (clientes, contas),
*> o registro de idempotencia e os contadores em memoria (tabelas
*> OCCURS) durante a sessao; grava de volta ao disco de forma
*> atomica (arquivo temporario + rename) em LB-DATA-SAVE.
*> O journal de movimentos e o log de auditoria sao append-only.
*>
*> Uso tipico:
*>   CALL "LB-DATA-INIT" USING WS-DIR
*>   CALL "LB-DATA-LOAD" USING WS-RC
*>   ... operacoes ...
*>   CALL "LB-DATA-SAVE" USING WS-RC
*>==============================================================*
IDENTIFICATION DIVISION.
PROGRAM-ID. LB-DADOS.

ENVIRONMENT DIVISION.
INPUT-OUTPUT SECTION.
FILE-CONTROL.
    SELECT ARQ-CLI ASSIGN TO WS-PATH-CLI
        ORGANIZATION IS LINE SEQUENTIAL
        FILE STATUS IS WS-FS-CLI.
    SELECT ARQ-CTA ASSIGN TO WS-PATH-CTA
        ORGANIZATION IS LINE SEQUENTIAL
        FILE STATUS IS WS-FS-CTA.
    SELECT ARQ-MOV ASSIGN TO WS-PATH-MOV
        ORGANIZATION IS LINE SEQUENTIAL
        FILE STATUS IS WS-FS-MOV.
    SELECT ARQ-TXR ASSIGN TO WS-PATH-TXR
        ORGANIZATION IS LINE SEQUENTIAL
        FILE STATUS IS WS-FS-TXR.
    SELECT ARQ-SEQ ASSIGN TO WS-PATH-SEQ
        ORGANIZATION IS LINE SEQUENTIAL
        FILE STATUS IS WS-FS-SEQ.
    SELECT ARQ-AUD ASSIGN TO WS-PATH-AUD
        ORGANIZATION IS LINE SEQUENTIAL
        FILE STATUS IS WS-FS-AUD.
    SELECT ARQ-JRN ASSIGN TO WS-PATH-JRN
        ORGANIZATION IS LINE SEQUENTIAL
        FILE STATUS IS WS-FS-JRN.
    SELECT ARQ-CLI-TMP ASSIGN TO WS-PATH-CLI-TMP
        ORGANIZATION IS LINE SEQUENTIAL
        FILE STATUS IS WS-FS-TMP.
    SELECT ARQ-CTA-TMP ASSIGN TO WS-PATH-CTA-TMP
        ORGANIZATION IS LINE SEQUENTIAL
        FILE STATUS IS WS-FS-TMP.
    SELECT ARQ-TXR-TMP ASSIGN TO WS-PATH-TXR-TMP
        ORGANIZATION IS LINE SEQUENTIAL
        FILE STATUS IS WS-FS-TMP.
    SELECT ARQ-SEQ-TMP ASSIGN TO WS-PATH-SEQ-TMP
        ORGANIZATION IS LINE SEQUENTIAL
        FILE STATUS IS WS-FS-TMP.

DATA DIVISION.
FILE SECTION.
FD ARQ-CLI.     01 FD-CLI-LINE     PIC X(512).
FD ARQ-CTA.     01 FD-CTA-LINE     PIC X(512).
FD ARQ-MOV.     01 FD-MOV-LINE     PIC X(512).
FD ARQ-TXR.     01 FD-TXR-LINE     PIC X(512).
FD ARQ-SEQ.     01 FD-SEQ-LINE     PIC X(128).
FD ARQ-AUD.     01 FD-AUD-LINE     PIC X(512).
FD ARQ-JRN.     01 FD-JRN-LINE     PIC X(512).
FD ARQ-CLI-TMP. 01 FD-CLI-TMP-LINE PIC X(512).
FD ARQ-CTA-TMP. 01 FD-CTA-TMP-LINE PIC X(512).
FD ARQ-TXR-TMP. 01 FD-TXR-TMP-LINE PIC X(512).
FD ARQ-SEQ-TMP. 01 FD-SEQ-TMP-LINE PIC X(128).

WORKING-STORAGE SECTION.
COPY "copy/constantes.cpy".

01 WS-DATA-DIR        PIC X(256) VALUE SPACES.
01 WS-PATH-CLI        PIC X(300).
01 WS-PATH-CTA        PIC X(300).
01 WS-PATH-MOV        PIC X(300).
01 WS-PATH-TXR        PIC X(300).
01 WS-PATH-SEQ        PIC X(300).
01 WS-PATH-JRN        PIC X(300).
01 WS-JOURNAL-LINES   PIC 9(9) VALUE 0.
01 WS-JOURNAL-CKPT    PIC 9(9) VALUE 0.
01 WS-PATH-AUD        PIC X(300).
01 WS-PATH-TMP        PIC X(300).
01 WS-PATH-CLI-TMP    PIC X(300).
01 WS-PATH-CTA-TMP    PIC X(300).
01 WS-PATH-TXR-TMP    PIC X(300).
01 WS-PATH-SEQ-TMP    PIC X(300).

01 WS-FS-CLI          PIC X(2).
01 WS-FS-CTA          PIC X(2).
01 WS-FS-MOV          PIC X(2).
01 WS-FS-TXR          PIC X(2).
01 WS-FS-SEQ          PIC X(2).
01 WS-FS-AUD          PIC X(2).
01 WS-FS-JRN          PIC X(2).
01 WS-FS-TMP          PIC X(2).
01 WS-RENAME-RC       PIC 9(9) VALUE 0.
01 WS-RENAME-SRC      PIC X(300).
01 WS-RENAME-DST      PIC X(300).
01 WS-DEL-RC          PIC 9(9) VALUE 0.
01 WS-CFE-RC          PIC 9(9) VALUE 0.
01 WS-CFE-INFO        PIC X(16).

01 WS-LINE            PIC X(512).
01 WS-EOF             PIC X(1).
01 WS-IDX             PIC 9(7).
01 WS-I               PIC 9(7).
01 WS-FOUND           PIC X(1).
01 WS-NUM-N           PIC 9(13).
01 WS-NUM-X REDEFINES WS-NUM-N PIC X(13).
01 WS-NUM9-N          PIC 9(9).
01 WS-NUM9-X REDEFINES WS-NUM9-N PIC X(9).
01 WS-NUM6-N          PIC 9(6).
01 WS-NUM6-X REDEFINES WS-NUM6-N PIC X(6).
01 WS-NUM8-N          PIC 9(8).
01 WS-NUM8-X REDEFINES WS-NUM8-N PIC X(8).
01 WS-NUM4-N          PIC 9(4).
01 WS-NUM4-X REDEFINES WS-NUM4-N PIC X(4).

01 WS-NOW-X           PIC X(21).
01 WS-DATAHORA-FMT    PIC X(19).
01 WS-F1 PIC X(80). 01 WS-F2 PIC X(80). 01 WS-F3 PIC X(80).
01 WS-F4 PIC X(80). 01 WS-F5 PIC X(80). 01 WS-F6 PIC X(80).
01 WS-F7 PIC X(80). 01 WS-F8 PIC X(80).
01 WS-PX-I  PIC 9(4) VALUE 0.
01 WS-PX-C  PIC 9(2) VALUE 0.
01 WS-PX-P3 PIC 9(4) VALUE 0.

01 TBL-CLIENTES.
   05 CLI-COUNT       PIC 9(6) VALUE 0.
   05 CLI-ITEM OCCURS 10000 TIMES.
      COPY "copy/clientes.cpy".

01 TBL-CONTAS.
   05 CTA-COUNT       PIC 9(6) VALUE 0.
   05 CTA-ITEM OCCURS 20000 TIMES.
      COPY "copy/contas.cpy".

01 TBL-TXREG.
   05 TXR-COUNT       PIC 9(7) VALUE 0.
   05 TXR-ITEM OCCURS 500000 TIMES.
      COPY "copy/txreg.cpy".

*>--------------------------------------------------------------*
*> IDX-TXREG: indice hash do registro de idempotencia.
*> Resolve o gargalo O(n) por operacao das buscas lineares de
*> TX-ID (LB-TX-FIND e P-TX-FIND-DUP): cada transacao financeira
*> executava 2 varreduras completas de TXR-ITEM -> O(n^2) no lote.
*>
*> Propriedades que tornam o indice seguro aqui:
*> - TXR-ITEM: somente LB-TX-ADD e P-CARREGA-TXREG CRIAM posicoes;
*>   LB-TX-UPD pode alterar o DETALHE de uma posicao existente
*>   (carimbo ";ESTORNADA" do estorno de transacoes), mas nunca o
*>   TXR-ID nem a ordem das posicoes: o indice nunca precisa de
*>   remocao nem de re-encadeamento.
*> - Estado DERIVADO: nunca persistido em disco; reconstruido a
*>   cada LB-DATA-LOAD a partir de tx_registry.dat. Crash nao o
*>   corrompe: a fonte da verdade continua sendo o arquivo.
*> - Hash djb2 sobre o TX-ID (sem espacos); bucket = MOD 65536 + 1.
*> - Colisoes por encadeamento (lista ligada via IDX-NXT);
*>   insercao na cabeca do bucket (LIFO). 0 = fim da cadeia.
*> - Custo de memoria: ~5 MB (590 KB buckets + 4,5 MB elos).
*> - Busca media: O(1) (cadeia media < 8 elos mesmo com 500k TXs).
*>--------------------------------------------------------------*
01 IDX-TXREG.
   05 IDX-BKT OCCURS 65536 TIMES PIC 9(9).
   05 IDX-NXT OCCURS 500000 TIMES PIC 9(9).
01 WS-IDX-H            PIC 9(10).
01 WS-IDX-B            PIC 9(9).
01 WS-IDX-POS          PIC 9(9).
01 WS-IDX-LAST         PIC 9(9).
01 WS-IDX-J            PIC 9(5). *> ate 65536 (limpeza dos buckets)
01 WS-IDX-KEY          PIC X(24).
01 WS-IDX-LEN          PIC 9(4).

01 SEQS.
   05 SEQ-CLIENTE     PIC 9(6) VALUE 1.
   05 SEQ-CONTA       PIC 9(8) VALUE 10000001.
   05 SEQ-MOV         PIC 9(9) VALUE 1.
   05 SEQ-TX         PIC 9(4) VALUE 1.

LINKAGE SECTION.
01 LK-DIR             PIC X(256).
01 LK-RC              PIC 9(2).
01 LK-ID              PIC X(24).
01 LK-IDX             PIC 9(7).
01 LK-FOUND           PIC X(1).
01 LK-TARIFA          PIC 9(13).
01 LK-N               PIC 9(7).
01 LK-QUAL            PIC X(10).
01 LK-VAL             PIC 9(9).
01 LK-TXT             PIC X(200).
01 LK-MSG             PIC X(120).
01 LK-CLI-REC.
   COPY "copy/clientes.cpy".
01 LK-CTA-REC.
   COPY "copy/contas.cpy".
01 LK-MOV-REC.
   COPY "copy/movimentos.cpy".
01 LK-TXR-REC.
   COPY "copy/txreg.cpy".
01 LK-DATAHORA        PIC X(19).

PROCEDURE DIVISION.
    GOBACK.

*>--------------------------------------------------------------*
*> LB-DATA-INIT: define o diretorio de dados.
*>--------------------------------------------------------------*
ENTRY "LB-DATA-INIT" USING LK-DIR.
    IF FUNCTION TRIM(LK-DIR) = SPACES
        MOVE "./data" TO WS-DATA-DIR
    ELSE
        MOVE FUNCTION TRIM(LK-DIR) TO WS-DATA-DIR
    END-IF.
    STRING FUNCTION TRIM(WS-DATA-DIR) "/clientes.dat"
        DELIMITED BY SIZE INTO WS-PATH-CLI
    END-STRING.
    STRING FUNCTION TRIM(WS-DATA-DIR) "/contas.dat"
        DELIMITED BY SIZE INTO WS-PATH-CTA
    END-STRING.
    STRING FUNCTION TRIM(WS-DATA-DIR) "/movimentos.dat"
        DELIMITED BY SIZE INTO WS-PATH-MOV
    END-STRING.
    MOVE WS-PATH-MOV TO WS-PATH-JRN.
    STRING FUNCTION TRIM(WS-DATA-DIR) "/tx_registry.dat"
        DELIMITED BY SIZE INTO WS-PATH-TXR
    END-STRING.
    STRING FUNCTION TRIM(WS-DATA-DIR) "/sequencia.dat"
        DELIMITED BY SIZE INTO WS-PATH-SEQ
    END-STRING.
    STRING FUNCTION TRIM(WS-DATA-DIR) "/auditoria.log"
        DELIMITED BY SIZE INTO WS-PATH-AUD
    END-STRING.
    GOBACK.

*>--------------------------------------------------------------*
*> LB-DATA-CREATE-FILES: cria os arquivos de dados ausentes
*> (vazios). Portabilidade (D32): o lb-init criava so o diretorio;
*> os .dat nasciam de forma preguicosa no primeiro LOAD - o journal
*> via sequencia 35 -> OUTPUT -> EXTEND, que nao se recuperava no
*> Windows (FS=35 persistente). Criar aqui, sempre checando a
*> existencia antes (nunca trunca base existente), garante base
*> inicializada de forma portatil. Chamada apenas pelo lb-init,
*> apos LB-DATA-INIT.
*>--------------------------------------------------------------*
ENTRY "LB-DATA-CREATE-FILES".
    CALL "CBL_CHECK_FILE_EXIST" USING WS-PATH-CLI WS-CFE-INFO
        RETURNING WS-CFE-RC END-CALL.
    IF WS-CFE-RC = 35
        OPEN OUTPUT ARQ-CLI
        CLOSE ARQ-CLI
    END-IF.
    CALL "CBL_CHECK_FILE_EXIST" USING WS-PATH-CTA WS-CFE-INFO
        RETURNING WS-CFE-RC END-CALL.
    IF WS-CFE-RC = 35
        OPEN OUTPUT ARQ-CTA
        CLOSE ARQ-CTA
    END-IF.
    CALL "CBL_CHECK_FILE_EXIST" USING WS-PATH-MOV WS-CFE-INFO
        RETURNING WS-CFE-RC END-CALL.
    IF WS-CFE-RC = 35
        OPEN OUTPUT ARQ-MOV
        CLOSE ARQ-MOV
    END-IF.
    CALL "CBL_CHECK_FILE_EXIST" USING WS-PATH-TXR WS-CFE-INFO
        RETURNING WS-CFE-RC END-CALL.
    IF WS-CFE-RC = 35
        OPEN OUTPUT ARQ-TXR
        CLOSE ARQ-TXR
    END-IF.
    CALL "CBL_CHECK_FILE_EXIST" USING WS-PATH-SEQ WS-CFE-INFO
        RETURNING WS-CFE-RC END-CALL.
    IF WS-CFE-RC = 35
        OPEN OUTPUT ARQ-SEQ
        CLOSE ARQ-SEQ
    END-IF.
    CALL "CBL_CHECK_FILE_EXIST" USING WS-PATH-AUD WS-CFE-INFO
        RETURNING WS-CFE-RC END-CALL.
    IF WS-CFE-RC = 35
        OPEN OUTPUT ARQ-AUD
        CLOSE ARQ-AUD
    END-IF.
    GOBACK.

*>--------------------------------------------------------------*
*> LB-DATA-LOAD: carrega masters para a memoria; abre journal e
*> auditoria em modo append. Arquivos inexistentes = base vazia.
*>--------------------------------------------------------------*
ENTRY "LB-DATA-LOAD" USING LK-RC.
    MOVE 0 TO LK-RC.
    PERFORM P-CARREGA-CLIENTES.
    PERFORM P-CARREGA-CONTAS.
    PERFORM P-CARREGA-TXREG.
    PERFORM P-CARREGA-SEQ.
    PERFORM P-CONTA-JOURNAL.
    PERFORM P-ABRE-APPEND-MOV.
    PERFORM P-ABRE-APPEND-AUD.
    GOBACK.

*>--------------------------------------------------------------*
*> LB-DATA-SAVE: persiste masters com rewrite atomico
*> (tmp + rename) e fecha os arquivos de append.
*>--------------------------------------------------------------*
ENTRY "LB-DATA-SAVE" USING LK-RC.
    MOVE 0 TO LK-RC.
    PERFORM P-SALVA-CLIENTES.
    PERFORM P-SALVA-CONTAS.
    PERFORM P-SALVA-TXREG.
    PERFORM P-SALVA-SEQ.
    CLOSE ARQ-MOV.
    CLOSE ARQ-AUD.
    GOBACK.

*>--------------------------------------------------------------*
*> LB-DATA-REOPEN: reabre journal e auditoria em append apos um
*> SAVE (que os fecha). Permite salvar no meio da sessao.
*>--------------------------------------------------------------*
ENTRY "LB-DATA-REOPEN".
    PERFORM P-ABRE-APPEND-MOV.
    PERFORM P-ABRE-APPEND-AUD.
    GOBACK.

*>--------------------------------------------------------------*
*> LB-DATA-CHECK: integridade do journal contra o ultimo
*> checkpoint gravado em sequencia.dat.
*> RC=0 ok; RC=1 journal alem do checkpoint (queda antes do SAVE?);
*> RC=2 journal menor que o checkpoint (possivel perda de dados).
*>--------------------------------------------------------------*
ENTRY "LB-DATA-CHECK" USING LK-RC LK-MSG.
    MOVE 0 TO LK-RC.
    MOVE SPACES TO LK-MSG.
    IF WS-JOURNAL-LINES > WS-JOURNAL-CKPT
        MOVE 1 TO LK-RC
        STRING "Journal alem do checkpoint ("
            DELIMITED BY SIZE
            WS-JOURNAL-LINES DELIMITED BY SIZE
            " > " DELIMITED BY SIZE
            WS-JOURNAL-CKPT DELIMITED BY SIZE
            "): possivel queda antes do SAVE." DELIMITED BY SIZE
            INTO LK-MSG
        END-STRING
    ELSE
        IF WS-JOURNAL-LINES < WS-JOURNAL-CKPT
            MOVE 2 TO LK-RC
            MOVE "Journal menor que o checkpoint: possivel perda de dados."
                TO LK-MSG
        END-IF
    END-IF.
    GOBACK.

*>--------------------------------------------------------------*
*> Buscas e leituras
*>--------------------------------------------------------------*
ENTRY "LB-CLI-FIND" USING LK-ID LK-CLI-REC LK-FOUND.
    MOVE "N" TO LK-FOUND.
    PERFORM VARYING WS-IDX FROM 1 BY 1 UNTIL WS-IDX > CLI-COUNT
        IF CLI-ID OF CLI-ITEM(WS-IDX) = FUNCTION TRIM(LK-ID)
            MOVE CORRESPONDING CLI-ITEM(WS-IDX) TO LK-CLI-REC
            MOVE "S" TO LK-FOUND
            EXIT PERFORM
        END-IF
    END-PERFORM.
    GOBACK.

ENTRY "LB-CTA-FIND" USING LK-ID LK-CTA-REC LK-FOUND.
    MOVE "N" TO LK-FOUND.
    PERFORM VARYING WS-IDX FROM 1 BY 1 UNTIL WS-IDX > CTA-COUNT
        IF CTA-NUMERO OF CTA-ITEM(WS-IDX) = FUNCTION TRIM(LK-ID)
            MOVE CORRESPONDING CTA-ITEM(WS-IDX) TO LK-CTA-REC
            MOVE "S" TO LK-FOUND
            EXIT PERFORM
        END-IF
    END-PERFORM.
    GOBACK.

ENTRY "LB-TX-FIND" USING LK-ID LK-TXR-REC LK-FOUND.
    MOVE "N" TO LK-FOUND.
    MOVE FUNCTION TRIM(LK-ID) TO WS-IDX-KEY.
    PERFORM P-IDX-LOOKUP.
    IF WS-FOUND = "S"
        MOVE CORRESPONDING TXR-ITEM(WS-IDX-POS) TO LK-TXR-REC
        MOVE "S" TO LK-FOUND
    END-IF.
    GOBACK.

ENTRY "LB-CLI-GET" USING LK-IDX LK-CLI-REC LK-FOUND.
    IF LK-IDX >= 1 AND LK-IDX <= CLI-COUNT
        MOVE CORRESPONDING CLI-ITEM(LK-IDX) TO LK-CLI-REC
        MOVE "S" TO LK-FOUND
    ELSE
        MOVE "N" TO LK-FOUND
    END-IF.
    GOBACK.

ENTRY "LB-CTA-GET" USING LK-IDX LK-CTA-REC LK-FOUND.
    IF LK-IDX >= 1 AND LK-IDX <= CTA-COUNT
        MOVE CORRESPONDING CTA-ITEM(LK-IDX) TO LK-CTA-REC
        MOVE "S" TO LK-FOUND
    ELSE
        MOVE "N" TO LK-FOUND
    END-IF.
    GOBACK.

ENTRY "LB-CLI-COUNT" USING LK-N.
    MOVE CLI-COUNT TO LK-N.
    GOBACK.

ENTRY "LB-CTA-COUNT" USING LK-N.
    MOVE CTA-COUNT TO LK-N.
    GOBACK.

*>--------------------------------------------------------------*
*> Inclusoes e atualizacoes
*>--------------------------------------------------------------*
ENTRY "LB-CLI-ADD" USING LK-CLI-REC LK-RC.
    MOVE 0 TO LK-RC.
    PERFORM P-CLI-FIND-DUP.
    IF WS-FOUND = "S"
        MOVE 8 TO LK-RC
        GOBACK
    END-IF.
    IF CLI-COUNT >= 10000
        MOVE 10 TO LK-RC
        GOBACK
    END-IF.
    ADD 1 TO CLI-COUNT.
    MOVE CORRESPONDING LK-CLI-REC TO CLI-ITEM(CLI-COUNT).
    GOBACK.

ENTRY "LB-CLI-UPD" USING LK-CLI-REC LK-RC.
    MOVE 0 TO LK-RC.
    PERFORM P-CLI-FIND-DUP.
    IF WS-FOUND = "N"
        MOVE 7 TO LK-RC
        GOBACK
    END-IF.
    MOVE CORRESPONDING LK-CLI-REC TO CLI-ITEM(WS-IDX).
    GOBACK.

ENTRY "LB-CTA-ADD" USING LK-CTA-REC LK-RC.
    MOVE 0 TO LK-RC.
    PERFORM P-CTA-FIND-DUP.
    IF WS-FOUND = "S"
        MOVE 8 TO LK-RC
        GOBACK
    END-IF.
    IF CTA-COUNT >= 20000
        MOVE 10 TO LK-RC
        GOBACK
    END-IF.
    ADD 1 TO CTA-COUNT.
    MOVE CORRESPONDING LK-CTA-REC TO CTA-ITEM(CTA-COUNT).
    GOBACK.

ENTRY "LB-CTA-UPD" USING LK-CTA-REC LK-RC.
    MOVE 0 TO LK-RC.
    PERFORM P-CTA-FIND-DUP.
    IF WS-FOUND = "N"
        MOVE 1 TO LK-RC
        GOBACK
    END-IF.
    MOVE CORRESPONDING LK-CTA-REC TO CTA-ITEM(WS-IDX).
    GOBACK.

ENTRY "LB-TX-ADD" USING LK-TXR-REC LK-RC.
    MOVE 0 TO LK-RC.
    PERFORM P-TX-FIND-DUP.
    IF WS-FOUND = "S"
        MOVE 6 TO LK-RC
        GOBACK
    END-IF.
    IF TXR-COUNT >= MAX-TXREG
        MOVE 10 TO LK-RC
        GOBACK
    END-IF.
    ADD 1 TO TXR-COUNT.
    MOVE CORRESPONDING LK-TXR-REC TO TXR-ITEM(TXR-COUNT).
    MOVE TXR-ID OF TXR-ITEM(TXR-COUNT) TO WS-IDX-KEY.
    MOVE TXR-COUNT TO WS-IDX-POS.
    PERFORM P-IDX-INSERT.
    GOBACK.

*>--------------------------------------------------------------*
*> LB-TX-UPD: atualiza o DETALHE de um TX-ID ja registrado,
*> localizado via indice hash (O(1) medio). Uso: o estorno
*> carimba ";ESTORNADA" no DETALHE da transacao original.
*> A chave (TX-ID) nunca muda: o indice continua valido.
*> LK-RC = 0 ok; 1 = TX-ID nao encontrado.
*>--------------------------------------------------------------*
ENTRY "LB-TX-UPD" USING LK-TXR-REC LK-RC.
    MOVE 0 TO LK-RC.
    PERFORM P-TX-FIND-DUP.
    IF WS-FOUND = "N"
        MOVE 1 TO LK-RC
        GOBACK
    END-IF.
    MOVE TXR-DETALHE OF LK-TXR-REC
        TO TXR-DETALHE OF TXR-ITEM(WS-IDX-POS).
    GOBACK.

*>--------------------------------------------------------------*
*> LB-SEQ-NEXT: retorna o proximo valor do contador QUAL e incrementa.
*> QUAL = "CLIENTE" | "CONTA" | "MOV" | "TX"
*>--------------------------------------------------------------*
ENTRY "LB-SEQ-NEXT" USING LK-QUAL LK-VAL.
    EVALUATE FUNCTION TRIM(LK-QUAL)
        WHEN "CLIENTE"
            MOVE SEQ-CLIENTE TO LK-VAL
            ADD 1 TO SEQ-CLIENTE
        WHEN "CONTA"
            MOVE SEQ-CONTA TO LK-VAL
            ADD 1 TO SEQ-CONTA
        WHEN "MOV"
            MOVE SEQ-MOV TO LK-VAL
            ADD 1 TO SEQ-MOV
        WHEN "TX"
            MOVE SEQ-TX TO LK-VAL
            ADD 1 TO SEQ-TX
            IF SEQ-TX > 9999 MOVE 1 TO SEQ-TX END-IF
        WHEN OTHER
            MOVE 0 TO LK-VAL
    END-EVALUATE.
    GOBACK.

*>--------------------------------------------------------------*
*> LB-MOV-ADD: grava um movimento no journal (append).
*>--------------------------------------------------------------*
ENTRY "LB-MOV-ADD" USING LK-MOV-REC.
    MOVE MOV-SEQ OF LK-MOV-REC TO WS-NUM9-N.
    MOVE MOV-VALOR OF LK-MOV-REC TO WS-NUM-N.
    MOVE SPACES TO WS-LINE
    STRING
        WS-NUM9-X DELIMITED BY SIZE
        ";" DELIMITED BY SIZE
        FUNCTION TRIM(MOV-DATAHORA OF LK-MOV-REC) DELIMITED BY SIZE
        ";" DELIMITED BY SIZE
        FUNCTION TRIM(MOV-TIPO OF LK-MOV-REC) DELIMITED BY SIZE
        ";" DELIMITED BY SIZE
        FUNCTION TRIM(MOV-CONTA OF LK-MOV-REC) DELIMITED BY SIZE
        ";" DELIMITED BY SIZE
        FUNCTION TRIM(MOV-CONTA-DEST OF LK-MOV-REC) DELIMITED BY SIZE
        ";" DELIMITED BY SIZE
        WS-NUM-X DELIMITED BY SIZE
        ";" DELIMITED BY SIZE
        FUNCTION TRIM(MOV-TX-ID OF LK-MOV-REC) DELIMITED BY SIZE
        ";" DELIMITED BY SIZE
        FUNCTION TRIM(MOV-DESCRICAO OF LK-MOV-REC) DELIMITED BY SIZE
        INTO WS-LINE
    END-STRING.
    MOVE FUNCTION TRIM(WS-LINE) TO FD-MOV-LINE.
    WRITE FD-MOV-LINE.
    ADD 1 TO WS-JOURNAL-LINES.
    GOBACK.

*>--------------------------------------------------------------*
*> LB-MOV-FIND-TX: localiza no journal (movimentos.dat) os
*> movimentos de um TX-ID. Uso: compatibilidade com transacoes
*> criadas antes do DETALHE enriquecido (sem "valor=") — o
*> journal e a fonte da verdade para tipo/contas/valor/tarifa.
*> Varredura sequencial O(n) em disco; usada apenas no caminho
*> legado, nunca no fluxo quente.
*> LK-MOV-REC: primeiro movimento nao-TARIFA (tipo/conta/dest/valor).
*> LK-TARIFA: soma dos movimentos TARIFA do mesmo TX-ID.
*> LK-FOUND: "S" se achou ao menos o movimento principal.
*>--------------------------------------------------------------*
ENTRY "LB-MOV-FIND-TX" USING LK-ID LK-MOV-REC LK-TARIFA LK-FOUND.
    MOVE "N" TO LK-FOUND.
    MOVE 0 TO LK-TARIFA.
    MOVE SPACES TO LK-MOV-REC.
*> O arquivo fica aberto em EXTEND durante a sessao (P-ABRE-
*> APPEND-MOV): fecha, le em INPUT e reabre em EXTEND para os
*> appends seguintes continuarem funcionando.
    CLOSE ARQ-MOV.
    OPEN INPUT ARQ-MOV.
    IF WS-FS-MOV NOT = "00"
        PERFORM P-ABRE-APPEND-MOV
        GOBACK
    END-IF.
    MOVE "N" TO WS-EOF.
    PERFORM UNTIL WS-EOF = "S"
        READ ARQ-MOV
            AT END MOVE "S" TO WS-EOF
            NOT AT END
                MOVE FD-MOV-LINE TO WS-LINE
                UNSTRING WS-LINE DELIMITED BY ";"
                    INTO WS-F1 WS-F2 WS-F3 WS-F4
                         WS-F5 WS-F6 WS-F7 WS-F8
                END-UNSTRING
                IF FUNCTION TRIM(WS-F7) = FUNCTION TRIM(LK-ID)
                    IF FUNCTION TRIM(WS-F3) = "TARIFA"
                        COMPUTE LK-TARIFA = LK-TARIFA
                            + FUNCTION NUMVAL(FUNCTION TRIM(WS-F6))
                    ELSE
                        IF LK-FOUND = "N"
                            MOVE "S" TO LK-FOUND
                            MOVE FUNCTION TRIM(WS-F3)
                                TO MOV-TIPO OF LK-MOV-REC
                            MOVE FUNCTION TRIM(WS-F4)
                                TO MOV-CONTA OF LK-MOV-REC
                            MOVE FUNCTION TRIM(WS-F5)
                                TO MOV-CONTA-DEST OF LK-MOV-REC
                            COMPUTE MOV-VALOR OF LK-MOV-REC =
                                FUNCTION NUMVAL(FUNCTION TRIM(WS-F6))
                        END-IF
                    END-IF
                END-IF
        END-READ
    END-PERFORM.
    CLOSE ARQ-MOV.
    PERFORM P-ABRE-APPEND-MOV.
    GOBACK.

*>--------------------------------------------------------------*
*> LB-AUDIT: grava linha de auditoria (append, com timestamp).
*>--------------------------------------------------------------*
ENTRY "LB-AUDIT" USING LK-TXT.
    PERFORM P-AGORA.
    MOVE SPACES TO WS-LINE
    STRING WS-DATAHORA-FMT DELIMITED BY SIZE
        " | " DELIMITED BY SIZE
        FUNCTION TRIM(LK-TXT) DELIMITED BY SIZE
        INTO WS-LINE
    END-STRING.
    MOVE FUNCTION TRIM(WS-LINE) TO FD-AUD-LINE.
    WRITE FD-AUD-LINE.
    GOBACK.

*>--------------------------------------------------------------*
*> LB-NOW: devolve timestamp "AAAA-MM-DD HH:MM:SS".
*>--------------------------------------------------------------*
ENTRY "LB-NOW" USING LK-DATAHORA.
    PERFORM P-AGORA.
    MOVE WS-DATAHORA-FMT TO LK-DATAHORA.
    GOBACK.

*>--------------------------------------------------------------*
*> LB-TX-GEN: gera TX-ID unico: TX-AAAAMMDDHHMMSS-NNNN
*>--------------------------------------------------------------*
ENTRY "LB-TX-GEN" USING LK-ID.
    MOVE FUNCTION CURRENT-DATE TO WS-NOW-X.
    MOVE SEQ-TX TO WS-NUM4-N.
    ADD 1 TO SEQ-TX.
    IF SEQ-TX > 9999 MOVE 1 TO SEQ-TX END-IF.
    STRING "TX-" DELIMITED BY SIZE
           WS-NOW-X(1:14) DELIMITED BY SIZE
           "-" DELIMITED BY SIZE
           WS-NUM4-X DELIMITED BY SIZE
        INTO LK-ID
    END-STRING.
    GOBACK.

*>==============================================================*
*> Rotinas internas
*>==============================================================*
P-AGORA.
    MOVE FUNCTION CURRENT-DATE TO WS-NOW-X.
    STRING WS-NOW-X(1:4) DELIMITED BY SIZE
        "-" DELIMITED BY SIZE
        WS-NOW-X(5:2) DELIMITED BY SIZE
        "-" DELIMITED BY SIZE
        WS-NOW-X(7:2) DELIMITED BY SIZE
        " " DELIMITED BY SIZE
        WS-NOW-X(9:2) DELIMITED BY SIZE
        ":" DELIMITED BY SIZE
        WS-NOW-X(11:2) DELIMITED BY SIZE
        ":" DELIMITED BY SIZE
        WS-NOW-X(13:2) DELIMITED BY SIZE
        INTO WS-DATAHORA-FMT
    END-STRING.
    .

P-CLI-FIND-DUP.
    MOVE "N" TO WS-FOUND.
    PERFORM VARYING WS-IDX FROM 1 BY 1 UNTIL WS-IDX > CLI-COUNT
        IF CLI-ID OF CLI-ITEM(WS-IDX)
                = FUNCTION TRIM(CLI-ID OF LK-CLI-REC)
            MOVE "S" TO WS-FOUND
            EXIT PERFORM
        END-IF
    END-PERFORM.
    .

P-CTA-FIND-DUP.
    MOVE "N" TO WS-FOUND.
    PERFORM VARYING WS-IDX FROM 1 BY 1 UNTIL WS-IDX > CTA-COUNT
        IF CTA-NUMERO OF CTA-ITEM(WS-IDX)
                = FUNCTION TRIM(CTA-NUMERO OF LK-CTA-REC)
            MOVE "S" TO WS-FOUND
            EXIT PERFORM
        END-IF
    END-PERFORM.
    .

P-TX-FIND-DUP.
    MOVE TXR-ID OF LK-TXR-REC TO WS-IDX-KEY.
    PERFORM P-IDX-LOOKUP.
    .

*>--------------------------------------------------------------*
*> Indice hash de TX-ID (paragrafos internos de lb-dados).
*> Invariante: apos qualquer escrita em TXR-ITEM, o TX-ID da
*> posicao escrita esta encadeado no bucket do seu hash; apos
*> P-CARREGA-TXREG, as posicoes 1..TXR-COUNT estao encadeadas.
*> LB-TX-UPD altera apenas o DETALHE (nunca o TX-ID): nao afeta
*> o indice. Nenhum outro programa precisa conhecer o indice:
*> LB-TX-FIND e LB-TX-ADD mantem as assinaturas e a semantica
*> originais.
*>--------------------------------------------------------------*
P-IDX-HASH.
    MOVE 5381 TO WS-IDX-H.
    MOVE FUNCTION LENGTH(FUNCTION TRIM(WS-IDX-KEY)) TO WS-IDX-LEN.
    PERFORM VARYING WS-IDX-J FROM 1 BY 1
            UNTIL WS-IDX-J > WS-IDX-LEN
        COMPUTE WS-IDX-H = FUNCTION MOD(
            WS-IDX-H * 33 + FUNCTION ORD(WS-IDX-KEY(WS-IDX-J:1)),
            4294967296)
    END-PERFORM.
    COMPUTE WS-IDX-B = FUNCTION MOD(WS-IDX-H, 65536) + 1.
    .

P-IDX-INSERT.
    PERFORM P-IDX-HASH.
    MOVE IDX-BKT(WS-IDX-B) TO IDX-NXT(WS-IDX-POS).
    MOVE WS-IDX-POS TO IDX-BKT(WS-IDX-B).
    .

P-IDX-LOOKUP.
*> Percorre a cadeia inteira guardando o ULTIMO match (= menor
*> posicao, insercao mais antiga): replica exatamente a semantica
*> da busca linear antiga, que retornava a primeira ocorrencia.
    MOVE "N" TO WS-FOUND.
    MOVE 0 TO WS-IDX-POS.
    MOVE 0 TO WS-IDX-LAST.
    PERFORM P-IDX-HASH.
    MOVE IDX-BKT(WS-IDX-B) TO WS-IDX-POS.
    PERFORM UNTIL WS-IDX-POS = 0
        IF TXR-ID OF TXR-ITEM(WS-IDX-POS)
                = FUNCTION TRIM(WS-IDX-KEY)
            MOVE "S" TO WS-FOUND
            MOVE WS-IDX-POS TO WS-IDX-LAST
        END-IF
        MOVE IDX-NXT(WS-IDX-POS) TO WS-IDX-POS
    END-PERFORM.
    MOVE WS-IDX-LAST TO WS-IDX-POS.
    .

P-IDX-LIMPA.
    PERFORM VARYING WS-IDX-J FROM 1 BY 1 UNTIL WS-IDX-J > 65536
        MOVE 0 TO IDX-BKT(WS-IDX-J)
    END-PERFORM.
    .

P-IDX-ENCadeia.
    PERFORM VARYING WS-IDX-POS FROM 1 BY 1
            UNTIL WS-IDX-POS > TXR-COUNT
        MOVE TXR-ID OF TXR-ITEM(WS-IDX-POS) TO WS-IDX-KEY
        PERFORM P-IDX-INSERT
    END-PERFORM.
    .

P-CARREGA-CLIENTES.
    MOVE 0 TO CLI-COUNT.
    OPEN INPUT ARQ-CLI.
    IF WS-FS-CLI = "35"
        EXIT PARAGRAPH
    END-IF.
    IF WS-FS-CLI NOT = "00"
        DISPLAY "ERRO ao abrir clientes.dat (FS=" WS-FS-CLI ")"
        STOP RUN RETURNING 1
    END-IF.
    MOVE "N" TO WS-EOF.
    PERFORM UNTIL WS-EOF = "S"
        READ ARQ-CLI
            AT END MOVE "S" TO WS-EOF
            NOT AT END
                ADD 1 TO CLI-COUNT
                MOVE FD-CLI-LINE TO WS-LINE
                PERFORM P-PARSE-CLIENTE
        END-READ
    END-PERFORM.
    CLOSE ARQ-CLI.
    .

P-PARSE-CLIENTE.
    UNSTRING WS-LINE DELIMITED BY ";"
        INTO WS-F1 WS-F2 WS-F3 WS-F4 WS-F5 WS-F6.
    MOVE FUNCTION TRIM(WS-F1) TO CLI-ID OF CLI-ITEM(CLI-COUNT).
    MOVE FUNCTION TRIM(WS-F2) TO CLI-NOME OF CLI-ITEM(CLI-COUNT).
    MOVE FUNCTION TRIM(WS-F3) TO CLI-CPF OF CLI-ITEM(CLI-COUNT).
    MOVE FUNCTION TRIM(WS-F4) TO CLI-EMAIL OF CLI-ITEM(CLI-COUNT).
    MOVE FUNCTION TRIM(WS-F5) TO CLI-DATA-CAD OF CLI-ITEM(CLI-COUNT).
    MOVE FUNCTION TRIM(WS-F6) TO CLI-STATUS OF CLI-ITEM(CLI-COUNT).
    .

P-CARREGA-CONTAS.
    MOVE 0 TO CTA-COUNT.
    OPEN INPUT ARQ-CTA.
    IF WS-FS-CTA = "35"
        EXIT PARAGRAPH
    END-IF.
    IF WS-FS-CTA NOT = "00"
        DISPLAY "ERRO ao abrir contas.dat (FS=" WS-FS-CTA ")"
        STOP RUN RETURNING 1
    END-IF.
    MOVE "N" TO WS-EOF.
    PERFORM UNTIL WS-EOF = "S"
        READ ARQ-CTA
            AT END MOVE "S" TO WS-EOF
            NOT AT END
                ADD 1 TO CTA-COUNT
                MOVE FD-CTA-LINE TO WS-LINE
                PERFORM P-PARSE-CONTA
        END-READ
    END-PERFORM.
    CLOSE ARQ-CTA.
    .

P-PARSE-CONTA.
    UNSTRING WS-LINE DELIMITED BY ";"
        INTO WS-F1 WS-F2 WS-F3 WS-F4 WS-F5 WS-F6.
    MOVE FUNCTION TRIM(WS-F1) TO CTA-NUMERO OF CTA-ITEM(CTA-COUNT).
    MOVE FUNCTION TRIM(WS-F2) TO CTA-CLIENTE-ID OF CTA-ITEM(CTA-COUNT).
    MOVE FUNCTION TRIM(WS-F3) TO CTA-TIPO OF CTA-ITEM(CTA-COUNT).
    MOVE FUNCTION TRIM(WS-F4) TO CTA-STATUS OF CTA-ITEM(CTA-COUNT).
    COMPUTE WS-NUM-N = FUNCTION NUMVAL(WS-F5).
    MOVE WS-NUM-N TO CTA-SALDO OF CTA-ITEM(CTA-COUNT).
    MOVE FUNCTION TRIM(WS-F6) TO CTA-DATA-ABERT OF CTA-ITEM(CTA-COUNT).
    .

P-CARREGA-TXREG.
    MOVE 0 TO TXR-COUNT.
    PERFORM P-IDX-LIMPA.
    OPEN INPUT ARQ-TXR.
    IF WS-FS-TXR = "35"
        EXIT PARAGRAPH
    END-IF.
    IF WS-FS-TXR NOT = "00"
        DISPLAY "ERRO ao abrir tx_registry.dat (FS=" WS-FS-TXR ")"
        STOP RUN RETURNING 1
    END-IF.
    MOVE "N" TO WS-EOF.
    PERFORM UNTIL WS-EOF = "S"
        READ ARQ-TXR
            AT END MOVE "S" TO WS-EOF
            NOT AT END
                ADD 1 TO TXR-COUNT
                MOVE FD-TXR-LINE TO WS-LINE
                PERFORM P-PARSE-TXREG
        END-READ
    END-PERFORM.
    CLOSE ARQ-TXR.
    PERFORM P-IDX-ENCadeia.
    .

P-PARSE-TXREG.
*> O DETALHE (4o campo) pode conter ";" (ex.: o carimbo
*> ";ESTORNADA" do estorno). Os 3 primeiros campos nunca
*> contem ";": o DETALHE e tudo o que vem apos o 3o ";".
*> Um UNSTRING simples em 4 campos descartaria o resto.
    MOVE 0 TO WS-PX-C.
    MOVE 0 TO WS-PX-P3.
    PERFORM VARYING WS-PX-I FROM 1 BY 1
            UNTIL WS-PX-I > 512 OR WS-PX-C = 3
        IF WS-LINE(WS-PX-I:1) = ";"
            ADD 1 TO WS-PX-C
            IF WS-PX-C = 3
                MOVE WS-PX-I TO WS-PX-P3
            END-IF
        END-IF
    END-PERFORM.
    IF WS-PX-P3 = 0
        MOVE SPACES TO TXR-DETALHE OF TXR-ITEM(TXR-COUNT)
        EXIT PARAGRAPH
    END-IF.
    UNSTRING WS-LINE(1:WS-PX-P3 - 1) DELIMITED BY ";"
        INTO WS-F1 WS-F2 WS-F3
    END-UNSTRING.
    MOVE WS-LINE(WS-PX-P3 + 1:) TO WS-F4.
    MOVE FUNCTION TRIM(WS-F1) TO TXR-ID OF TXR-ITEM(TXR-COUNT).
    MOVE FUNCTION TRIM(WS-F2) TO TXR-DATAHORA OF TXR-ITEM(TXR-COUNT).
    MOVE FUNCTION TRIM(WS-F3) TO TXR-RESULTADO OF TXR-ITEM(TXR-COUNT).
    MOVE FUNCTION TRIM(WS-F4) TO TXR-DETALHE OF TXR-ITEM(TXR-COUNT).
    .

P-CARREGA-SEQ.
    OPEN INPUT ARQ-SEQ.
    IF WS-FS-SEQ = "35"
        EXIT PARAGRAPH
    END-IF.
    IF WS-FS-SEQ NOT = "00"
        DISPLAY "ERRO ao abrir sequencia.dat (FS=" WS-FS-SEQ ")"
        STOP RUN RETURNING 1
    END-IF.
    READ ARQ-SEQ
        AT END CONTINUE
        NOT AT END
            MOVE FD-SEQ-LINE TO WS-LINE
            UNSTRING WS-LINE DELIMITED BY ";"
                INTO WS-F1 WS-F2 WS-F3 WS-F4 WS-F5
            END-UNSTRING
            COMPUTE SEQ-CLIENTE = FUNCTION NUMVAL(WS-F1)
            COMPUTE SEQ-CONTA   = FUNCTION NUMVAL(WS-F2)
            COMPUTE SEQ-MOV     = FUNCTION NUMVAL(WS-F3)
            COMPUTE SEQ-TX     = FUNCTION NUMVAL(WS-F4)
            COMPUTE WS-JOURNAL-CKPT = FUNCTION NUMVAL(WS-F5)
    END-READ.
    CLOSE ARQ-SEQ.
    .

P-CONTA-JOURNAL.
    *> conta as linhas do journal para o checkpoint de integridade
    MOVE 0 TO WS-JOURNAL-LINES.
    OPEN INPUT ARQ-JRN.
    IF WS-FS-JRN = "35"
        EXIT PARAGRAPH
    END-IF.
    IF WS-FS-JRN NOT = "00"
        DISPLAY "ERRO ao ler movimentos.dat (FS=" WS-FS-JRN ")"
        STOP RUN RETURNING 1
    END-IF.
    MOVE "N" TO WS-EOF.
    PERFORM UNTIL WS-EOF = "S"
        READ ARQ-JRN
            AT END MOVE "S" TO WS-EOF
            NOT AT END ADD 1 TO WS-JOURNAL-LINES
        END-READ
    END-PERFORM.
    CLOSE ARQ-JRN.
    .

P-ABRE-APPEND-MOV.
    OPEN EXTEND ARQ-MOV.
    IF WS-FS-MOV = "35"
*>      Portabilidade (D32): arquivo inexistente -> OPEN OUTPUT cria
*>      vazio e segue aberto para escrita sequencial, o que equivale
*>      ao EXTEND num arquivo novo (LINE SEQUENTIAL). Substitui a
*>      sequencia CLOSE/OUTPUT/CLOSE/EXTEND, cuja etapa final nao se
*>      recuperava no Windows (FS=35 persistente).
        OPEN OUTPUT ARQ-MOV
    END-IF.
    IF WS-FS-MOV NOT = "00"
        DISPLAY "ERRO ao abrir movimentos.dat (FS=" WS-FS-MOV ")"
        STOP RUN RETURNING 1
    END-IF.
    .

P-ABRE-APPEND-AUD.
    OPEN EXTEND ARQ-AUD.
    IF WS-FS-AUD = "35"
*>      Portabilidade (D32): idem P-ABRE-APPEND-MOV.
        OPEN OUTPUT ARQ-AUD
    END-IF.
    IF WS-FS-AUD NOT = "00"
        DISPLAY "ERRO ao abrir auditoria.log (FS=" WS-FS-AUD ")"
        STOP RUN RETURNING 1
    END-IF.
    .

*>--------------------------------------------------------------*
*> P-RENAME-ATOMICO: renomeia WS-RENAME-SRC -> WS-RENAME-DST.
*> Portabilidade (D30): CBL_RENAME_FILE usa rename() do C; no
*> Linux rename() substitui o destino atomicamente, mas no
*> Windows (UCRT) rename() FALHA se o destino existir. O
*> caminho feliz (rename direto) e tentado primeiro, ficando
*> inalterado no Linux; so se ele falhar, remove-se o destino
*> e tenta-se de novo (trecho exercido apenas no Windows).
*>--------------------------------------------------------------*
P-RENAME-ATOMICO.
    CALL "CBL_RENAME_FILE" USING WS-RENAME-SRC WS-RENAME-DST
        RETURNING WS-RENAME-RC
    END-CALL.
    IF WS-RENAME-RC NOT = 0
        CALL "CBL_DELETE_FILE" USING WS-RENAME-DST
            RETURNING WS-DEL-RC
        END-CALL
        IF WS-DEL-RC = 0
            CALL "CBL_RENAME_FILE" USING WS-RENAME-SRC WS-RENAME-DST
                RETURNING WS-RENAME-RC
            END-CALL
        END-IF
    END-IF.
    .

P-SALVA-CLIENTES.
    STRING FUNCTION TRIM(WS-PATH-CLI) DELIMITED BY SIZE
        ".tmp" DELIMITED BY SIZE
        INTO WS-PATH-TMP
    END-STRING.
    MOVE WS-PATH-TMP TO WS-PATH-CLI-TMP.
    OPEN OUTPUT ARQ-CLI-TMP.
    PERFORM VARYING WS-I FROM 1 BY 1 UNTIL WS-I > CLI-COUNT
        MOVE SPACES TO WS-LINE
        STRING
            FUNCTION TRIM(CLI-ID OF CLI-ITEM(WS-I)) DELIMITED BY SIZE
            ";" DELIMITED BY SIZE
            FUNCTION TRIM(CLI-NOME OF CLI-ITEM(WS-I)) DELIMITED BY SIZE
            ";" DELIMITED BY SIZE
            FUNCTION TRIM(CLI-CPF OF CLI-ITEM(WS-I)) DELIMITED BY SIZE
            ";" DELIMITED BY SIZE
            FUNCTION TRIM(CLI-EMAIL OF CLI-ITEM(WS-I)) DELIMITED BY SIZE
            ";" DELIMITED BY SIZE
            FUNCTION TRIM(CLI-DATA-CAD OF CLI-ITEM(WS-I))
            DELIMITED BY SIZE
            ";" DELIMITED BY SIZE
            FUNCTION TRIM(CLI-STATUS OF CLI-ITEM(WS-I)) DELIMITED BY SIZE
            INTO WS-LINE
        END-STRING
        MOVE FUNCTION TRIM(WS-LINE) TO FD-CLI-TMP-LINE
        WRITE FD-CLI-TMP-LINE
    END-PERFORM.
    CLOSE ARQ-CLI-TMP.
    MOVE WS-PATH-TMP TO WS-RENAME-SRC.
    MOVE WS-PATH-CLI TO WS-RENAME-DST.
    PERFORM P-RENAME-ATOMICO.
    IF WS-RENAME-RC NOT = 0
        DISPLAY "ERRO ao persistir clientes.dat"
        STOP RUN RETURNING 1
    END-IF.
    .

P-SALVA-CONTAS.
    STRING FUNCTION TRIM(WS-PATH-CTA) DELIMITED BY SIZE
        ".tmp" DELIMITED BY SIZE
        INTO WS-PATH-TMP
    END-STRING.
    MOVE WS-PATH-TMP TO WS-PATH-CTA-TMP.
    OPEN OUTPUT ARQ-CTA-TMP.
    PERFORM VARYING WS-I FROM 1 BY 1 UNTIL WS-I > CTA-COUNT
        MOVE CTA-SALDO OF CTA-ITEM(WS-I) TO WS-NUM-N
        MOVE SPACES TO WS-LINE
        STRING
            FUNCTION TRIM(CTA-NUMERO OF CTA-ITEM(WS-I))
            DELIMITED BY SIZE
            ";" DELIMITED BY SIZE
            FUNCTION TRIM(CTA-CLIENTE-ID OF CTA-ITEM(WS-I))
            DELIMITED BY SIZE
            ";" DELIMITED BY SIZE
            FUNCTION TRIM(CTA-TIPO OF CTA-ITEM(WS-I))
            DELIMITED BY SIZE
            ";" DELIMITED BY SIZE
            FUNCTION TRIM(CTA-STATUS OF CTA-ITEM(WS-I))
            DELIMITED BY SIZE
            ";" DELIMITED BY SIZE
            WS-NUM-X DELIMITED BY SIZE
            ";" DELIMITED BY SIZE
            FUNCTION TRIM(CTA-DATA-ABERT OF CTA-ITEM(WS-I))
            DELIMITED BY SIZE
            INTO WS-LINE
        END-STRING
        MOVE FUNCTION TRIM(WS-LINE) TO FD-CTA-TMP-LINE
        WRITE FD-CTA-TMP-LINE
    END-PERFORM.
    CLOSE ARQ-CTA-TMP.
    MOVE WS-PATH-TMP TO WS-RENAME-SRC.
    MOVE WS-PATH-CTA TO WS-RENAME-DST.
    PERFORM P-RENAME-ATOMICO.
    IF WS-RENAME-RC NOT = 0
        DISPLAY "ERRO ao persistir contas.dat"
        STOP RUN RETURNING 1
    END-IF.
    .

P-SALVA-TXREG.
    STRING FUNCTION TRIM(WS-PATH-TXR) DELIMITED BY SIZE
        ".tmp" DELIMITED BY SIZE
        INTO WS-PATH-TMP
    END-STRING.
    MOVE WS-PATH-TMP TO WS-PATH-TXR-TMP.
    OPEN OUTPUT ARQ-TXR-TMP.
    PERFORM VARYING WS-I FROM 1 BY 1 UNTIL WS-I > TXR-COUNT
        MOVE SPACES TO WS-LINE
        STRING
            FUNCTION TRIM(TXR-ID OF TXR-ITEM(WS-I))
            DELIMITED BY SIZE
            ";" DELIMITED BY SIZE
            FUNCTION TRIM(TXR-DATAHORA OF TXR-ITEM(WS-I))
            DELIMITED BY SIZE
            ";" DELIMITED BY SIZE
            FUNCTION TRIM(TXR-RESULTADO OF TXR-ITEM(WS-I))
            DELIMITED BY SIZE
            ";" DELIMITED BY SIZE
            FUNCTION TRIM(TXR-DETALHE OF TXR-ITEM(WS-I))
            DELIMITED BY SIZE
            INTO WS-LINE
        END-STRING
        MOVE FUNCTION TRIM(WS-LINE) TO FD-TXR-TMP-LINE
        WRITE FD-TXR-TMP-LINE
    END-PERFORM.
    CLOSE ARQ-TXR-TMP.
    MOVE WS-PATH-TMP TO WS-RENAME-SRC.
    MOVE WS-PATH-TXR TO WS-RENAME-DST.
    PERFORM P-RENAME-ATOMICO.
    IF WS-RENAME-RC NOT = 0
        DISPLAY "ERRO ao persistir tx_registry.dat"
        STOP RUN RETURNING 1
    END-IF.
    .

P-SALVA-SEQ.
    STRING FUNCTION TRIM(WS-PATH-SEQ) DELIMITED BY SIZE
        ".tmp" DELIMITED BY SIZE
        INTO WS-PATH-TMP
    END-STRING.
    MOVE WS-PATH-TMP TO WS-PATH-SEQ-TMP.
    OPEN OUTPUT ARQ-SEQ-TMP.
    MOVE SEQ-CLIENTE TO WS-NUM6-N.
    MOVE SEQ-CONTA TO WS-NUM8-N.
    MOVE SEQ-MOV TO WS-NUM9-N.
    MOVE SEQ-TX TO WS-NUM4-N.
    MOVE WS-JOURNAL-LINES TO WS-JOURNAL-CKPT.
    MOVE WS-JOURNAL-CKPT TO WS-NUM-N.
    MOVE SPACES TO WS-LINE
    STRING WS-NUM6-X DELIMITED BY SIZE
        ";" DELIMITED BY SIZE
        WS-NUM8-X DELIMITED BY SIZE
        ";" DELIMITED BY SIZE
        WS-NUM9-X DELIMITED BY SIZE
        ";" DELIMITED BY SIZE
        WS-NUM4-X DELIMITED BY SIZE
        ";" DELIMITED BY SIZE
        WS-NUM-X DELIMITED BY SIZE
        INTO WS-LINE
    END-STRING.
    MOVE FUNCTION TRIM(WS-LINE) TO FD-SEQ-TMP-LINE.
    WRITE FD-SEQ-TMP-LINE.
    CLOSE ARQ-SEQ-TMP.
    MOVE WS-PATH-TMP TO WS-RENAME-SRC.
    MOVE WS-PATH-SEQ TO WS-RENAME-DST.
    PERFORM P-RENAME-ATOMICO.
    IF WS-RENAME-RC NOT = 0
        DISPLAY "ERRO ao persistir sequencia.dat"
        STOP RUN RETURNING 1
    END-IF.
    .

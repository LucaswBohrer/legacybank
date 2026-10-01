>>SOURCE FORMAT IS FREE
*>==============================================================*
*> LEGACYBANK - LB-LOTE
*> Processador de lote: le um arquivo de operacoes, executa cada
*> uma via o nucleo financeiro (LB-FINANC) e gera relatorio.
*>
*> Formato do arquivo de lote (uma operacao por linha, ";" separa):
*>   DEPOSITO;TXID;CONTA;VALOR
*>   SAQUE;TXID;CONTA;VALOR
*>   TRANSFERENCIA;TXID;ORIGEM;DESTINO;VALOR
*> VALOR usa ponto decimal (ex.: 150.75). Linhas em branco e linhas
*> iniciadas por "#" sao ignoradas.
*>
*> Uso: lb-lote [dir-dados] arquivo-lote
*>==============================================================*
IDENTIFICATION DIVISION.
PROGRAM-ID. LB-LOTE.

ENVIRONMENT DIVISION.
INPUT-OUTPUT SECTION.
FILE-CONTROL.
    SELECT ARQ-LOTE ASSIGN TO WS-LOTE-PATH
        ORGANIZATION IS LINE SEQUENTIAL
        FILE STATUS IS WS-FS.
    SELECT ARQ-REL ASSIGN TO WS-REL-PATH
        ORGANIZATION IS LINE SEQUENTIAL
        FILE STATUS IS WS-FS.

DATA DIVISION.
FILE SECTION.
FD ARQ-LOTE. 01 FD-LOTE-LINE PIC X(512).
FD ARQ-REL.  01 FD-REL-LINE  PIC X(256).

WORKING-STORAGE SECTION.
01 WS-ARGC            PIC 9(4).
01 WS-ARG             PIC X(256).
01 WS-DIR             PIC X(256) VALUE "./data".
01 WS-LOTE-PATH       PIC X(256).
01 WS-REL-PATH        PIC X(300).
01 WS-FS              PIC X(2).
01 WS-EOF             PIC X(1).
01 WS-LINE            PIC X(512).
01 WS-LINE-NUM        PIC 9(7).
01 WS-OP              PIC X(13).
01 WS-F2 PIC X(40). 01 WS-F3 PIC X(40). 01 WS-F4 PIC X(40).
01 WS-F5 PIC X(40).
01 WS-VAL-REAL        PIC 9(11)V99.
01 WS-VAL-CENT        PIC 9(13).
01 WS-PARSE-OK        PIC X(1).
01 WS-RC              PIC 9(2).
01 WS-MSG             PIC X(120).
01 WS-TXID            PIC X(24).
01 WS-CONTA           PIC X(8).
01 WS-DEST            PIC X(8).
01 WS-N-OK            PIC 9(7).
01 WS-N-REJ           PIC 9(7).
01 WS-N-DUP           PIC 9(7).
01 WS-N-INV           PIC 9(7).
01 WS-DATAHORA        PIC X(19).
01 WS-TS-FILE         PIC X(19).
01 WS-I               PIC 9(3).
01 WS-SEP-N           PIC 9(3).
01 WS-OPS-SINCE-SAVE  PIC 9(7).

PROCEDURE DIVISION.
MAIN-PARA.
    PERFORM P-ARGS.
    CALL "LB-DATA-INIT" USING WS-DIR.
    CALL "LB-DATA-LOAD" USING WS-RC.
    CALL "LB-DATA-CHECK" USING WS-RC WS-MSG.
    IF WS-RC NOT = 0
        DISPLAY FUNCTION TRIM(WS-MSG)
    END-IF.
    MOVE 0 TO WS-N-OK WS-N-REJ WS-N-DUP WS-N-INV WS-LINE-NUM
        WS-OPS-SINCE-SAVE.
    OPEN INPUT ARQ-LOTE.
    IF WS-FS NOT = "00"
        DISPLAY "Nao foi possivel abrir o arquivo de lote: "
            FUNCTION TRIM(WS-LOTE-PATH)
        STOP RUN RETURNING 2
    END-IF.
    MOVE "N" TO WS-EOF.
    PERFORM UNTIL WS-EOF = "S"
        READ ARQ-LOTE
            AT END MOVE "S" TO WS-EOF
            NOT AT END
                ADD 1 TO WS-LINE-NUM
                MOVE FD-LOTE-LINE TO WS-LINE
                PERFORM P-PROCESSA-LINHA
                ADD 1 TO WS-OPS-SINCE-SAVE
                IF WS-OPS-SINCE-SAVE >= 1000
                    CALL "LB-DATA-SAVE" USING WS-RC
                    CALL "LB-DATA-REOPEN"
                    MOVE 0 TO WS-OPS-SINCE-SAVE
                END-IF
        END-READ
    END-PERFORM.
    CLOSE ARQ-LOTE.
    CALL "LB-DATA-SAVE" USING WS-RC.
    PERFORM P-RELATORIO.
    DISPLAY " ".
    DISPLAY "Lote concluido: " WS-N-OK " ok, "
        WS-N-REJ " rejeitadas, " WS-N-DUP " duplicadas, "
        WS-N-INV " invalidas.".
    DISPLAY "Relatorio: " FUNCTION TRIM(WS-REL-PATH).
    STOP RUN RETURNING 0.

P-ARGS.
    ACCEPT WS-ARGC FROM ARGUMENT-NUMBER.
    IF WS-ARGC = 0
        DISPLAY "Uso: lb-lote [dir-dados] arquivo-lote"
        STOP RUN RETURNING 2
    END-IF.
    IF WS-ARGC = 1
        ACCEPT WS-LOTE-PATH FROM ARGUMENT-VALUE
    ELSE
        ACCEPT WS-DIR FROM ARGUMENT-VALUE
        ACCEPT WS-LOTE-PATH FROM ARGUMENT-VALUE
    END-IF.
    .

P-PROCESSA-LINHA.
    IF FUNCTION TRIM(WS-LINE) = SPACES
        EXIT PARAGRAPH
    END-IF.
    IF WS-LINE(1:1) = "#"
        EXIT PARAGRAPH
    END-IF.
    MOVE SPACES TO WS-OP WS-F2 WS-F3 WS-F4 WS-F5.
    UNSTRING WS-LINE DELIMITED BY ";"
        INTO WS-OP WS-F2 WS-F3 WS-F4 WS-F5
    END-UNSTRING.
    MOVE FUNCTION UPPER-CASE(FUNCTION TRIM(WS-OP)) TO WS-OP.
    EVALUATE WS-OP
        WHEN "DEPOSITO"
            MOVE FUNCTION TRIM(WS-F2) TO WS-TXID
            MOVE FUNCTION TRIM(WS-F3) TO WS-CONTA
            PERFORM P-PARSE-VALOR-F4
            IF WS-PARSE-OK = "S"
                CALL "FIN-DEPOSITO" USING WS-TXID WS-CONTA
                    WS-VAL-CENT WS-RC WS-MSG
                PERFORM P-CONTABILIZA
            ELSE
                ADD 1 TO WS-N-INV
            END-IF
        WHEN "SAQUE"
            MOVE FUNCTION TRIM(WS-F2) TO WS-TXID
            MOVE FUNCTION TRIM(WS-F3) TO WS-CONTA
            PERFORM P-PARSE-VALOR-F4
            IF WS-PARSE-OK = "S"
                CALL "FIN-SAQUE" USING WS-TXID WS-CONTA
                    WS-VAL-CENT WS-RC WS-MSG
                PERFORM P-CONTABILIZA
            ELSE
                ADD 1 TO WS-N-INV
            END-IF
        WHEN "TRANSFERENCIA"
            MOVE FUNCTION TRIM(WS-F2) TO WS-TXID
            MOVE FUNCTION TRIM(WS-F3) TO WS-CONTA
            MOVE FUNCTION TRIM(WS-F4) TO WS-DEST
            MOVE FUNCTION TRIM(WS-F5) TO WS-ARG
            PERFORM P-PARSE-VALOR-ARG
            IF WS-PARSE-OK = "S"
                CALL "FIN-TRANSFERENCIA" USING WS-TXID WS-CONTA
                    WS-DEST WS-VAL-CENT WS-RC WS-MSG
                PERFORM P-CONTABILIZA
            ELSE
                ADD 1 TO WS-N-INV
            END-IF
        WHEN OTHER
            ADD 1 TO WS-N-INV
            DISPLAY "Linha " WS-LINE-NUM ": operacao desconhecida."
    END-EVALUATE.
    .

P-PARSE-VALOR-F4.
    MOVE FUNCTION TRIM(WS-F4) TO WS-ARG.
    PERFORM P-PARSE-VALOR-ARG.
    .

P-PARSE-VALOR-ARG.
    *> converte texto "150.75"/"150,75" em centavos; valor negativo
    *> eh normalizado para zero para o nucleo rejeitar com RC=5
    MOVE "N" TO WS-PARSE-OK.
    MOVE 0 TO WS-VAL-CENT.
    IF FUNCTION TRIM(WS-ARG) = SPACES
        DISPLAY "Linha " WS-LINE-NUM ": valor ausente."
        EXIT PARAGRAPH
    END-IF.
    MOVE 0 TO WS-SEP-N.
    PERFORM VARYING WS-I FROM 1 BY 1
            UNTIL WS-I > FUNCTION LENGTH(FUNCTION TRIM(WS-ARG))
        IF WS-ARG(WS-I:1) >= "0" AND WS-ARG(WS-I:1) <= "9"
            CONTINUE
        ELSE
            IF WS-ARG(WS-I:1) = "." OR WS-ARG(WS-I:1) = ","
                ADD 1 TO WS-SEP-N
                IF WS-SEP-N > 1
                    DISPLAY "Linha " WS-LINE-NUM
                        ": valor invalido."
                    EXIT PARAGRAPH
                END-IF
            ELSE
                IF WS-ARG(WS-I:1) = "-" AND WS-I = 1
                    MOVE "S" TO WS-PARSE-OK
                    EXIT PARAGRAPH
                END-IF
                DISPLAY "Linha " WS-LINE-NUM
                    ": valor invalido."
                EXIT PARAGRAPH
            END-IF
        END-IF
    END-PERFORM.
    PERFORM VARYING WS-I FROM 1 BY 1
            UNTIL WS-I > FUNCTION LENGTH(FUNCTION TRIM(WS-ARG))
        IF WS-ARG(WS-I:1) = ","
            MOVE "." TO WS-ARG(WS-I:1)
        END-IF
    END-PERFORM.
    COMPUTE WS-VAL-REAL =
        FUNCTION NUMVAL(FUNCTION TRIM(WS-ARG)).
    COMPUTE WS-VAL-CENT =
        FUNCTION INTEGER(WS-VAL-REAL * 100 + 0.5).
    MOVE "S" TO WS-PARSE-OK.
    .

P-CONTABILIZA.
    EVALUATE WS-RC
        WHEN 0
            ADD 1 TO WS-N-OK
        WHEN 6
            ADD 1 TO WS-N-DUP
        WHEN OTHER
            ADD 1 TO WS-N-REJ
            DISPLAY "Linha " WS-LINE-NUM ": rejeitada ("
                FUNCTION TRIM(WS-MSG) ")"
    END-EVALUATE.
    .

P-RELATORIO.
    CALL "LB-NOW" USING WS-DATAHORA.
    MOVE WS-DATAHORA TO WS-TS-FILE.
    PERFORM VARYING WS-I FROM 1 BY 1 UNTIL WS-I > 19
        IF WS-TS-FILE(WS-I:1) = " " OR WS-TS-FILE(WS-I:1) = ":"
                OR WS-TS-FILE(WS-I:1) = "-"
            MOVE "_" TO WS-TS-FILE(WS-I:1)
        END-IF
    END-PERFORM.
    MOVE SPACES TO WS-REL-PATH
    STRING FUNCTION TRIM(WS-DIR) DELIMITED BY SIZE
        "/relatorio_lote_" DELIMITED BY SIZE
        WS-TS-FILE(1:19) DELIMITED BY SIZE
        ".txt" DELIMITED BY SIZE
        INTO WS-REL-PATH
    END-STRING.
    OPEN OUTPUT ARQ-REL.
    MOVE SPACES TO FD-REL-LINE.
    STRING "RELATORIO DE LOTE LEGACYBANK - " DELIMITED BY SIZE
        WS-DATAHORA DELIMITED BY SIZE
        INTO FD-REL-LINE
    END-STRING.
    WRITE FD-REL-LINE.
    MOVE SPACES TO FD-REL-LINE.
    STRING "Arquivo: " DELIMITED BY SIZE
        FUNCTION TRIM(WS-LOTE-PATH) DELIMITED BY SIZE
        INTO FD-REL-LINE
    END-STRING.
    WRITE FD-REL-LINE.
    MOVE SPACES TO FD-REL-LINE.
    STRING "Processadas com sucesso: " DELIMITED BY SIZE
        WS-N-OK DELIMITED BY SIZE
        INTO FD-REL-LINE
    END-STRING.
    WRITE FD-REL-LINE.
    MOVE SPACES TO FD-REL-LINE.
    STRING "Rejeitadas: " DELIMITED BY SIZE
        WS-N-REJ DELIMITED BY SIZE
        INTO FD-REL-LINE
    END-STRING.
    WRITE FD-REL-LINE.
    MOVE SPACES TO FD-REL-LINE.
    STRING "Duplicadas (ignoradas): " DELIMITED BY SIZE
        WS-N-DUP DELIMITED BY SIZE
        INTO FD-REL-LINE
    END-STRING.
    WRITE FD-REL-LINE.
    MOVE SPACES TO FD-REL-LINE.
    STRING "Invalidas: " DELIMITED BY SIZE
        WS-N-INV DELIMITED BY SIZE
        INTO FD-REL-LINE
    END-STRING.
    WRITE FD-REL-LINE.
    CLOSE ARQ-REL.
    .

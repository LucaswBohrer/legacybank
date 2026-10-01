>>SOURCE FORMAT IS FREE
*>==============================================================*
*> LEGACYBANK - LB-CONSULTA
*> Consultas somente-leitura: extrato, saldo, listagens e relatorio.
*> Le os arquivos diretamente (nao usa o estado em memoria do
*> LB-DADOS), portanto pode ser chamado a qualquer momento.
*>==============================================================*
IDENTIFICATION DIVISION.
PROGRAM-ID. LB-CONSULTA.

ENVIRONMENT DIVISION.
INPUT-OUTPUT SECTION.
FILE-CONTROL.
    SELECT ARQ-MOV ASSIGN TO WS-PATH-MOV
        ORGANIZATION IS LINE SEQUENTIAL
        FILE STATUS IS WS-FS.
    SELECT ARQ-CTA ASSIGN TO WS-PATH-CTA
        ORGANIZATION IS LINE SEQUENTIAL
        FILE STATUS IS WS-FS.
    SELECT ARQ-CLI ASSIGN TO WS-PATH-CLI
        ORGANIZATION IS LINE SEQUENTIAL
        FILE STATUS IS WS-FS.

DATA DIVISION.
FILE SECTION.
FD ARQ-MOV. 01 FD-MOV-LINE PIC X(512).
FD ARQ-CTA. 01 FD-CTA-LINE PIC X(512).
FD ARQ-CLI. 01 FD-CLI-LINE PIC X(512).

WORKING-STORAGE SECTION.
01 WS-DIR             PIC X(256).
01 WS-PATH-MOV        PIC X(300).
01 WS-PATH-CTA        PIC X(300).
01 WS-PATH-CLI        PIC X(300).
01 WS-FS              PIC X(2).
01 WS-LINE            PIC X(512).
01 WS-EOF             PIC X(1).
01 WS-F1 PIC X(80). 01 WS-F2 PIC X(80). 01 WS-F3 PIC X(80).
01 WS-F4 PIC X(80). 01 WS-F5 PIC X(80). 01 WS-F6 PIC X(80).
01 WS-F7 PIC X(80). 01 WS-F8 PIC X(80).
01 WS-NUM-N           PIC 9(13).
01 WS-CENTAVOS        PIC S9(13).
01 WS-CENT-U          PIC 9(13).
01 WS-SALDO-ATUAL     PIC 9(13).
01 WS-SOMA-MOV        PIC S9(13).
01 WS-SALDO-ABERT     PIC S9(13).
01 WS-CORR            PIC S9(13).
01 WS-FOUND           PIC X(1).
01 WS-TIPO            PIC X(13).
01 WS-CONTA           PIC X(8).
01 WS-CONTA-DEST      PIC X(8).
01 WS-QTD             PIC 9(7).
01 WS-QTD-CLI         PIC 9(7).
01 WS-QTD-CTA         PIC 9(7).
01 WS-QTD-A           PIC 9(7).
01 WS-QTD-B           PIC 9(7).
01 WS-QTD-E           PIC 9(7).
01 WS-SOMA-SALDOS     PIC 9(15).
01 WS-N-DEP           PIC 9(7).
01 WS-N-SAQ           PIC 9(7).
01 WS-N-TRA           PIC 9(7).
01 WS-N-TAR           PIC 9(7).
01 WS-N-EST           PIC 9(7).
01 WS-V-DEP           PIC 9(13).
01 WS-V-SAQ           PIC 9(13).
01 WS-V-TRA           PIC 9(13).
01 WS-V-TAR           PIC 9(13).
01 WS-V-EST           PIC 9(13).
*> formatacao de valor pt-BR ("1.234,56")
01 WS-REAIS           PIC 9(11).
01 WS-CENT            PIC 99.
01 WS-REAIS-EDT       PIC ZZZZZZZZZZ9.
01 WS-REAIS-TXT       PIC X(12).
01 WS-VLR-FMT         PIC X(20).
01 WS-TMP-TXT         PIC X(20).
01 WS-I               PIC 9(3).
01 WS-J               PIC 9(3).
01 WS-LEN             PIC 9(3).

01 WS-CLI-REC.
   COPY "copy/clientes.cpy".
01 WS-CTA-REC.
   COPY "copy/contas.cpy".

LINKAGE SECTION.
01 LK-DIR             PIC X(256).
01 LK-CONTA           PIC X(8).
01 LK-SALDO-OUT       PIC 9(13).
01 LK-RC              PIC 9(2).
01 LK-FMT-VALOR       PIC S9(13).
01 LK-FMT-TXT         PIC X(40).

PROCEDURE DIVISION.
    GOBACK.

*>--------------------------------------------------------------*
*> CONS-EXTRATO: imprime o extrato da conta com saldo corrido.
*>--------------------------------------------------------------*
ENTRY "CONS-EXTRATO" USING LK-DIR LK-CONTA.
    PERFORM P-DEFINE-DIR.
    PERFORM P-BUSCA-SALDO-ATUAL.
    IF WS-FOUND = "N"
        DISPLAY "Conta inexistente."
        GOBACK
    END-IF.
    *> Passada 1: soma assinada dos movimentos -> saldo de abertura
    MOVE 0 TO WS-SOMA-MOV.
    PERFORM P-ABRE-MOV-INPUT.
    IF WS-FS = "35"
        MOVE 0 TO WS-SOMA-MOV
    ELSE
        MOVE "N" TO WS-EOF
        PERFORM UNTIL WS-EOF = "S"
            READ ARQ-MOV
                AT END MOVE "S" TO WS-EOF
                NOT AT END
                    MOVE FD-MOV-LINE TO WS-LINE
                    PERFORM P-PARSE-MOV
                    PERFORM P-SOMA-SE-DA-CONTA
            END-READ
        END-PERFORM
        CLOSE ARQ-MOV
    END-IF.
    COMPUTE WS-SALDO-ABERT = WS-SALDO-ATUAL - WS-SOMA-MOV.
    DISPLAY " ".
    DISPLAY "================ EXTRATO ================".
    DISPLAY "Conta: " FUNCTION TRIM(LK-CONTA).
    MOVE WS-SALDO-ABERT TO WS-CENTAVOS.
    PERFORM P-FORMATA-SINAL.
    DISPLAY "Saldo anterior: R$ " FUNCTION TRIM(WS-VLR-FMT).
    DISPLAY "------------------------------------------".
    *> Passada 2: lista movimentos com saldo corrido
    MOVE WS-SALDO-ABERT TO WS-CORR.
    PERFORM P-ABRE-MOV-INPUT.
    IF WS-FS NOT = "35"
        MOVE "N" TO WS-EOF
        PERFORM UNTIL WS-EOF = "S"
            READ ARQ-MOV
                AT END MOVE "S" TO WS-EOF
                NOT AT END
                    MOVE FD-MOV-LINE TO WS-LINE
                    PERFORM P-PARSE-MOV
                    PERFORM P-EXIBE-SE-DA-CONTA
            END-READ
        END-PERFORM
        CLOSE ARQ-MOV
    END-IF.
    DISPLAY "------------------------------------------".
    MOVE WS-SALDO-ATUAL TO WS-CENTAVOS.
    PERFORM P-FORMATA-SINAL.
    DISPLAY "Saldo atual:    R$ " FUNCTION TRIM(WS-VLR-FMT).
    DISPLAY "==========================================".
    GOBACK.

*>--------------------------------------------------------------*
*> CONS-SALDO: devolve o saldo em centavos (LK-SALDO-OUT).
*>--------------------------------------------------------------*
ENTRY "CONS-SALDO" USING LK-DIR LK-CONTA LK-SALDO-OUT LK-RC.
    PERFORM P-DEFINE-DIR.
    PERFORM P-BUSCA-SALDO-ATUAL.
    IF WS-FOUND = "N"
        MOVE 1 TO LK-RC
    ELSE
        MOVE 0 TO LK-RC
        MOVE WS-SALDO-ATUAL TO LK-SALDO-OUT
    END-IF.
    GOBACK.

*>--------------------------------------------------------------*
*> CONS-LISTA-CLIENTES / CONS-LISTA-CONTAS
*>--------------------------------------------------------------*
ENTRY "CONS-LISTA-CLIENTES" USING LK-DIR.
    PERFORM P-DEFINE-DIR.
    MOVE SPACES TO WS-PATH-CLI
    STRING FUNCTION TRIM(WS-DIR) DELIMITED BY SIZE
        "/clientes.dat" DELIMITED BY SIZE
        INTO WS-PATH-CLI
    END-STRING.
    OPEN INPUT ARQ-CLI.
    IF WS-FS = "35"
        DISPLAY "Nenhum cliente cadastrado."
        GOBACK
    END-IF.
    DISPLAY " ".
    DISPLAY "ID       NOME                                            CPF".
    DISPLAY "------------------------------------------------------------".
    MOVE "N" TO WS-EOF.
    PERFORM UNTIL WS-EOF = "S"
        READ ARQ-CLI
            AT END MOVE "S" TO WS-EOF
            NOT AT END
                MOVE FD-CLI-LINE TO WS-LINE
                UNSTRING WS-LINE DELIMITED BY ";"
                    INTO WS-F1 WS-F2 WS-F3 WS-F4 WS-F5 WS-F6
                END-UNSTRING
                DISPLAY FUNCTION TRIM(WS-F1) " "
                    WS-F2(1:45) " " FUNCTION TRIM(WS-F3)
        END-READ
    END-PERFORM.
    CLOSE ARQ-CLI.
    GOBACK.

ENTRY "CONS-LISTA-CONTAS" USING LK-DIR.
    PERFORM P-DEFINE-DIR.
    MOVE SPACES TO WS-PATH-CTA
    STRING FUNCTION TRIM(WS-DIR) DELIMITED BY SIZE
        "/contas.dat" DELIMITED BY SIZE
        INTO WS-PATH-CTA
    END-STRING.
    OPEN INPUT ARQ-CTA.
    IF WS-FS = "35"
        DISPLAY "Nenhuma conta aberta."
        GOBACK
    END-IF.
    DISPLAY " ".
    DISPLAY "CONTA     CLIENTE  TIPO ST SALDO".
    DISPLAY "----------------------------------------".
    MOVE "N" TO WS-EOF.
    PERFORM UNTIL WS-EOF = "S"
        READ ARQ-CTA
            AT END MOVE "S" TO WS-EOF
            NOT AT END
                MOVE FD-CTA-LINE TO WS-LINE
                UNSTRING WS-LINE DELIMITED BY ";"
                    INTO WS-F1 WS-F2 WS-F3 WS-F4 WS-F5 WS-F6
                END-UNSTRING
                COMPUTE WS-NUM-N = FUNCTION NUMVAL(WS-F5)
                MOVE WS-NUM-N TO WS-CENTAVOS
                PERFORM P-FORMATA-SINAL
                DISPLAY FUNCTION TRIM(WS-F1) "  "
                    FUNCTION TRIM(WS-F2) "  "
                    FUNCTION TRIM(WS-F3) "  "
                    FUNCTION TRIM(WS-F4) "  R$ "
                    FUNCTION TRIM(WS-VLR-FMT)
        END-READ
    END-PERFORM.
    CLOSE ARQ-CTA.
    GOBACK.

*>--------------------------------------------------------------*
*> CONS-FORMATA-VALOR: formata centavos (com sinal) no padrao
*> pt-BR ("1.234,56" / "-12,50") em texto de ate 40 posicoes.
*>--------------------------------------------------------------*
ENTRY "CONS-FORMATA-VALOR" USING LK-FMT-VALOR LK-FMT-TXT.
    MOVE LK-FMT-VALOR TO WS-CENTAVOS.
    PERFORM P-FORMATA-SINAL.
    MOVE WS-VLR-FMT TO LK-FMT-TXT.
    GOBACK.

*>--------------------------------------------------------------*
*> CONS-RELATORIO: totais do sistema.
*>--------------------------------------------------------------*
ENTRY "CONS-RELATORIO" USING LK-DIR.
    PERFORM P-DEFINE-DIR.
    MOVE 0 TO WS-QTD-CLI WS-QTD-CTA WS-QTD-A WS-QTD-B WS-QTD-E
        WS-SOMA-SALDOS WS-N-DEP WS-N-SAQ WS-N-TRA WS-N-TAR
        WS-N-EST WS-V-DEP WS-V-SAQ WS-V-TRA WS-V-TAR WS-V-EST.
    MOVE SPACES TO WS-PATH-CLI
    STRING FUNCTION TRIM(WS-DIR) DELIMITED BY SIZE
        "/clientes.dat" DELIMITED BY SIZE INTO WS-PATH-CLI
    END-STRING.
    OPEN INPUT ARQ-CLI.
    IF WS-FS NOT = "35"
        MOVE "N" TO WS-EOF
        PERFORM UNTIL WS-EOF = "S"
            READ ARQ-CLI AT END MOVE "S" TO WS-EOF
                NOT AT END ADD 1 TO WS-QTD-CLI
            END-READ
        END-PERFORM
        CLOSE ARQ-CLI
    END-IF.
    MOVE SPACES TO WS-PATH-CTA
    STRING FUNCTION TRIM(WS-DIR) DELIMITED BY SIZE
        "/contas.dat" DELIMITED BY SIZE INTO WS-PATH-CTA
    END-STRING.
    OPEN INPUT ARQ-CTA.
    IF WS-FS NOT = "35"
        MOVE "N" TO WS-EOF
        PERFORM UNTIL WS-EOF = "S"
            READ ARQ-CTA
                AT END MOVE "S" TO WS-EOF
                NOT AT END
                    MOVE FD-CTA-LINE TO WS-LINE
                    UNSTRING WS-LINE DELIMITED BY ";"
                        INTO WS-F1 WS-F2 WS-F3 WS-F4 WS-F5 WS-F6
                    END-UNSTRING
                    ADD 1 TO WS-QTD-CTA
                    EVALUATE FUNCTION TRIM(WS-F4)
                        WHEN "A" ADD 1 TO WS-QTD-A
                        WHEN "B" ADD 1 TO WS-QTD-B
                        WHEN "E" ADD 1 TO WS-QTD-E
                    END-EVALUATE
                    COMPUTE WS-NUM-N = FUNCTION NUMVAL(WS-F5)
                    ADD WS-NUM-N TO WS-SOMA-SALDOS
            END-READ
        END-PERFORM
        CLOSE ARQ-CTA
    END-IF.
    PERFORM P-ABRE-MOV-INPUT.
    IF WS-FS NOT = "35"
        MOVE "N" TO WS-EOF
        PERFORM UNTIL WS-EOF = "S"
            READ ARQ-MOV
                AT END MOVE "S" TO WS-EOF
                NOT AT END
                    MOVE FD-MOV-LINE TO WS-LINE
                    PERFORM P-PARSE-MOV
                    COMPUTE WS-NUM-N = FUNCTION NUMVAL(WS-F6)
                    EVALUATE WS-TIPO
                        WHEN "DEPOSITO"
                            ADD 1 TO WS-N-DEP
                            ADD WS-NUM-N TO WS-V-DEP
                        WHEN "SAQUE"
                            ADD 1 TO WS-N-SAQ
                            ADD WS-NUM-N TO WS-V-SAQ
                        WHEN "TRANSFERENCIA"
                            ADD 1 TO WS-N-TRA
                            ADD WS-NUM-N TO WS-V-TRA
                        WHEN "TARIFA"
                            ADD 1 TO WS-N-TAR
                            ADD WS-NUM-N TO WS-V-TAR
                        WHEN "ESTORNO"
                            ADD 1 TO WS-N-EST
                            ADD WS-NUM-N TO WS-V-EST
                    END-EVALUATE
            END-READ
        END-PERFORM
        CLOSE ARQ-MOV
    END-IF.
    DISPLAY " ".
    DISPLAY "=========== RELATORIO LEGACYBANK ===========".
    DISPLAY "Clientes cadastrados: " WS-QTD-CLI.
    DISPLAY "Contas: " WS-QTD-CTA
        " (ativas=" WS-QTD-A " bloqueadas=" WS-QTD-B
        " encerradas=" WS-QTD-E ")".
    MOVE WS-SOMA-SALDOS TO WS-CENTAVOS.
    PERFORM P-FORMATA-SINAL.
    DISPLAY "Soma dos saldos: R$ " FUNCTION TRIM(WS-VLR-FMT).
    DISPLAY "-------------------------------------------".
    DISPLAY "Depositos:      " WS-N-DEP.
    DISPLAY "Saques:         " WS-N-SAQ.
    DISPLAY "Transferencias: " WS-N-TRA.
    MOVE WS-V-TAR TO WS-CENTAVOS.
    PERFORM P-FORMATA-SINAL.
    DISPLAY "Tarifas cobradas (" WS-N-TAR "): R$ "
        FUNCTION TRIM(WS-VLR-FMT).
    MOVE WS-V-EST TO WS-CENTAVOS.
    PERFORM P-FORMATA-SINAL.
    DISPLAY "Estornos (" WS-N-EST "): R$ "
        FUNCTION TRIM(WS-VLR-FMT).
    DISPLAY "===========================================".
    GOBACK.

*>==============================================================*
*> Rotinas internas
*>==============================================================*
P-DEFINE-DIR.
    IF FUNCTION TRIM(LK-DIR) = SPACES
        MOVE "./data" TO WS-DIR
    ELSE
        MOVE FUNCTION TRIM(LK-DIR) TO WS-DIR
    END-IF.
    MOVE SPACES TO WS-PATH-MOV
    STRING FUNCTION TRIM(WS-DIR) DELIMITED BY SIZE
        "/movimentos.dat" DELIMITED BY SIZE INTO WS-PATH-MOV
    END-STRING.
    MOVE SPACES TO WS-PATH-CTA
    STRING FUNCTION TRIM(WS-DIR) DELIMITED BY SIZE
        "/contas.dat" DELIMITED BY SIZE INTO WS-PATH-CTA
    END-STRING.
    .

P-ABRE-MOV-INPUT.
    OPEN INPUT ARQ-MOV.
    .

P-BUSCA-SALDO-ATUAL.
    MOVE "N" TO WS-FOUND.
    OPEN INPUT ARQ-CTA.
    IF WS-FS = "35"
        EXIT PARAGRAPH
    END-IF.
    MOVE "N" TO WS-EOF.
    PERFORM UNTIL WS-EOF = "S"
        READ ARQ-CTA
            AT END MOVE "S" TO WS-EOF
            NOT AT END
                MOVE FD-CTA-LINE TO WS-LINE
                UNSTRING WS-LINE DELIMITED BY ";"
                    INTO WS-F1 WS-F2 WS-F3 WS-F4 WS-F5 WS-F6
                END-UNSTRING
                IF FUNCTION TRIM(WS-F1) = FUNCTION TRIM(LK-CONTA)
                    COMPUTE WS-SALDO-ATUAL = FUNCTION NUMVAL(WS-F5)
                    MOVE "S" TO WS-FOUND
                    EXIT PERFORM
                END-IF
        END-READ
    END-PERFORM.
    CLOSE ARQ-CTA.
    .

P-PARSE-MOV.
    *> SEQ;DATAHORA;TIPO;CONTA;DEST;VALOR;TXID;DESCRICAO
    UNSTRING WS-LINE DELIMITED BY ";"
        INTO WS-F1 WS-F2 WS-F3 WS-F4 WS-F5 WS-F6 WS-F7 WS-F8
    END-UNSTRING.
    MOVE FUNCTION TRIM(WS-F3) TO WS-TIPO.
    MOVE FUNCTION TRIM(WS-F4) TO WS-CONTA.
    MOVE FUNCTION TRIM(WS-F5) TO WS-CONTA-DEST.
    .

P-SOMA-SE-DA-CONTA.
    *> soma assinada dos movimentos que afetam LK-CONTA
    COMPUTE WS-NUM-N = FUNCTION NUMVAL(WS-F6).
    EVALUATE WS-TIPO
        WHEN "DEPOSITO"
            IF WS-CONTA = FUNCTION TRIM(LK-CONTA)
                ADD WS-NUM-N TO WS-SOMA-MOV
            END-IF
        WHEN "SAQUE"
            IF WS-CONTA = FUNCTION TRIM(LK-CONTA)
                SUBTRACT WS-NUM-N FROM WS-SOMA-MOV
            END-IF
        WHEN "TARIFA"
            IF WS-CONTA = FUNCTION TRIM(LK-CONTA)
                SUBTRACT WS-NUM-N FROM WS-SOMA-MOV
            END-IF
        WHEN "TRANSFERENCIA"
            IF WS-CONTA = FUNCTION TRIM(LK-CONTA)
                SUBTRACT WS-NUM-N FROM WS-SOMA-MOV
            END-IF
            IF WS-CONTA-DEST = FUNCTION TRIM(LK-CONTA)
                ADD WS-NUM-N TO WS-SOMA-MOV
            END-IF
        WHEN "ESTORNO"
            *> mesma convencao de sinal da transferencia:
            *> debita CONTA, credita CONTA_DESTINO
            IF WS-CONTA = FUNCTION TRIM(LK-CONTA)
                SUBTRACT WS-NUM-N FROM WS-SOMA-MOV
            END-IF
            IF WS-CONTA-DEST = FUNCTION TRIM(LK-CONTA)
                ADD WS-NUM-N TO WS-SOMA-MOV
            END-IF
    END-EVALUATE.
    .

P-EXIBE-SE-DA-CONTA.
    COMPUTE WS-NUM-N = FUNCTION NUMVAL(WS-F6).
    MOVE WS-NUM-N TO WS-CENTAVOS.
    PERFORM P-FORMATA-SINAL.
    EVALUATE WS-TIPO
        WHEN "DEPOSITO"
            IF WS-CONTA = FUNCTION TRIM(LK-CONTA)
                ADD WS-NUM-N TO WS-CORR
                DISPLAY WS-F2(1:16) "  DEPOSITO       +R$ "
                    FUNCTION TRIM(WS-VLR-FMT)
            END-IF
        WHEN "SAQUE"
            IF WS-CONTA = FUNCTION TRIM(LK-CONTA)
                SUBTRACT WS-NUM-N FROM WS-CORR
                DISPLAY WS-F2(1:16) "  SAQUE          -R$ "
                    FUNCTION TRIM(WS-VLR-FMT)
            END-IF
        WHEN "TARIFA"
            IF WS-CONTA = FUNCTION TRIM(LK-CONTA)
                SUBTRACT WS-NUM-N FROM WS-CORR
                DISPLAY WS-F2(1:16) "  TARIFA         -R$ "
                    FUNCTION TRIM(WS-VLR-FMT)
            END-IF
        WHEN "TRANSFERENCIA"
            IF WS-CONTA = FUNCTION TRIM(LK-CONTA)
                SUBTRACT WS-NUM-N FROM WS-CORR
                DISPLAY WS-F2(1:16) "  TRANSF SAIDA   -R$ "
                    FUNCTION TRIM(WS-VLR-FMT)
                    " -> " FUNCTION TRIM(WS-CONTA-DEST)
            END-IF
            IF WS-CONTA-DEST = FUNCTION TRIM(LK-CONTA)
                ADD WS-NUM-N TO WS-CORR
                DISPLAY WS-F2(1:16) "  TRANSF ENTRADA +R$ "
                    FUNCTION TRIM(WS-VLR-FMT)
                    " <- " FUNCTION TRIM(WS-CONTA)
            END-IF
        WHEN "ESTORNO"
            IF WS-CONTA = FUNCTION TRIM(LK-CONTA)
                SUBTRACT WS-NUM-N FROM WS-CORR
                DISPLAY WS-F2(1:16) "  ESTORNO        -R$ "
                    FUNCTION TRIM(WS-VLR-FMT)
            END-IF
            IF WS-CONTA-DEST = FUNCTION TRIM(LK-CONTA)
                ADD WS-NUM-N TO WS-CORR
                DISPLAY WS-F2(1:16) "  ESTORNO        +R$ "
                    FUNCTION TRIM(WS-VLR-FMT)
            END-IF
    END-EVALUATE.
    .

*> Formata WS-CENTAVOS (com sinal) em WS-VLR-FMT no padrao pt-BR:
*> "1.234,56" (usa P-FORMATA-VALOR sobre o valor absoluto)
P-FORMATA-SINAL.
    IF WS-CENTAVOS < 0
        COMPUTE WS-CENT-U = WS-CENTAVOS * -1
        PERFORM P-FORMATA-VALOR
        MOVE SPACES TO WS-TMP-TXT
        STRING "-" DELIMITED BY SIZE
            FUNCTION TRIM(WS-VLR-FMT) DELIMITED BY SIZE
            INTO WS-TMP-TXT
        END-STRING
        MOVE WS-TMP-TXT TO WS-VLR-FMT
    ELSE
        MOVE WS-CENTAVOS TO WS-CENT-U
        PERFORM P-FORMATA-VALOR
    END-IF.
    .

*> Formata WS-CENT-U (sem sinal) em WS-VLR-FMT ("1.234,56")
P-FORMATA-VALOR.
    DIVIDE WS-CENT-U BY 100 GIVING WS-REAIS REMAINDER WS-CENT.
    MOVE WS-REAIS TO WS-REAIS-EDT.
    MOVE FUNCTION TRIM(WS-REAIS-EDT) TO WS-REAIS-TXT.
    IF FUNCTION TRIM(WS-REAIS-TXT) = SPACES
        MOVE "0" TO WS-REAIS-TXT
    END-IF.
    PERFORM P-PONTUA-MILHAR.
    MOVE SPACES TO WS-VLR-FMT
    STRING FUNCTION TRIM(WS-TMP-TXT) DELIMITED BY SIZE
        "," DELIMITED BY SIZE
        WS-CENT DELIMITED BY SIZE
        INTO WS-VLR-FMT
    END-STRING.
    .

P-PONTUA-MILHAR.
    *> insere "." a cada 3 digitos em WS-REAIS-TXT -> WS-TMP-TXT
    MOVE FUNCTION TRIM(WS-REAIS-TXT) TO WS-REAIS-TXT.
    COMPUTE WS-LEN = FUNCTION LENGTH(FUNCTION TRIM(WS-REAIS-TXT)).
    MOVE SPACES TO WS-TMP-TXT.
    MOVE 1 TO WS-J.
    PERFORM VARYING WS-I FROM 1 BY 1 UNTIL WS-I > WS-LEN
        MOVE WS-REAIS-TXT(WS-I:1) TO WS-TMP-TXT(WS-J:1)
        ADD 1 TO WS-J
        IF FUNCTION MOD(WS-LEN - WS-I, 3) = 0 AND WS-I < WS-LEN
            MOVE "." TO WS-TMP-TXT(WS-J:1)
            ADD 1 TO WS-J
        END-IF
    END-PERFORM.
    .

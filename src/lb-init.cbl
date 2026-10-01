>>SOURCE FORMAT IS FREE
*>==============================================================*
*> LEGACYBANK - LB-INIT
*> Cria o diretorio de dados com semantica "mkdir -p", de forma
*> portavel: usa CBL_CREATE_DIR/CBL_CHECK_FILE_EXIST da libcob,
*> sem invocar shell externo (D29).
*>
*> Motivacao: CALL "SYSTEM" no Windows (MSYS2/UCRT64) cai no
*> cmd.exe (documentado no fonte da libcob), que nao entende
*> "mkdir -p" nem aspas simples -> "A sintaxe do comando esta
*> incorreta." (rc=1). Sem shell nao ha esse problema e tambem
*> nao ha risco de shell injection pelo caminho.
*>
*> Os arquivos de dados sao criados vazios pelo proprio init
*> (LB-DATA-CREATE-FILES); o LOAD tambem tolera arquivos
*> ausentes, tratando-os como base vazia.
*> Uso: lb-init [dir-dados]
*>==============================================================*
IDENTIFICATION DIVISION.
PROGRAM-ID. LB-INIT.

DATA DIVISION.
WORKING-STORAGE SECTION.
01 WS-ARGC     PIC 9(4).
01 WS-DIR      PIC X(256) VALUE "./data".
01 WS-WORK     PIC X(256).
01 WS-PREFIX   PIC X(256).
01 WS-INFO     PIC X(16).
01 WS-LEN      PIC 9(4).
01 WS-I        PIC 9(4).
01 WS-PLEN     PIC 9(4).
01 WS-RC       PIC S9(9) COMP-5.
01 WS-RC2      PIC S9(9) COMP-5.
01 WS-C        PIC X.

PROCEDURE DIVISION.
MAIN-PARA.
    ACCEPT WS-ARGC FROM ARGUMENT-NUMBER.
    IF WS-ARGC >= 1
        ACCEPT WS-DIR FROM ARGUMENT-VALUE
    END-IF.
    IF FUNCTION TRIM(WS-DIR) = SPACES
        DISPLAY "ERRO: diretorio de dados vazio."
        STOP RUN RETURNING 1
    END-IF.
    PERFORM P-NORMALIZA.
    PERFORM P-CRIA-ARVORE.
    CALL "LB-DATA-INIT" USING WS-DIR.
    CALL "LB-DATA-CREATE-FILES".
    DISPLAY "Diretorio de dados inicializado: "
        FUNCTION TRIM(WS-DIR).
    STOP RUN.

*>--------------------------------------------------------------*
*> P-NORMALIZA: copia o caminho para WS-WORK convertendo "\"
*> em "/" e ajusta WS-LEN para o comprimento efetivo (sem
*> separadores finais). Sem shell, nao ha risco de injecao.
*>--------------------------------------------------------------*
P-NORMALIZA.
    MOVE FUNCTION TRIM(WS-DIR) TO WS-WORK.
    COMPUTE WS-LEN = FUNCTION LENGTH(FUNCTION TRIM(WS-WORK)).
    PERFORM VARYING WS-I FROM 1 BY 1 UNTIL WS-I > WS-LEN
        IF WS-WORK(WS-I:1) = "\"
            MOVE "/" TO WS-WORK(WS-I:1)
        END-IF
    END-PERFORM.
    PERFORM UNTIL WS-LEN = 0
        MOVE WS-WORK(WS-LEN:1) TO WS-C
        IF WS-C NOT = "/"
            EXIT PERFORM
        END-IF
        SUBTRACT 1 FROM WS-LEN
    END-PERFORM.
    IF WS-LEN = 0
        DISPLAY "ERRO: diretorio de dados vazio."
        STOP RUN RETURNING 1
    END-IF.
    .

*>--------------------------------------------------------------*
*> P-CRIA-ARVORE: cria cada nivel do caminho (semantica mkdir
*> -p). Prefixos vazios, "." e letra de drive ("C:") sao
*> ignorados; nivel ja existente nao e erro.
*>--------------------------------------------------------------*
P-CRIA-ARVORE.
    PERFORM VARYING WS-I FROM 1 BY 1 UNTIL WS-I > WS-LEN
        IF WS-WORK(WS-I:1) = "/"
            COMPUTE WS-PLEN = WS-I - 1
            PERFORM P-CRIA-NIVEL
        END-IF
    END-PERFORM.
    MOVE WS-LEN TO WS-PLEN.
    PERFORM P-CRIA-NIVEL.
    .

P-CRIA-NIVEL.
    IF WS-PLEN <= 0
        EXIT PARAGRAPH
    END-IF.
    MOVE SPACES TO WS-PREFIX.
    MOVE WS-WORK(1:WS-PLEN) TO WS-PREFIX.
    IF FUNCTION TRIM(WS-PREFIX) = "." OR SPACES
        EXIT PARAGRAPH
    END-IF.
    IF WS-PLEN = 2 AND WS-PREFIX(2:1) = ":"
        EXIT PARAGRAPH
    END-IF.
    CALL "CBL_CREATE_DIR" USING WS-PREFIX RETURNING WS-RC
    END-CALL.
    IF WS-RC NOT = 0
        CALL "CBL_CHECK_FILE_EXIST" USING WS-PREFIX WS-INFO
            RETURNING WS-RC2
        END-CALL
        IF WS-RC2 NOT = 0
            DISPLAY "ERRO ao criar diretorio '"
                FUNCTION TRIM(WS-PREFIX) "' (rc=" WS-RC ")."
            STOP RUN RETURNING 1
        END-IF
    END-IF.
    .

>>SOURCE FORMAT IS FREE
*>==============================================================*
*> LEGACYBANK - LB-INIT
*> Cria o diretorio de dados (mkdir -p). Os arquivos de dados
*> sao criados sob demanda no primeiro uso (LOAD/SAVE).
*> Uso: lb-init [dir-dados]
*>==============================================================*
IDENTIFICATION DIVISION.
PROGRAM-ID. LB-INIT.

DATA DIVISION.
WORKING-STORAGE SECTION.
01 WS-ARGC     PIC 9(4).
01 WS-DIR      PIC X(256) VALUE "./data".
01 WS-CMD      PIC X(300).
01 WS-SYS-RC   PIC S9(9) COMP-5.
01 WS-LEN      PIC 9(4).
01 WS-I        PIC 9(4).

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
    *> Defesa contra shell injection: o caminho vai entre aspas
    *> simples; se contiver aspas simples, aborta.
    COMPUTE WS-LEN = FUNCTION LENGTH(FUNCTION TRIM(WS-DIR)).
    PERFORM VARYING WS-I FROM 1 BY 1 UNTIL WS-I > WS-LEN
        IF WS-DIR(WS-I:1) = "'"
            DISPLAY "ERRO: caminho com aspas simples nao suportado."
            STOP RUN RETURNING 1
        END-IF
    END-PERFORM.
    MOVE SPACES TO WS-CMD.
    STRING "mkdir -p '" DELIMITED BY SIZE
        FUNCTION TRIM(WS-DIR) DELIMITED BY SIZE
        "'" DELIMITED BY SIZE
        INTO WS-CMD
    END-STRING.
    CALL "SYSTEM" USING WS-CMD RETURNING WS-SYS-RC.
    IF WS-SYS-RC NOT = 0
        DISPLAY "ERRO ao criar diretorio (rc=" WS-SYS-RC ")."
        STOP RUN RETURNING 1
    END-IF.
    CALL "LB-DATA-INIT" USING WS-DIR.
    DISPLAY "Diretorio de dados inicializado: "
        FUNCTION TRIM(WS-DIR).
    STOP RUN.

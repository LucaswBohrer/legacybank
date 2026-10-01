>>SOURCE FORMAT IS FREE
*>==============================================================*
*> LEGACYBANK - LB-API
*> Driver fino de integracao (D25): despacha UMA operacao para o
*> nucleo COBOL e imprime o resultado em linhas "CHAVE: valor"
*> para consumo por maquina (a API HTTP faz o parse).
*>
*> NAO contem regra financeira: apenas converte argv, chama os
*> ENTRYs existentes e formata a saida. Toda a logica de negocio
*> continua em lb-financ / lb-dados / lb-consulta.
*>
*> Uso: lb-api <dir-dados> <op> [args...]
*>   DEPOSIT  <txid> <conta> <centavos>
*>   WITHDRAW <txid> <conta> <centavos>
*>   TRANSFER <txid> <origem> <destino> <centavos>
*>   REVERSAL <txid-novo> <txid-original>
*>   BALANCE  <conta>
*>   TX       <txid>
*>   STATEMENT <conta>
*>   ACCOUNT  <conta>
*>
*> Saida: linhas "CHAVE: valor" em stdout; sempre inclui "RC: n".
*> Exit: 0 = driver executou (ver RC na saida); 2 = uso/args;
*>       3 = falha ao carregar dados.
*>==============================================================*
IDENTIFICATION DIVISION.
PROGRAM-ID. LB-API.

ENVIRONMENT DIVISION.

DATA DIVISION.
WORKING-STORAGE SECTION.
01 WS-ARGC            PIC 9(4).
01 WS-ARG             PIC X(256).
01 WS-DIR             PIC X(256).
01 WS-OP              PIC X(13).
01 WS-P1              PIC X(256).
01 WS-P2              PIC X(256).
01 WS-P3              PIC X(256).
01 WS-P4              PIC X(256).
01 WS-TXID            PIC X(24).
01 WS-ID24            PIC X(24).
01 WS-TXORIG          PIC X(24).
01 WS-CONTA           PIC X(8).
01 WS-DEST            PIC X(8).
01 WS-CENT            PIC 9(13).
01 WS-RC              PIC 9(2).
01 WS-RC-SAVE         PIC 9(2).
01 WS-RC-CHECK        PIC 9(2).
01 WS-MSG             PIC X(120).
01 WS-MSG-CHECK       PIC X(120).
01 WS-FOUND           PIC X(1).
01 WS-SALDO-OUT       PIC 9(13).
01 WS-TXR-REC.
   COPY "copy/txreg.cpy".
01 WS-CTA-REC.
   COPY "copy/contas.cpy".

PROCEDURE DIVISION.
MAIN-PARA.
    PERFORM P-ARGS.
    MOVE FUNCTION UPPER-CASE(FUNCTION TRIM(WS-OP)) TO WS-OP.
    EVALUATE WS-OP
        WHEN "DEPOSIT"   PERFORM P-OP-FINANC
        WHEN "WITHDRAW"  PERFORM P-OP-FINANC
        WHEN "TRANSFER"  PERFORM P-OP-FINANC
        WHEN "REVERSAL"  PERFORM P-OP-FINANC
        WHEN "BALANCE"   PERFORM P-OP-BALANCE
        WHEN "TX"        PERFORM P-OP-TX
        WHEN "STATEMENT" PERFORM P-OP-STATEMENT
        WHEN "ACCOUNT"   PERFORM P-OP-ACCOUNT
        WHEN OTHER
            DISPLAY "RC: 99"
            DISPLAY "MSG: operacao desconhecida"
            STOP RUN RETURNING 2
    END-EVALUATE.
    STOP RUN RETURNING 0.

P-ARGS.
    ACCEPT WS-ARGC FROM ARGUMENT-NUMBER.
    IF WS-ARGC < 2
        DISPLAY "Uso: lb-api <dir-dados> <op> [args...]"
        STOP RUN RETURNING 2
    END-IF.
    ACCEPT WS-DIR FROM ARGUMENT-VALUE.
    ACCEPT WS-OP FROM ARGUMENT-VALUE.
    IF WS-ARGC >= 3
        ACCEPT WS-P1 FROM ARGUMENT-VALUE
    END-IF.
    IF WS-ARGC >= 4
        ACCEPT WS-P2 FROM ARGUMENT-VALUE
    END-IF.
    IF WS-ARGC >= 5
        ACCEPT WS-P3 FROM ARGUMENT-VALUE
    END-IF.
    IF WS-ARGC >= 6
        ACCEPT WS-P4 FROM ARGUMENT-VALUE
    END-IF.
    .

P-INIT-LOAD.
    CALL "LB-DATA-INIT" USING WS-DIR.
    CALL "LB-DATA-LOAD" USING WS-RC.
    IF WS-RC NOT = 0
        DISPLAY "RC: 10"
        DISPLAY "MSG: falha ao carregar dados"
        STOP RUN RETURNING 3
    END-IF.
    CALL "LB-DATA-CHECK" USING WS-RC-CHECK WS-MSG-CHECK.
    IF WS-RC-CHECK NOT = 0
        DISPLAY "RC: 11"
        DISPLAY "MSG: " FUNCTION TRIM(WS-MSG-CHECK)
        STOP RUN RETURNING 3
    END-IF.
    .

*> Operacoes financeiras: INIT, LOAD, ENTRY, SAVE, saida.
P-OP-FINANC.
    PERFORM P-INIT-LOAD.
    EVALUATE WS-OP
        WHEN "DEPOSIT"
            MOVE FUNCTION TRIM(WS-P1) TO WS-TXID
            MOVE FUNCTION TRIM(WS-P2) TO WS-CONTA
            COMPUTE WS-CENT =
                FUNCTION NUMVAL(FUNCTION TRIM(WS-P3))
            CALL "FIN-DEPOSITO" USING WS-TXID WS-CONTA
                WS-CENT WS-RC WS-MSG
        WHEN "WITHDRAW"
            MOVE FUNCTION TRIM(WS-P1) TO WS-TXID
            MOVE FUNCTION TRIM(WS-P2) TO WS-CONTA
            COMPUTE WS-CENT =
                FUNCTION NUMVAL(FUNCTION TRIM(WS-P3))
            CALL "FIN-SAQUE" USING WS-TXID WS-CONTA
                WS-CENT WS-RC WS-MSG
        WHEN "TRANSFER"
            MOVE FUNCTION TRIM(WS-P1) TO WS-TXID
            MOVE FUNCTION TRIM(WS-P2) TO WS-CONTA
            MOVE FUNCTION TRIM(WS-P3) TO WS-DEST
            COMPUTE WS-CENT =
                FUNCTION NUMVAL(FUNCTION TRIM(WS-P4))
            CALL "FIN-TRANSFERENCIA" USING WS-TXID WS-CONTA
                WS-DEST WS-CENT WS-RC WS-MSG
        WHEN "REVERSAL"
            MOVE FUNCTION TRIM(WS-P1) TO WS-TXID
            MOVE FUNCTION TRIM(WS-P2) TO WS-TXORIG
            CALL "FIN-ESTORNO" USING WS-TXID WS-TXORIG
                WS-RC WS-MSG
    END-EVALUATE.
    CALL "LB-DATA-SAVE" USING WS-RC-SAVE.
    DISPLAY "RC: " WS-RC.
    DISPLAY "MSG: " FUNCTION TRIM(WS-MSG).
    DISPLAY "TX: " FUNCTION TRIM(WS-TXID).
    .

P-OP-BALANCE.
    MOVE FUNCTION TRIM(WS-P1) TO WS-CONTA.
    CALL "CONS-SALDO" USING WS-DIR WS-CONTA
        WS-SALDO-OUT WS-RC.
    DISPLAY "RC: " WS-RC.
    IF WS-RC = 0
        DISPLAY "BALANCE: " WS-SALDO-OUT
    ELSE
        DISPLAY "MSG: conta inexistente"
    END-IF.
    .

P-OP-TX.
    PERFORM P-INIT-LOAD.
    MOVE FUNCTION TRIM(WS-P1) TO WS-TXID.
    CALL "LB-TX-FIND" USING WS-TXID WS-TXR-REC WS-FOUND.
    CALL "LB-DATA-SAVE" USING WS-RC-SAVE.
    IF WS-FOUND = "N"
        DISPLAY "RC: 12"
        DISPLAY "MSG: transacao inexistente"
    ELSE
        DISPLAY "RC: 0"
        DISPLAY "TX-ID: "
            FUNCTION TRIM(TXR-ID OF WS-TXR-REC)
        DISPLAY "TX-DATAHORA: "
            FUNCTION TRIM(TXR-DATAHORA OF WS-TXR-REC)
        DISPLAY "TX-RESULTADO: "
            FUNCTION TRIM(TXR-RESULTADO OF WS-TXR-REC)
        DISPLAY "TX-DETALHE: "
            FUNCTION TRIM(TXR-DETALHE OF WS-TXR-REC)
    END-IF.
    .

P-OP-STATEMENT.
    MOVE FUNCTION TRIM(WS-P1) TO WS-CONTA.
    CALL "CONS-EXTRATO-API" USING WS-DIR WS-CONTA.
    DISPLAY "RC: 0".
    .

P-OP-ACCOUNT.
    PERFORM P-INIT-LOAD.
    MOVE FUNCTION TRIM(WS-P1) TO WS-CONTA.
    MOVE WS-CONTA TO WS-ID24.
    CALL "LB-CTA-FIND" USING WS-ID24 WS-CTA-REC WS-FOUND.
    CALL "LB-DATA-SAVE" USING WS-RC-SAVE.
    IF WS-FOUND = "N"
        DISPLAY "RC: 1"
        DISPLAY "MSG: conta inexistente"
    ELSE
        DISPLAY "RC: 0"
        DISPLAY "CTA-NUMERO: "
            FUNCTION TRIM(CTA-NUMERO OF WS-CTA-REC)
        DISPLAY "CTA-TIPO: "
            FUNCTION TRIM(CTA-TIPO OF WS-CTA-REC)
        DISPLAY "CTA-STATUS: "
            FUNCTION TRIM(CTA-STATUS OF WS-CTA-REC)
        DISPLAY "CTA-SALDO: " CTA-SALDO OF WS-CTA-REC
    END-IF.
    .

>>SOURCE FORMAT IS FREE
*>==============================================================*
*> LEGACYBANK - programa principal (menu interativo)
*> Uso: legacybank [dir-dados]
*>==============================================================*
IDENTIFICATION DIVISION.
PROGRAM-ID. LEGACYBANK.

DATA DIVISION.
WORKING-STORAGE SECTION.
01 WS-ARGC            PIC 9(4).
01 WS-DIR             PIC X(256) VALUE "./data".
01 WS-OPCAO           PIC X(2).
01 WS-RC              PIC 9(2).
01 WS-MSG             PIC X(120).
01 WS-MSG2            PIC X(80).
01 WS-NOME            PIC X(60).
01 WS-CPF             PIC X(14).
01 WS-EMAIL           PIC X(60).
01 WS-ID              PIC X(24).
01 WS-ID24            PIC X(24).
01 WS-ID-OUT          PIC X(7).
01 WS-NUM-OUT         PIC X(8).
01 WS-TIPO            PIC X(2).
01 WS-CONTA           PIC X(8).
01 WS-DEST            PIC X(8).
01 WS-TXID            PIC X(24).
01 WS-VAL-TXT         PIC X(40).
01 WS-VAL-REAL        PIC 9(11)V99.
01 WS-VAL-CENT        PIC 9(13).
01 WS-SALDO           PIC 9(13).
01 WS-PARSE-OK        PIC X(1).
01 WS-I               PIC 9(3).
01 WS-SEP-N           PIC 9(3).
01 WS-REAIS           PIC 9(11).
01 WS-CENT            PIC 99.
01 WS-VLR-FMT         PIC X(40).

PROCEDURE DIVISION.
MAIN-PARA.
    ACCEPT WS-ARGC FROM ARGUMENT-NUMBER.
    IF WS-ARGC >= 1
        ACCEPT WS-DIR FROM ARGUMENT-VALUE
    END-IF.
    CALL "LB-DATA-INIT" USING WS-DIR.
    CALL "LB-DATA-LOAD" USING WS-RC.
    CALL "LB-DATA-CHECK" USING WS-RC WS-MSG.
    IF WS-RC NOT = 0
        DISPLAY " "
        DISPLAY FUNCTION TRIM(WS-MSG)
        DISPLAY " "
    END-IF.
    DISPLAY " ".
    DISPLAY "======== LEGACYBANK - Sistema Bancario ========".
    DISPLAY "Diretorio de dados: " FUNCTION TRIM(WS-DIR).
    PERFORM P-MENU UNTIL WS-OPCAO = "0".
    CALL "LB-DATA-SAVE" USING WS-RC.
    DISPLAY "Dados salvos. Ate logo!".
    STOP RUN.

P-MENU.
    DISPLAY " ".
    DISPLAY " 1 Cadastrar cliente      8  Saldo".
    DISPLAY " 2 Atualizar cliente      9  Listar clientes".
    DISPLAY " 3 Abrir conta            10 Listar contas".
    DISPLAY " 4 Depositar              11 Bloquear conta".
    DISPLAY " 5 Sacar                  12 Desbloquear conta".
    DISPLAY " 6 Transferir             13 Encerrar conta".
    DISPLAY " 7 Extrato                14 Relatorio geral".
    DISPLAY " 0 Sair".
    DISPLAY "Opcao: " WITH NO ADVANCING.
    ACCEPT WS-OPCAO.
    EVALUATE FUNCTION TRIM(WS-OPCAO)
        WHEN "1" PERFORM P-OP-NOVO-CLIENTE
        WHEN "2" PERFORM P-OP-UPD-CLIENTE
        WHEN "3" PERFORM P-OP-NOVA-CONTA
        WHEN "4" PERFORM P-OP-DEPOSITO
        WHEN "5" PERFORM P-OP-SAQUE
        WHEN "6" PERFORM P-OP-TRANSFERENCIA
        WHEN "7" PERFORM P-OP-EXTRATO
        WHEN "8" PERFORM P-OP-SALDO
        WHEN "9" CALL "CONS-LISTA-CLIENTES" USING WS-DIR
        WHEN "10" CALL "CONS-LISTA-CONTAS" USING WS-DIR
        WHEN "11" PERFORM P-OP-BLOQUEAR
        WHEN "12" PERFORM P-OP-DESBLOQUEAR
        WHEN "13" PERFORM P-OP-ENCERRAR
        WHEN "14" CALL "CONS-RELATORIO" USING WS-DIR
        WHEN "0" CONTINUE
        WHEN OTHER DISPLAY "Opcao invalida."
    END-EVALUATE.
    .

P-SALVA.
    CALL "LB-DATA-SAVE" USING WS-RC.
    CALL "LB-DATA-REOPEN".
    .

P-MOSTRA-RC.
    IF WS-RC = 0
        DISPLAY "OK: " FUNCTION TRIM(WS-MSG2)
    ELSE
        DISPLAY "ERRO (" WS-RC "): " FUNCTION TRIM(WS-MSG2)
    END-IF.
    .

P-OP-NOVO-CLIENTE.
    DISPLAY "Nome: " WITH NO ADVANCING.
    ACCEPT WS-NOME.
    DISPLAY "CPF: " WITH NO ADVANCING.
    ACCEPT WS-CPF.
    DISPLAY "E-mail: " WITH NO ADVANCING.
    ACCEPT WS-EMAIL.
    CALL "CAD-NOVO-CLIENTE" USING WS-NOME WS-CPF WS-EMAIL
        WS-ID-OUT WS-RC WS-MSG2.
    PERFORM P-MOSTRA-RC.
    IF WS-RC = 0
        DISPLAY "ID do cliente: " FUNCTION TRIM(WS-ID-OUT)
        PERFORM P-SALVA
    END-IF.
    .

P-OP-UPD-CLIENTE.
    DISPLAY "ID do cliente: " WITH NO ADVANCING.
    ACCEPT WS-ID.
    DISPLAY "Novo nome (vazio = mantem): " WITH NO ADVANCING.
    ACCEPT WS-NOME.
    DISPLAY "Novo e-mail (vazio = mantem): " WITH NO ADVANCING.
    ACCEPT WS-EMAIL.
    CALL "CAD-UPD-CLIENTE" USING WS-ID WS-NOME WS-EMAIL
        WS-RC WS-MSG2.
    PERFORM P-MOSTRA-RC.
    IF WS-RC = 0
        PERFORM P-SALVA
    END-IF.
    .

P-OP-NOVA-CONTA.
    DISPLAY "ID do cliente: " WITH NO ADVANCING.
    ACCEPT WS-ID.
    DISPLAY "Tipo (CC/CP): " WITH NO ADVANCING.
    ACCEPT WS-TIPO.
    CALL "CAD-NOVA-CONTA" USING WS-ID WS-TIPO
        WS-NUM-OUT WS-RC WS-MSG2.
    PERFORM P-MOSTRA-RC.
    IF WS-RC = 0
        DISPLAY "Numero da conta: " FUNCTION TRIM(WS-NUM-OUT)
        PERFORM P-SALVA
    END-IF.
    .

P-OP-DEPOSITO.
    DISPLAY "Conta: " WITH NO ADVANCING.
    ACCEPT WS-CONTA.
    PERFORM P-LER-VALOR.
    IF WS-PARSE-OK = "N"
        DISPLAY "Valor invalido."
        EXIT PARAGRAPH
    END-IF.
    CALL "LB-TX-GEN" USING WS-TXID.
    CALL "FIN-DEPOSITO" USING WS-TXID WS-CONTA WS-VAL-CENT
        WS-RC WS-MSG2.
    PERFORM P-MOSTRA-RC.
    IF WS-RC = 0
        PERFORM P-SALVA
    END-IF.
    .

P-OP-SAQUE.
    DISPLAY "Conta: " WITH NO ADVANCING.
    ACCEPT WS-CONTA.
    PERFORM P-LER-VALOR.
    IF WS-PARSE-OK = "N"
        DISPLAY "Valor invalido."
        EXIT PARAGRAPH
    END-IF.
    CALL "LB-TX-GEN" USING WS-TXID.
    CALL "FIN-SAQUE" USING WS-TXID WS-CONTA WS-VAL-CENT
        WS-RC WS-MSG2.
    PERFORM P-MOSTRA-RC.
    IF WS-RC = 0
        PERFORM P-SALVA
    END-IF.
    .

P-OP-TRANSFERENCIA.
    DISPLAY "Conta origem: " WITH NO ADVANCING.
    ACCEPT WS-CONTA.
    DISPLAY "Conta destino: " WITH NO ADVANCING.
    ACCEPT WS-DEST.
    PERFORM P-LER-VALOR.
    IF WS-PARSE-OK = "N"
        DISPLAY "Valor invalido."
        EXIT PARAGRAPH
    END-IF.
    CALL "LB-TX-GEN" USING WS-TXID.
    CALL "FIN-TRANSFERENCIA" USING WS-TXID WS-CONTA WS-DEST
        WS-VAL-CENT WS-RC WS-MSG2.
    PERFORM P-MOSTRA-RC.
    IF WS-RC = 0
        PERFORM P-SALVA
    END-IF.
    .

P-OP-EXTRATO.
    DISPLAY "Conta: " WITH NO ADVANCING.
    ACCEPT WS-CONTA.
    CALL "CONS-EXTRATO" USING WS-DIR WS-CONTA.
    .

P-OP-SALDO.
    DISPLAY "Conta: " WITH NO ADVANCING.
    ACCEPT WS-CONTA.
    CALL "CONS-SALDO" USING WS-DIR WS-CONTA WS-SALDO WS-RC.
    IF WS-RC = 0
        CALL "CONS-FORMATA-VALOR" USING WS-SALDO WS-VLR-FMT
        DISPLAY "Saldo: R$ " FUNCTION TRIM(WS-VLR-FMT)
    ELSE
        DISPLAY "Conta inexistente."
    END-IF.
    .

P-OP-BLOQUEAR.
    DISPLAY "Conta: " WITH NO ADVANCING.
    ACCEPT WS-CONTA.
    MOVE FUNCTION TRIM(WS-CONTA) TO WS-ID24.
    CALL "CAD-BLOQUEAR-CONTA" USING WS-ID24 WS-RC WS-MSG2.
    PERFORM P-MOSTRA-RC.
    IF WS-RC = 0
        PERFORM P-SALVA
    END-IF.
    .

P-OP-DESBLOQUEAR.
    DISPLAY "Conta: " WITH NO ADVANCING.
    ACCEPT WS-CONTA.
    MOVE FUNCTION TRIM(WS-CONTA) TO WS-ID24.
    CALL "CAD-DESBLOQUEAR-CONTA" USING WS-ID24 WS-RC WS-MSG2.
    PERFORM P-MOSTRA-RC.
    IF WS-RC = 0
        PERFORM P-SALVA
    END-IF.
    .

P-OP-ENCERRAR.
    DISPLAY "Conta: " WITH NO ADVANCING.
    ACCEPT WS-CONTA.
    MOVE FUNCTION TRIM(WS-CONTA) TO WS-ID24.
    CALL "CAD-ENCERRAR-CONTA" USING WS-ID24 WS-RC WS-MSG2.
    PERFORM P-MOSTRA-RC.
    IF WS-RC = 0
        PERFORM P-SALVA
    END-IF.
    .

P-LER-VALOR.
    DISPLAY "Valor (ex.: 150.75): " WITH NO ADVANCING.
    ACCEPT WS-VAL-TXT.
    MOVE FUNCTION TRIM(WS-VAL-TXT) TO WS-VAL-TXT.
    MOVE "N" TO WS-PARSE-OK.
    MOVE 0 TO WS-VAL-CENT.
    IF WS-VAL-TXT = SPACES
        EXIT PARAGRAPH
    END-IF.
    MOVE 0 TO WS-SEP-N.
    PERFORM VARYING WS-I FROM 1 BY 1
            UNTIL WS-I > FUNCTION LENGTH(FUNCTION TRIM(WS-VAL-TXT))
        IF WS-VAL-TXT(WS-I:1) >= "0"
                AND WS-VAL-TXT(WS-I:1) <= "9"
            CONTINUE
        ELSE
            IF WS-VAL-TXT(WS-I:1) = "."
                    OR WS-VAL-TXT(WS-I:1) = ","
                ADD 1 TO WS-SEP-N
                IF WS-SEP-N > 1
                    EXIT PARAGRAPH
                END-IF
                MOVE "." TO WS-VAL-TXT(WS-I:1)
            ELSE
                IF WS-VAL-TXT(WS-I:1) = "-" AND WS-I = 1
                    *> valor negativo: normaliza para zero; o nucleo
                    *> financeiro rejeita com RC=5 (fonte unica)
                    MOVE 0 TO WS-VAL-CENT
                    MOVE "S" TO WS-PARSE-OK
                    EXIT PARAGRAPH
                END-IF
                EXIT PARAGRAPH
            END-IF
        END-IF
    END-PERFORM.
    COMPUTE WS-VAL-REAL =
        FUNCTION NUMVAL(FUNCTION TRIM(WS-VAL-TXT)).
    COMPUTE WS-VAL-CENT =
        FUNCTION INTEGER(WS-VAL-REAL * 100 + 0.5).
    MOVE "S" TO WS-PARSE-OK.
    .

>>SOURCE FORMAT IS FREE
*>==============================================================*
*> LEGACYBANK - LB-CAD
*> Cadastros: clientes e contas (abertura, consulta, atualizacao,
*> bloqueio, desbloqueio, encerramento).
*> Validacoes de negocio centralizadas aqui.
*>==============================================================*
IDENTIFICATION DIVISION.
PROGRAM-ID. LB-CAD.

DATA DIVISION.
WORKING-STORAGE SECTION.
COPY "copy/constantes.cpy".

01 WS-FOUND           PIC X(1).
01 WS-DATAHORA        PIC X(19).
01 WS-DATA-10         PIC X(10).
01 WS-SEQ-N           PIC 9(9).
01 WS-QUAL            PIC X(10).
01 WS-AUD-TXT         PIC X(200).
01 WS-ID-GERADO       PIC X(24).
01 WS-NUM6-N          PIC 9(6).
01 WS-NUM6-X REDEFINES WS-NUM6-N PIC X(6).
01 WS-NUM8-N          PIC 9(8).
01 WS-NUM8-X REDEFINES WS-NUM8-N PIC X(8).
01 WS-DIGITOS         PIC 9(3).
01 WS-I               PIC 9(3).
01 WS-CH              PIC X(1).
01 WS-NOVO-STATUS     PIC X(1).
01 WS-OK-MSG          PIC X(80).

01 WS-CLI-REC.
   COPY "copy/clientes.cpy".
01 WS-CTA-REC.
   COPY "copy/contas.cpy".

LINKAGE SECTION.
01 LK-NOME            PIC X(60).
01 LK-CPF             PIC X(14).
01 LK-EMAIL           PIC X(60).
01 LK-ID              PIC X(24).
01 LK-ID-OUT          PIC X(7).
01 LK-NUM-OUT         PIC X(8).
01 LK-TIPO            PIC X(2).
01 LK-RC              PIC 9(2).
01 LK-MSG             PIC X(80).

PROCEDURE DIVISION.
    GOBACK.

*>--------------------------------------------------------------*
*> CAD-NOVO-CLIENTE: valida e cadastra; devolve o ID gerado.
*>--------------------------------------------------------------*
ENTRY "CAD-NOVO-CLIENTE"
        USING LK-NOME LK-CPF LK-EMAIL LK-ID-OUT LK-RC LK-MSG.
    MOVE 0 TO LK-RC.
    MOVE SPACES TO LK-MSG LK-ID-OUT.
    IF FUNCTION TRIM(LK-NOME) = SPACES
        MOVE 5 TO LK-RC
        MOVE "Nome invalido." TO LK-MSG
        GOBACK
    END-IF.
    PERFORM P-VALIDA-CPF.
    IF LK-RC NOT = 0
        GOBACK
    END-IF.
    PERFORM P-VALIDA-EMAIL.
    IF LK-RC NOT = 0
        GOBACK
    END-IF.
    MOVE "CLIENTE" TO WS-QUAL.
    CALL "LB-SEQ-NEXT" USING WS-QUAL WS-SEQ-N.
    MOVE WS-SEQ-N TO WS-NUM6-N.
    STRING "C" DELIMITED BY SIZE
           WS-NUM6-X DELIMITED BY SIZE
        INTO LK-ID-OUT
    END-STRING.
    MOVE LK-ID-OUT TO CLI-ID OF WS-CLI-REC.
    MOVE FUNCTION TRIM(LK-NOME) TO CLI-NOME OF WS-CLI-REC.
    MOVE FUNCTION TRIM(LK-CPF) TO CLI-CPF OF WS-CLI-REC.
    MOVE FUNCTION TRIM(LK-EMAIL) TO CLI-EMAIL OF WS-CLI-REC.
    CALL "LB-NOW" USING WS-DATAHORA.
    MOVE WS-DATAHORA(1:10) TO CLI-DATA-CAD OF WS-CLI-REC.
    MOVE "A" TO CLI-STATUS OF WS-CLI-REC.
    CALL "LB-CLI-ADD" USING WS-CLI-REC LK-RC.
    IF LK-RC NOT = 0
        MOVE "Erro interno ao gravar cliente." TO LK-MSG
        GOBACK
    END-IF.
    MOVE SPACES TO WS-AUD-TXT
    STRING "CLIENTE_CADASTRADO id=" DELIMITED BY SIZE
        FUNCTION TRIM(LK-ID-OUT) DELIMITED BY SIZE
        INTO WS-AUD-TXT
    END-STRING.
    CALL "LB-AUDIT" USING WS-AUD-TXT.
    MOVE "Cliente cadastrado." TO LK-MSG.
    GOBACK.

*>--------------------------------------------------------------*
*> CAD-UPD-CLIENTE: atualiza nome e e-mail de um cliente.
*>--------------------------------------------------------------*
ENTRY "CAD-UPD-CLIENTE"
        USING LK-ID LK-NOME LK-EMAIL LK-RC LK-MSG.
    MOVE 0 TO LK-RC.
    MOVE SPACES TO LK-MSG.
    CALL "LB-CLI-FIND" USING LK-ID WS-CLI-REC WS-FOUND.
    IF WS-FOUND = "N"
        MOVE 7 TO LK-RC
        MOVE "Cliente inexistente." TO LK-MSG
        GOBACK
    END-IF.
    IF FUNCTION TRIM(LK-NOME) NOT = SPACES
        MOVE FUNCTION TRIM(LK-NOME) TO CLI-NOME OF WS-CLI-REC
    END-IF.
    IF FUNCTION TRIM(LK-EMAIL) NOT = SPACES
        MOVE FUNCTION TRIM(LK-EMAIL) TO LK-EMAIL
        PERFORM P-VALIDA-EMAIL-UPD
        IF LK-RC NOT = 0
            GOBACK
        END-IF
        MOVE FUNCTION TRIM(LK-EMAIL) TO CLI-EMAIL OF WS-CLI-REC
    END-IF.
    CALL "LB-CLI-UPD" USING WS-CLI-REC LK-RC.
    IF LK-RC = 0
        MOVE "Cliente atualizado." TO LK-MSG
        MOVE SPACES TO WS-AUD-TXT
        STRING "CLIENTE_ATUALIZADO id=" DELIMITED BY SIZE
            FUNCTION TRIM(LK-ID) DELIMITED BY SIZE
            INTO WS-AUD-TXT
        END-STRING
        CALL "LB-AUDIT" USING WS-AUD-TXT
    ELSE
        MOVE "Erro interno ao atualizar cliente." TO LK-MSG
    END-IF.
    GOBACK.

*>--------------------------------------------------------------*
*> CAD-NOVA-CONTA: abre conta para um cliente existente.
*>--------------------------------------------------------------*
ENTRY "CAD-NOVA-CONTA"
        USING LK-ID LK-TIPO LK-NUM-OUT LK-RC LK-MSG.
    MOVE 0 TO LK-RC.
    MOVE SPACES TO LK-MSG LK-NUM-OUT.
    CALL "LB-CLI-FIND" USING LK-ID WS-CLI-REC WS-FOUND.
    IF WS-FOUND = "N"
        MOVE 7 TO LK-RC
        MOVE "Cliente inexistente." TO LK-MSG
        GOBACK
    END-IF.
    IF FUNCTION TRIM(LK-TIPO) NOT = "CC"
            AND FUNCTION TRIM(LK-TIPO) NOT = "CP"
        MOVE 5 TO LK-RC
        MOVE "Tipo invalido (use CC ou CP)." TO LK-MSG
        GOBACK
    END-IF.
    MOVE "CONTA" TO WS-QUAL.
    CALL "LB-SEQ-NEXT" USING WS-QUAL WS-SEQ-N.
    MOVE WS-SEQ-N TO WS-NUM8-N.
    MOVE WS-NUM8-X TO LK-NUM-OUT.
    MOVE LK-NUM-OUT TO CTA-NUMERO OF WS-CTA-REC.
    MOVE FUNCTION TRIM(LK-ID) TO CTA-CLIENTE-ID OF WS-CTA-REC.
    MOVE FUNCTION TRIM(LK-TIPO) TO CTA-TIPO OF WS-CTA-REC.
    MOVE "A" TO CTA-STATUS OF WS-CTA-REC.
    MOVE 0 TO CTA-SALDO OF WS-CTA-REC.
    CALL "LB-NOW" USING WS-DATAHORA.
    MOVE WS-DATAHORA(1:10) TO CTA-DATA-ABERT OF WS-CTA-REC.
    CALL "LB-CTA-ADD" USING WS-CTA-REC LK-RC.
    IF LK-RC NOT = 0
        MOVE "Erro interno ao abrir conta." TO LK-MSG
        GOBACK
    END-IF.
    MOVE SPACES TO WS-AUD-TXT
    STRING "CONTA_ABERTA num=" DELIMITED BY SIZE
        FUNCTION TRIM(LK-NUM-OUT) DELIMITED BY SIZE
        " cliente=" DELIMITED BY SIZE
        FUNCTION TRIM(LK-ID) DELIMITED BY SIZE
        INTO WS-AUD-TXT
    END-STRING.
    CALL "LB-AUDIT" USING WS-AUD-TXT.
    MOVE "Conta aberta." TO LK-MSG.
    GOBACK.

*>--------------------------------------------------------------*
*> CAD-BLOQUEAR-CONTA / DESBLOQUEAR / ENCERRAR
*>--------------------------------------------------------------*
ENTRY "CAD-BLOQUEAR-CONTA" USING LK-ID LK-RC LK-MSG.
    MOVE "B" TO WS-NOVO-STATUS.
    MOVE "Conta bloqueada." TO WS-OK-MSG.
    PERFORM P-TROCA-STATUS-CONTA.
    GOBACK.

ENTRY "CAD-DESBLOQUEAR-CONTA" USING LK-ID LK-RC LK-MSG.
    MOVE "A" TO WS-NOVO-STATUS.
    MOVE "Conta desbloqueada." TO WS-OK-MSG.
    PERFORM P-TROCA-STATUS-CONTA.
    GOBACK.

ENTRY "CAD-ENCERRAR-CONTA" USING LK-ID LK-RC LK-MSG.
    MOVE 0 TO LK-RC.
    MOVE SPACES TO LK-MSG.
    CALL "LB-CTA-FIND" USING LK-ID WS-CTA-REC WS-FOUND.
    IF WS-FOUND = "N"
        MOVE 1 TO LK-RC
        MOVE "Conta inexistente." TO LK-MSG
        GOBACK
    END-IF.
    IF CTA-STATUS OF WS-CTA-REC = "E"
        MOVE 3 TO LK-RC
        MOVE "Conta ja encerrada." TO LK-MSG
        GOBACK
    END-IF.
    IF CTA-SALDO OF WS-CTA-REC NOT = 0
        MOVE 9 TO LK-RC
        MOVE "Conta com saldo nao pode ser encerrada." TO LK-MSG
        GOBACK
    END-IF.
    MOVE "E" TO CTA-STATUS OF WS-CTA-REC.
    CALL "LB-CTA-UPD" USING WS-CTA-REC LK-RC.
    IF LK-RC = 0
        MOVE "Conta encerrada." TO LK-MSG
        MOVE SPACES TO WS-AUD-TXT
        STRING "CONTA_ENCERRADA num=" DELIMITED BY SIZE
            FUNCTION TRIM(LK-ID) DELIMITED BY SIZE
            INTO WS-AUD-TXT
        END-STRING
        CALL "LB-AUDIT" USING WS-AUD-TXT
    ELSE
        MOVE "Erro interno." TO LK-MSG
    END-IF.
    GOBACK.

*>==============================================================*
*> Rotinas internas
*>==============================================================*
P-TROCA-STATUS-CONTA.
    MOVE 0 TO LK-RC.
    MOVE SPACES TO LK-MSG.
    CALL "LB-CTA-FIND" USING LK-ID WS-CTA-REC WS-FOUND.
    IF WS-FOUND = "N"
        MOVE 1 TO LK-RC
        MOVE "Conta inexistente." TO LK-MSG
        EXIT PARAGRAPH
    END-IF.
    IF CTA-STATUS OF WS-CTA-REC = "E"
        MOVE 3 TO LK-RC
        MOVE "Conta encerrada: status imutavel." TO LK-MSG
        EXIT PARAGRAPH
    END-IF.
    MOVE WS-NOVO-STATUS TO CTA-STATUS OF WS-CTA-REC.
    CALL "LB-CTA-UPD" USING WS-CTA-REC LK-RC.
    IF LK-RC = 0
        MOVE WS-OK-MSG TO LK-MSG
        MOVE SPACES TO WS-AUD-TXT
        STRING "CONTA_STATUS num=" DELIMITED BY SIZE
            FUNCTION TRIM(LK-ID) DELIMITED BY SIZE
            " status=" DELIMITED BY SIZE
            WS-NOVO-STATUS DELIMITED BY SIZE
            INTO WS-AUD-TXT
        END-STRING
        CALL "LB-AUDIT" USING WS-AUD-TXT
    ELSE
        MOVE "Erro interno." TO LK-MSG
    END-IF.
    .

P-VALIDA-CPF.
    MOVE 0 TO LK-RC WS-DIGITOS.
    PERFORM VARYING WS-I FROM 1 BY 1 UNTIL WS-I > 14
        MOVE LK-CPF(WS-I:1) TO WS-CH
        IF WS-CH >= "0" AND WS-CH <= "9"
            ADD 1 TO WS-DIGITOS
        ELSE
            IF WS-CH NOT = "." AND WS-CH NOT = "-"
                    AND WS-CH NOT = SPACE
                MOVE 5 TO LK-RC
                MOVE "CPF invalido." TO LK-MSG
                EXIT PARAGRAPH
            END-IF
        END-IF
    END-PERFORM.
    IF WS-DIGITOS NOT = 11
        MOVE 5 TO LK-RC
        MOVE "CPF invalido (esperados 11 digitos)." TO LK-MSG
    END-IF.
    .

P-VALIDA-EMAIL.
    MOVE 0 TO LK-RC.
    IF FUNCTION TRIM(LK-EMAIL) = SPACES
        MOVE 5 TO LK-RC
        MOVE "E-mail invalido." TO LK-MSG
        EXIT PARAGRAPH
    END-IF.
    MOVE FUNCTION TRIM(LK-EMAIL) TO LK-EMAIL.
    PERFORM P-VALIDA-EMAIL-UPD.
    .

P-VALIDA-EMAIL-UPD.
    *> verificacao simples: deve conter exatamente um "@"
    MOVE 0 TO LK-RC WS-DIGITOS.
    PERFORM VARYING WS-I FROM 1 BY 1
            UNTIL WS-I > FUNCTION LENGTH(FUNCTION TRIM(LK-EMAIL))
        IF LK-EMAIL(WS-I:1) = "@"
            ADD 1 TO WS-DIGITOS
        END-IF
    END-PERFORM.
    IF WS-DIGITOS NOT = 1
        MOVE 5 TO LK-RC
        MOVE "E-mail invalido." TO LK-MSG
    END-IF.
    .

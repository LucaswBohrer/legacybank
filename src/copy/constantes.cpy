      *>==============================================================*
      *> LEGACYBANK - COPY book: constantes do sistema
      *> Valores de negocio centralizados aqui para evitar "magic numbers"
      *> espalhados pelo codigo (valores em centavos).
      *>==============================================================*
       01  CONSTANTES-LEGACYBANK.
           05 TARIFA-SAQUE-CENTAVOS        PIC 9(6)  VALUE 150.
           05 TARIFA-TRANSFER-CENTAVOS     PIC 9(6)  VALUE 200.
      *> Limites das tabelas em memoria
           05 MAX-CLIENTES                 PIC 9(6)  VALUE 10000.
           05 MAX-CONTAS                   PIC 9(6)  VALUE 20000.
           05 MAX-TXREG                    PIC 9(7)  VALUE 500000.
      *> Status de conta
           05 ST-CONTA-ATIVA               PIC X(1)  VALUE "A".
           05 ST-CONTA-BLOQUEADA           PIC X(1)  VALUE "B".
           05 ST-CONTA-ENCERRADA           PIC X(1)  VALUE "E".
      *> Codigos de erro das operacoes financeiras
           05 ERR-OK                       PIC 9(2)  VALUE 00.
           05 ERR-CONTA-INEXISTENTE        PIC 9(2)  VALUE 01.
           05 ERR-CONTA-BLOQUEADA          PIC 9(2)  VALUE 02.
           05 ERR-CONTA-ENCERRADA          PIC 9(2)  VALUE 03.
           05 ERR-SALDO-INSUFICIENTE       PIC 9(2)  VALUE 04.
           05 ERR-VALOR-INVALIDO           PIC 9(2)  VALUE 05.
           05 ERR-DUPLICADA                PIC 9(2)  VALUE 06.
           05 ERR-CLIENTE-INEXISTENTE      PIC 9(2)  VALUE 07.
           05 ERR-CONTA-JA-EXISTE          PIC 9(2)  VALUE 08.
           05 ERR-CONTA-COM-SALDO          PIC 9(2)  VALUE 09.
           05 ERR-ERRO-INTERNO             PIC 9(2)  VALUE 10.
           05 ERR-ORIGEM-DEST-IGUAIS       PIC 9(2)  VALUE 11.

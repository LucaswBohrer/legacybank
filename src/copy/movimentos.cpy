      *>==============================================================*
      *> LEGACYBANK - COPY book: campos do registro de MOVIMENTO
      *> (declarar sob um grupo 01 proprio)
      *> Linha em movimentos.dat (journal append-only):
      *>   SEQ;DATAHORA;TIPO;CONTA;CONTA_DESTINO;VALOR;TX_ID;DESCRICAO
      *> Exemplo:
      *>   1;2026-10-01 10:00:01;DEPOSITO;10000001;;15075;
      *>     TX-20261001100001-0001;Deposito em conta
      *> VALOR em centavos inteiros. CONTA_DESTINO preenchido apenas em
      *> TRANSFERENCIA (CONTA = origem). A tarifa de uma operacao e um
      *> movimento proprio do tipo TARIFA com o mesmo TX_ID.
      *> TIPO: DEPOSITO, SAQUE, TRANSFERENCIA, TARIFA
      *>==============================================================*
          10 MOV-SEQ           PIC 9(9).
          10 MOV-DATAHORA      PIC X(19).
          10 MOV-TIPO          PIC X(13).
          10 MOV-CONTA         PIC X(8).
          10 MOV-CONTA-DEST    PIC X(8).
          10 MOV-VALOR         PIC 9(13).
          10 MOV-TX-ID         PIC X(24).
          10 MOV-DESCRICAO     PIC X(80).

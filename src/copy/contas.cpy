      *>==============================================================*
      *> LEGACYBANK - COPY book: campos do registro de CONTA
      *> (declarar sob um grupo 01 proprio)
      *> Linha em contas.dat:
      *>   NUMERO;CLIENTE_ID;TIPO;STATUS;SALDO_CENTAVOS;DATA_ABERTURA
      *> Exemplo:
      *>   10000001;C000001;CC;A;15075;2026-10-01
      *> (saldo em centavos inteiros: 15075 = R$ 150,75)
      *> TIPO: "CC" = corrente, "CP" = poupanca
      *> STATUS: "A" = ativa, "B" = bloqueada, "E" = encerrada
      *>==============================================================*
          10 CTA-NUMERO        PIC X(8).
          10 CTA-CLIENTE-ID    PIC X(7).
          10 CTA-TIPO          PIC X(2).
          10 CTA-STATUS        PIC X(1).
          10 CTA-SALDO         PIC 9(13).
          10 CTA-DATA-ABERT    PIC X(10).

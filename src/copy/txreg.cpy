      *>==============================================================*
      *> LEGACYBANK - COPY book: campos do registro de IDEMPOTENCIA
      *> (declarar sob um grupo 01 proprio)
      *> Linha em tx_registry.dat:
      *>   TX_ID;DATAHORA;RESULTADO;DETALHE
      *> Exemplo:
      *>   TX-20261001100001-0001;2026-10-01 10:00:01;OK;DEPOSITO 150.75
      *> RESULTADO: OK | REJEITADA
      *> Uma segunda submissao do mesmo TX_ID devolve o RESULTADO
      *> armazenado sem reexecutar a movimentacao financeira.
      *>==============================================================*
          10 TXR-ID            PIC X(24).
          10 TXR-DATAHORA      PIC X(19).
          10 TXR-RESULTADO     PIC X(12).
          10 TXR-DETALHE       PIC X(80).

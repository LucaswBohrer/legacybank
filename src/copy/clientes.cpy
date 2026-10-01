      *>==============================================================*
      *> LEGACYBANK - COPY book: campos do registro de CLIENTE
      *> (declarar sob um grupo 01 proprio; nao inclui o nivel 01 para
      *>  permitir uso dentro de OCCURS e LINKAGE SECTION)
      *> Linha em clientes.dat:
      *>   ID;NOME;CPF;EMAIL;DATA_CADASTRO;STATUS
      *> Exemplo:
      *>   C000001;Ada Lovelace;123.456.789-00;ada@exemplo.com;2026-10-01;A
      *> STATUS: "A" = ativo, "I" = inativo
      *>==============================================================*
          10 CLI-ID            PIC X(7).
          10 CLI-NOME          PIC X(60).
          10 CLI-CPF           PIC X(14).
          10 CLI-EMAIL         PIC X(60).
          10 CLI-DATA-CAD      PIC X(10).
          10 CLI-STATUS        PIC X(1).

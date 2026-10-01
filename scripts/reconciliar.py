#!/usr/bin/env python3
"""Reconciliação independente entre dois diretórios de dados do LEGACYBANK.

Uso: python3 scripts/reconciliar.py <dir-antes> <dir-depois>
Compara: saldos, nº de movimentos, nº de TX registradas, resultados
(OK/REJEITADA), totais financeiros por tipo e nº de linhas de auditoria.
Retorna 0 se tudo for equivalente, 1 caso contrário.
"""
import sys
from collections import Counter

def load(path):
    with open(path) as f:
        return [l.rstrip("\n") for l in f if l.strip()]

def main(a, b):
    ok = True
    def check(desc, va, vb):
        nonlocal ok
        status = "OK " if va == vb else "DIFERENTE"
        if va != vb:
            ok = False
        print(f"[{status}] {desc}: antes={va} depois={vb}")

    ca = {l.split(";")[0]: l.split(";")[4] for l in load(f"{a}/contas.dat")}
    cb = {l.split(";")[0]: l.split(";")[4] for l in load(f"{b}/contas.dat")}
    check("saldos das contas", ca, cb)

    ma = load(f"{a}/movimentos.dat")
    mb = load(f"{b}/movimentos.dat")
    check("nº movimentos (journal)", len(ma), len(mb))

    # totais financeiros por tipo (campo 3=TIPO, campo 6=VALOR-CENTAVOS)
    def totais(movs):
        t = Counter()
        for l in movs:
            p = l.split(";")
            t[p[2]] += int(p[5])
        return dict(sorted(t.items()))
    check("totais por tipo (centavos)", totais(ma), totais(mb))

    # tx_registry: conta por RESULTADO (campo 3)
    def res(movs_f):
        c = Counter()
        for l in load(movs_f):
            c[l.split(";")[2]] += 1
        return dict(sorted(c.items()))
    check("tx_registry por resultado", res(f"{a}/tx_registry.dat"),
          res(f"{b}/tx_registry.dat"))

    # auditoria: nº de linhas e distribuição por prefixo
    def aud(d):
        c = Counter()
        for l in load(f"{d}/auditoria.log"):
            # formato: "2026-10-01 10:00:01 | EVENTO resto..."
            evt = l.split(" | ", 1)[1].split(" ", 1)[0] if " | " in l else "?"
            c[evt] += 1
        return dict(sorted(c.items()))
    aa, ab = aud(a), aud(b)
    check("auditoria: nº linhas", sum(aa.values()), sum(ab.values()))
    check("auditoria por evento", aa, ab)

    # TX-IDs idênticos e na mesma ordem.
    # O deposito inicial de setup gera TX-ID com timestamp de parede
    # (TX-AAAAMMDDHHMMSS-NNNN): normaliza o timestamp, pois duas
    # execucoes legitimas em horarios distintos nunca terao o mesmo.
    # Todo o resto (TX-LOAD-*, ordem, duplicatas) e comparado exato.
    import re as _re
    def norm_txids(d):
        out = []
        for l in load(f"{d}/tx_registry.dat"):
            tid = l.split(";")[0]
            tid = _re.sub(r"^TX-\d{14}(-\d+)$", r"TX-<TS>\1", tid)
            out.append(tid)
        return out
    ida, idb = norm_txids(a), norm_txids(b)
    check("sequência de TX-IDs idêntica (ts normalizado)", ida == idb, True)

    print("RECONCILIAÇÃO: " + ("EQUIVALENTE" if ok else "DIVERGENTE"))
    return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))

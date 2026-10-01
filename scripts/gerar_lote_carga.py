#!/usr/bin/env python3
"""Gera lote determinístico para benchmark de carga do LEGACYBANK.

Uso: python3 scripts/gerar_lote_carga.py [N] [saida]
Padrão: N=100000, saida=/tmp/lote100k.txt

Distribuição: 60% depósitos, 20% saques, 20% transferências.
Seed fixa (42): o mesmo arquivo é gerado sempre, permitindo comparar
runs antes/depois de otimizações de forma justa.
"""
import random
import sys

N = int(sys.argv[1]) if len(sys.argv) > 1 else 100000
OUT = sys.argv[2] if len(sys.argv) > 2 else "/tmp/lote100k.txt"

random.seed(42)
ops = ["DEPOSITO"] * 60 + ["SAQUE"] * 20 + ["TRANSFERENCIA"] * 20

with open(OUT, "w") as f:
    for i in range(1, N + 1):
        tx = f"TX-LOAD-{i:06d}"
        op = random.choice(ops)
        if op == "DEPOSITO":
            v = random.randint(100, 50000) / 100
            f.write(f"DEPOSITO;{tx};10000001;{v:.2f}\n")
        elif op == "SAQUE":
            v = random.randint(100, 10000) / 100
            f.write(f"SAQUE;{tx};10000001;{v:.2f}\n")
        else:
            v = random.randint(100, 20000) / 100
            f.write(f"TRANSFERENCIA;{tx};10000001;10000002;{v:.2f}\n")

print(f"{N} linhas em {OUT}")

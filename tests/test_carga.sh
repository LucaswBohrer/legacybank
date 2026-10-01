#!/bin/bash
# test_carga.sh - carga com 100.000 transacoes em lote
# Gera o lote (deterministico, seed fixa) se ainda nao existir.
set -u
cd "$(dirname "$0")/.."
source tests/lib.sh

LB_BIN=./bin/legacybank
LB_LOTE=./bin/lb-lote
LB_INIT=./bin/lb-init
TDIR=$(mktemp -d)
trap 'rm -rf "$TDIR"' EXIT

LOTE="${LOTE_100K:-/tmp/lote100k.txt}"
if [ ! -f "$LOTE" ]; then
    echo "gerando lote de 100k transacoes..."
    "$PYBIN" - "$LOTE" <<'PYEOF'
import random, sys
random.seed(42)
out = sys.argv[1]
lines = []
for i in range(1, 100001):
    tx = f"TX-LOAD-{i:06d}"
    r = random.random()
    if r < 0.60:
        lines.append(f"DEPOSITO;{tx};10000001;{random.uniform(1,500):.2f}")
    elif r < 0.80:
        lines.append(f"SAQUE;{tx};10000001;{random.uniform(1,100):.2f}")
    else:
        lines.append(f"TRANSFERENCIA;{tx};10000001;10000002;{random.uniform(1,200):.2f}")
open(out, 'w').write('\n'.join(lines) + '\n')
PYEOF
fi

$LB_INIT "$TDIR" >/dev/null
run_menu "$TDIR" 1 "Load" "111.222.333-44" "load@t.com" 3 "C000001" "CC" 3 "C000001" "CC" 4 "10000001" "1000000.00" 0 >/dev/null

echo "--- carga: 100k transacoes ---"
inicio=$(date +%s)
out=$($LB_LOTE "$TDIR" "$LOTE" 2>&1)
fim=$(date +%s)
dur=$((fim - inicio))
echo "duracao: ${dur}s"
echo "$out" | tail -2

# Com seed 42 e saldo inicial alto, nenhuma rejeicao por saldo eh esperada.
# (saques de ate 100 e transferencias de ate 200 contra 1M + depositos)
assert_contains "100k ok" "0100000 ok" "$out"

s1=$(parse_saldo "$(run_menu "$TDIR" 8 "10000001" 0)")
s2=$(parse_saldo "$(run_menu "$TDIR" 8 "10000002" 0)")
echo "saldo final 10000001: $s1"
echo "saldo final 10000002: $s2"

# consistencia: soma dos saldos = inicial + depositos - saques - tarifas
"$PYBIN" - "$LOTE" "$s1" "$s2" <<'PYEOF'
import sys
lote, s1, s2 = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
dep = saq = tra = 0.0
n_tra = n_saq = 0
for line in open(lote):
    p = line.strip().split(';')
    if p[0] == 'DEPOSITO': dep += float(p[3])
    elif p[0] == 'SAQUE': saq += float(p[3]); n_saq += 1
    elif p[0] == 'TRANSFERENCIA': tra += float(p[3]); n_tra += 1
esperado = 1000000.0 + dep - saq - tra - n_saq*1.50 - n_tra*2.00
obtido = s1 + s2
print(f"esperado={esperado:.2f} obtido={obtido:.2f}")
sys.exit(0 if abs(esperado-obtido) < 0.01 else 1)
PYEOF
assert_eq "soma dos saldos confere com o lote" "0" "$?"

n_journal=$(wc -l < "$TDIR/movimentos.dat")
echo "linhas no journal: $n_journal"

print_summary "carga"

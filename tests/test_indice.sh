#!/bin/bash
# test_indice.sh - regressao da otimizacao do indice hash de TX-ID.
#
# Valida que a troca das buscas lineares (LB-TX-FIND / P-TX-FIND-DUP)
# pelo indice hash em lb-dados.cbl preserva integralmente a semantica:
# idempotencia, rejeicao sem efeito no saldo, reconstrucao do indice
# apos reinicializacao (LOAD) e comportamento em lote misto.
#
# Sao testes de COMPORTAMENTO: passam tanto no codigo original quanto
# no otimizado. O que muda eh o tempo de execucao.
set -u
cd "$(dirname "$0")/.."
source tests/lib.sh

LB_BIN=./bin/legacybank
LB_LOTE=./bin/lb-lote
LB_INIT=./bin/lb-init
TDIR=$(mktemp -d)
trap 'rm -rf "$TDIR"' EXIT

$LB_INIT "$TDIR" >/dev/null
run_menu "$TDIR" 1 "Indice" "111.222.333-44" "i@i.com" \
    3 "C000001" "CC" 3 "C000001" "CP" 4 "10000001" "5000.00" 0 >/dev/null

saldo() { parse_saldo "$(run_menu "$TDIR" 8 "$1" 0)"; }

echo "--- indice: TX nova processada normalmente ---"
out=$(run_menu "$TDIR" 4 "10000001" "100.00" 0)
s1=$(saldo 10000001)
assert_eq "saldo apos deposito novo" "5100.00" "$s1"

echo "--- indice: TX duplicada nao reexecuta ---"
# reenvia via lote com o MESMO txid do deposito acima? menu gera TXID
# automatico; para controlar o TX-ID usamos o lote.
cat > "$TDIR/dup.txt" <<'EOF'
DEPOSITO;TX-IDX-0001;10000001;250.00
DEPOSITO;TX-IDX-0001;10000001;250.00
EOF
out=$($LB_LOTE "$TDIR" "$TDIR/dup.txt" 2>&1)
assert_contains "1 ok" "0000001 ok" "$out"
assert_contains "1 duplicada" "0000001 duplicadas" "$out"
assert_eq "saldo com 1 deposito de 250" "5350.00" "$(saldo 10000001)"

echo "--- indice: TX rejeitada registrada; reenvio nao altera saldo ---"
cat > "$TDIR/rej.txt" <<'EOF'
SAQUE;TX-IDX-0002;10000001;-10.00
SAQUE;TX-IDX-0002;10000001;-10.00
EOF
out=$($LB_LOTE "$TDIR" "$TDIR/rej.txt" 2>&1)
assert_contains "1 rejeitada" "0000001 rejeitadas" "$out"
assert_contains "reenvio de rejeitada = duplicada" "0000001 duplicadas" "$out"
assert_eq "saldo intacto apos rejeicao+reenvio" "5350.00" "$(saldo 10000001)"
# o registro da rejeicao existe no tx_registry
assert_contains "rejeicao registrada" "TX-IDX-0002" "$(cat "$TDIR/tx_registry.dat")"

echo "--- indice: reinicializacao mantem protecao (indice reconstruido no LOAD) ---"
# cada invocacao de lb-lote eh um processo novo -> LOAD reconstrói o indice
out=$($LB_LOTE "$TDIR" "$TDIR/dup.txt" 2>&1)
assert_contains "apos restart: 0 ok" "0000000 ok" "$out"
assert_contains "apos restart: 2 duplicadas" "0000002 duplicadas" "$out"
assert_eq "saldo intacto apos restart" "5350.00" "$(saldo 10000001)"

echo "--- indice: transferencia continua atomica no lote ---"
cat > "$TDIR/tr.txt" <<'EOF'
TRANSFERENCIA;TX-IDX-0003;10000001;10000002;1000.00
EOF
out=$($LB_LOTE "$TDIR" "$TDIR/tr.txt" 2>&1)
assert_contains "transferencia ok" "0000001 ok" "$out"
assert_eq "origem debitada" "4348.00" "$(saldo 10000001)"
assert_eq "destino creditado" "1000.00" "$(saldo 10000002)"
# reenvio da transferencia nao move nada
out=$($LB_LOTE "$TDIR" "$TDIR/tr.txt" 2>&1)
assert_contains "reenvio transferencia duplicada" "0000001 duplicadas" "$out"
assert_eq "origem intacta" "4348.00" "$(saldo 10000001)"
assert_eq "destino intacto" "1000.00" "$(saldo 10000002)"

echo "--- indice: volume com colisoes forca encadeamento ---"
# 3000 TXs sequenciais: exercita insercao/lookup em massa no indice
python3 - "$TDIR/vol.txt" <<'PYEOF'
import sys
with open(sys.argv[1], "w") as f:
    for i in range(1, 3001):
        f.write(f"DEPOSITO;TX-IDX-V{i:06d};10000001;1.00\n")
    # 50 duplicadas no meio
    for i in range(1, 51):
        f.write(f"DEPOSITO;TX-IDX-V{i:06d};10000001;1.00\n")
PYEOF
out=$($LB_LOTE "$TDIR" "$TDIR/vol.txt" 2>&1)
assert_contains "volume: 3000 ok" "0003000 ok" "$out"
assert_contains "volume: 50 duplicadas" "0000050 duplicadas" "$out"
# 4348 + 3000*1.00 = 7348.00
assert_eq "saldo apos volume" "7348.00" "$(saldo 10000001)"
# restart: tudo vira duplicada (indice reconstruido do zero no LOAD)
out=$($LB_LOTE "$TDIR" "$TDIR/vol.txt" 2>&1)
assert_contains "volume reenvio: 0 ok" "0000000 ok" "$out"
assert_contains "volume reenvio: 3050 duplicadas" "0003050 duplicadas" "$out"
assert_eq "saldo intacto apos reenvio em massa" "7348.00" "$(saldo 10000001)"

print_summary "indice"

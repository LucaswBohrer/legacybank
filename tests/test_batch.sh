#!/bin/bash
# test_batch.sh - processamento em lote, contadores e idempotencia
set -u
cd "$(dirname "$0")/.."
source tests/lib.sh

LB_BIN=./bin/legacybank
LB_LOTE=./bin/lb-lote
LB_INIT=./bin/lb-init
TDIR=$(mktemp -d)
trap 'rm -rf "$TDIR"' EXIT

$LB_INIT "$TDIR" >/dev/null
run_menu "$TDIR" 1 "Lote" "111.222.333-44" "l@l.com" 3 "C000001" "CC" 3 "C000001" "CP" 4 "10000001" "1000.00" 0 >/dev/null

cat > "$TDIR/lote.txt" <<'EOF'
# comentario deve ser ignorado

DEPOSITO;TX-LOTE-0001;10000001;500.00
DEPOSITO;TX-LOTE-0001;10000001;500.00
SAQUE;TX-LOTE-0002;10000001;50,00
TRANSFERENCIA;TX-LOTE-0003;10000001;10000002;100.00
DEPOSITO;TX-LOTE-0004;99999999;10.00
SAQUE;TX-LOTE-0005;10000002;99999.00
LINHA-INVALIDA-SEM-FORMATO
DEPOSITO;TX-LOTE-0006;10000001;0.00
SAQUE;TX-LOTE-0007;10000001;-5.00
SAQUE;TX-LOTE-0007;10000001;-5.00
EOF

echo "--- batch: contadores ---"
out=$($LB_LOTE "$TDIR" "$TDIR/lote.txt" 2>&1)
assert_contains "3 ok" "0000003 ok" "$out"
assert_contains "4 rejeitadas" "0000004 rejeitadas" "$out"
assert_contains "2 duplicadas" "0000002 duplicadas" "$out"
assert_contains "1 invalida" "0000001 invalidas" "$out"

s1=$(parse_saldo "$(run_menu "$TDIR" 8 "10000001" 0)")
s2=$(parse_saldo "$(run_menu "$TDIR" 8 "10000002" 0)")
# 1000 +500 -50 -1.50 -100 -2.00 = 1346.50 ; destino = 100.00
assert_eq "saldo origem apos lote" "1346.50" "$s1"
assert_eq "saldo destino apos lote" "100.00" "$s2"

echo "--- batch: reenvio integral eh idempotente ---"
out2=$($LB_LOTE "$TDIR" "$TDIR/lote.txt" 2>&1)
assert_contains "reenvio: 0 ok" "0000000 ok" "$out2"
s1b=$(parse_saldo "$(run_menu "$TDIR" 8 "10000001" 0)")
s2b=$(parse_saldo "$(run_menu "$TDIR" 8 "10000002" 0)")
assert_eq "origem inalterada no reenvio" "$s1" "$s1b"
assert_eq "destino inalterado no reenvio" "$s2" "$s2b"

echo "--- batch: relatorio do lote existe ---"
rep=$(printf '%s' "$out" | grep -oE 'Relatorio: .*' | sed 's/Relatorio: //')
assert_eq "arquivo de relatorio criado" "1" "$([ -f "$rep" ] && echo 1 || echo 0)"

print_summary "batch"

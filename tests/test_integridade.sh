#!/bin/bash
# test_integridade.sh - rejeicoes nao mutam; reload preserva; checkpoint detecta
set -u
cd "$(dirname "$0")/.."
source tests/lib.sh

LB_BIN=./bin/legacybank
LB_INIT=./bin/lb-init
TDIR=$(mktemp -d)
trap 'rm -rf "$TDIR"' EXIT

$LB_INIT "$TDIR" >/dev/null
run_menu "$TDIR" 1 "Beto" "999.888.777-66" "beto@x.com" 3 "C000001" "CC" 3 "C000001" "CP" 4 "10000001" "500.00" 0 >/dev/null

saldo_antes=$(parse_saldo "$(run_menu "$TDIR" 8 "10000001" 0)")

echo "--- integridade: rejeicao nao altera saldo ---"
run_menu "$TDIR" 5 "10000001" "99999.99" 4 "10000001" "-10" 6 "10000001" "10000001" "5.00" 6 "10000001" "99999999" "5.00" 0 >/dev/null
saldo_depois=$(parse_saldo "$(run_menu "$TDIR" 8 "10000001" 0)")
assert_eq "saldo intacto apos 4 rejeicoes" "$saldo_antes" "$saldo_depois"

echo "--- integridade: transferencia nao debita sem creditar ---"
s_dest_antes=$(parse_saldo "$(run_menu "$TDIR" 8 "10000002" 0)")
run_menu "$TDIR" 6 "10000001" "99999999" "50.00" 0 >/dev/null
s_orig_depois=$(parse_saldo "$(run_menu "$TDIR" 8 "10000001" 0)")
s_dest_depois=$(parse_saldo "$(run_menu "$TDIR" 8 "10000002" 0)")
assert_eq "origem intacta (destino inexistente)" "$saldo_antes" "$s_orig_depois"
assert_eq "destino intacto" "$s_dest_antes" "$s_dest_depois"

echo "--- integridade: reload preserva tudo ---"
run_menu "$TDIR" 4 "10000002" "123.45" 0 >/dev/null
s1=$(parse_saldo "$(run_menu "$TDIR" 8 "10000001" 0)")
s2=$(parse_saldo "$(run_menu "$TDIR" 8 "10000002" 0)")
# "reinicia o sistema": novo processo, mesmos arquivos
s1r=$(parse_saldo "$(run_menu "$TDIR" 8 "10000001" 0)")
s2r=$(parse_saldo "$(run_menu "$TDIR" 8 "10000002" 0)")
assert_eq "saldo conta 1 sobrevive ao restart" "$s1" "$s1r"
assert_eq "saldo conta 2 sobrevive ao restart" "$s2" "$s2r"
n_mov=$(wc -l < "$TDIR/movimentos.dat")
assert_eq "journal tem 2 linhas" "2" "$n_mov"

echo "--- integridade: checkpoint detecta anomalia no journal ---"
echo "000000099;2026-01-01 00:00:00;DEPOSITO;10000001;;0000000000100;TX-FAKE;fake" >> "$TDIR/movimentos.dat"
out=$(run_menu "$TDIR" 8 "10000001" 0)
assert_contains "detecta journal alem do checkpoint" "Journal alem do checkpoint" "$out"
head -1 "$TDIR/movimentos.dat" > "$TDIR/m.tmp" && mv "$TDIR/m.tmp" "$TDIR/movimentos.dat"
out=$(run_menu "$TDIR" 8 "10000001" 0)
assert_contains "detecta journal menor que checkpoint" "Journal menor que o checkpoint" "$out"

print_summary "integridade"

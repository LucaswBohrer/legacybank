#!/bin/bash
# test_funcional.sh - testes funcionais do LEGACYBANK (menu interativo)
set -u
cd "$(dirname "$0")/.."
source tests/lib.sh

LB_BIN=./bin/legacybank
LB_INIT=./bin/lb-init
TDIR=$(mktemp -d)
trap 'rm -rf "$TDIR"' EXIT

echo "--- funcionais: cadastro e operacoes ---"
$LB_INIT "$TDIR" >/dev/null

out=$(run_menu "$TDIR" 1 "Ana Silva" "123.456.789-00" "ana@email.com" 0)
assert_contains "cadastra cliente" "ID do cliente: C000001" "$out"

out=$(run_menu "$TDIR" 3 "C000001" "CC" 3 "C000001" "CP" 0)
assert_contains "abre conta 1" "Numero da conta: 10000001" "$out"
assert_contains "abre conta 2" "Numero da conta: 10000002" "$out"

out=$(run_menu "$TDIR" 4 "10000001" "1000.00" 8 "10000001" 0)
assert_contains "deposito ok" "OK: Deposito efetuado." "$out"
assert_eq "saldo apos deposito" "1000.00" "$(parse_saldo "$out")"

out=$(run_menu "$TDIR" 5 "10000001" "100.00" 8 "10000001" 0)
assert_contains "saque ok" "OK: Saque efetuado." "$out"
assert_eq "saldo apos saque (+tarifa 1.50)" "898.50" "$(parse_saldo "$out")"

out=$(run_menu "$TDIR" 6 "10000001" "10000002" "200.00" 8 "10000001" 8 "10000002" 0)
assert_contains "transferencia ok" "OK: Transferencia efetuada." "$out"
saldos=$(printf '%s' "$out" | grep -oE 'Saldo: R\$ [0-9.,-]+')
s1=$(printf '%s' "$saldos" | sed -n '1p' | sed 's/Saldo: R\$ //; s/\.//g; s/,/./')
s2=$(printf '%s' "$saldos" | sed -n '2p' | sed 's/Saldo: R\$ //; s/\.//g; s/,/./')
assert_eq "origem apos transferencia (+tarifa 2.00)" "696.50" "$s1"
assert_eq "destino apos transferencia" "200.00" "$s2"

echo "--- funcionais: rejeicoes ---"
out=$(run_menu "$TDIR" 4 "99999999" "10.00" 0)
assert_contains "deposito conta inexistente" "ERRO (01): Conta inexistente." "$out"

out=$(run_menu "$TDIR" 4 "10000001" "0" 0)
assert_contains "deposito valor zero" "ERRO (05): Valor invalido" "$out"

out=$(run_menu "$TDIR" 5 "10000002" "99999.99" 0)
assert_contains "saque saldo insuficiente" "ERRO (04): Saldo insuficiente." "$out"

out=$(run_menu "$TDIR" 6 "10000001" "10000001" "10.00" 0)
assert_contains "transferencia origem=destino" "ERRO (11): Origem e destino" "$out"

out=$(run_menu "$TDIR" 11 "10000001" 4 "10000001" "10.00" 12 "10000001" 0)
assert_contains "bloqueio ok" "OK: Conta bloqueada." "$out"
assert_contains "deposito conta bloqueada" "ERRO (02): Conta bloqueada." "$out"
assert_contains "desbloqueio ok" "OK: Conta desbloqueada." "$out"

out=$(run_menu "$TDIR" 7 "10000001" 0)
assert_contains "extrato tem deposito" "DEPOSITO       +R\$ 1.000,00" "$out"
assert_contains "extrato tem tarifa saque" "TARIFA         -R\$ 1,50" "$out"
assert_contains "extrato saldo atual" "Saldo atual:    R\$ 696,50" "$out"

out=$(run_menu "$TDIR" 14 0)
assert_contains "relatorio soma saldos" "Soma dos saldos: R\$ 896,50" "$out"
assert_contains "relatorio tarifas" "Tarifas cobradas (0000002): R\$ 3,50" "$out"

print_summary "funcionais"

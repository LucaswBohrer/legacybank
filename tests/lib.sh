#!/bin/bash
# lib.sh - helpers de assercao para a suite de testes do LEGACYBANK
# Uso: source "$(dirname "$0")/lib.sh"

PASS=0
FAIL=0
FAILED_CASES=""

assert_eq() {
    # assert_eq "descricao" "esperado" "obtido"
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        FAILED_CASES="${FAILED_CASES}\n[FALHOU] $desc\n  esperado: $expected\n  obtido:   $actual"
        echo "FALHOU: $desc (esperado='$expected' obtido='$actual')"
    fi
}

assert_contains() {
    # assert_contains "descricao" "agulha" "palheiro"
    local desc="$1" needle="$2" haystack="$3"
    if printf '%s' "$haystack" | grep -qF "$needle"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        FAILED_CASES="${FAILED_CASES}\n[FALHOU] $desc\n  nao encontrou: $needle"
        echo "FALHOU: $desc (nao encontrou '$needle')"
    fi
}

# Extrai o valor do saldo da saida do menu ("Saldo: R$ 1.043,00" -> "1043.00")
parse_saldo() {
    printf '%s' "$1" | grep -oE 'Saldo: R\$ [0-9.,-]+' | head -1 \
        | sed 's/Saldo: R\$ //; s/\.//g; s/,/./'
}

run_menu() {
    # run_menu <dir-dados> <opcao> [entrada...]
    local dir="$1"; shift
    printf '%s\n' "$@" | "$LB_BIN" "$dir" 2>&1
}

print_summary() {
    # print_summary "nome-da-suite"
    echo ""
    echo "== $1: $PASS passaram, $FAIL falharam =="
    if [ -n "$FAILED_CASES" ]; then
        printf '%b\n' "$FAILED_CASES"
    fi
    return $FAIL
}

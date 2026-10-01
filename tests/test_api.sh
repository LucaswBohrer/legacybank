#!/bin/bash
# test_api.sh — suíte da camada HTTP/REST (TESTE 4, Fases C–H).
# Uso: ./tests/test_api.sh
# Não toca nos dados reais: usa diretório temporário próprio.

set -u
cd "$(dirname "$0")/.." || exit 1
REPO="$PWD"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); }
bad()  { FAIL=$((FAIL+1)); echo "FALHOU: $1"; }

D=/tmp/lbapi-test-$$
PORT=8137
BASE="http://127.0.0.1:$PORT/api/v1"
export LB_BIN="$REPO/bin/legacybank"
# shellcheck disable=SC1091
source tests/lib.sh

setup() {
    rm -rf "$D"
    ./bin/lb-init "$D" >/dev/null || return 1
    run_menu "$D" 1 "Api User" "12345678901" "a@a.com" \
             3 "C000001" "CC" 3 "C000001" "CP" 0 >/dev/null || return 1
    LBAPI_DATA_DIR="$D" LBAPI_PORT="$PORT" \
        nohup python3 api/lbapi.py >"$D-api.log" 2>&1 &
    API_PID=$!
    for _ in $(seq 1 30); do
        curl -s -o /dev/null "$BASE/health" 2>/dev/null && return 0
        sleep 0.5
    done
    echo "API nao subiu"; tail -5 "$D-api.log"; return 1
}

teardown() {
    kill "$API_PID" 2>/dev/null
    wait "$API_PID" 2>/dev/null
    rm -rf "$D" "$D-api.log"
}

jget() { python3 -c "import json,sys; print(json.load(sys.stdin)$1)"; }

assert_eq() { # esperado obtido rotulo
    if [ "$1" = "$2" ]; then ok; else bad "$3 (esperado=$1 obtido=$2)"; fi
}

# ---------------------------------------------------------- contrato
test_health() {
    local b c
    b=$(curl -s "$BASE/health"); c=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/health")
    assert_eq 200 "$c" "health status"
    assert_eq ok "$(echo "$b" | jget "['api']")" "health api"
    assert_eq ok "$(echo "$b" | jget "['core']")" "health core"
}

test_deposit_flow() {
    local r c
    r=$(curl -s -w '\n%{http_code}' -X POST "$BASE/transactions/deposit" \
        -d '{"tx_id":"T-DEP-1","account":"10000001","amount":"1000.00"}')
    c=$(echo "$r" | tail -1); r=$(echo "$r" | head -1)
    assert_eq 201 "$c" "deposit status"
    assert_eq accepted "$(echo "$r" | jget "['status']")" "deposit status body"
    assert_eq 0 "$(echo "$r" | jget "['rc']")" "deposit rc"

    # saldo via API
    r=$(curl -s "$BASE/accounts/10000001")
    assert_eq 100000 "$(echo "$r" | jget "['balance_cents']")" "saldo apos deposito"
    assert_eq "1000.00" "$(echo "$r" | jget "['balance']")" "saldo formatado"
}

test_withdraw_fees() {
    curl -s -X POST "$BASE/transactions/withdraw" \
        -d '{"tx_id":"T-SAQ-1","account":"10000001","amount":"200.00"}' >/dev/null
    local r
    r=$(curl -s "$BASE/accounts/10000001")
    # 1000.00 - 200.00 - 1.50 (tarifa do core)
    assert_eq 79850 "$(echo "$r" | jget "['balance_cents']")" "saque+tarifa"
}

test_transfer_fees() {
    curl -s -X POST "$BASE/transactions/transfer" \
        -d '{"tx_id":"T-TRF-1","from_account":"10000001","to_account":"10000002","amount":"300.00"}' >/dev/null
    local a b
    a=$(curl -s "$BASE/accounts/10000001" | jget "['balance_cents']")
    b=$(curl -s "$BASE/accounts/10000002" | jget "['balance_cents']")
    # A: 798.50 - 300.00 - 2.00 = 496.50 ; B: 300.00
    assert_eq 49650 "$a" "transfer origem+tarifa"
    assert_eq 30000 "$b" "transfer destino"
}

test_reversal() {
    local r c
    r=$(curl -s -w '\n%{http_code}' -X POST "$BASE/transactions/reversal" \
        -d '{"tx_id":"T-REV-1","original_tx_id":"T-TRF-1"}')
    c=$(echo "$r" | tail -1)
    assert_eq 201 "$c" "reversal status"
    local a b
    a=$(curl -s "$BASE/accounts/10000001" | jget "['balance_cents']")
    b=$(curl -s "$BASE/accounts/10000002" | jget "['balance_cents']")
    assert_eq 79850 "$a" "estorno origem"
    assert_eq 0 "$b" "estorno destino"
}

test_statement() {
    local r n cur
    r=$(curl -s "$BASE/accounts/10000001/statement")
    n=$(echo "$r" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['movements']))")
    cur=$(echo "$r" | jget "['current_balance_cents']")
    # deposito, saque, tarifa, transferencia, tarifa, estorno-credito...
    # (o estorno gera movimentos; apenas checa consistencia)
    [ "$n" -ge 5 ] && ok || bad "statement tem movimentos (n=$n)"
    assert_eq 79850 "$cur" "statement current == saldo"
    # running balance do ultimo == current
    local last
    last=$(echo "$r" | jget "['movements'][-1]['running_balance_cents']")
    assert_eq "$cur" "$last" "running balance final"
}

test_tx_lookup() {
    local r c
    r=$(curl -s "$BASE/transactions/T-DEP-1")
    assert_eq OK "$(echo "$r" | jget "['result']")" "tx lookup result"
    c=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/transactions/INEXISTENTE")
    assert_eq 404 "$c" "tx inexistente 404"
}

# --------------------------------------------------------------- erros
test_errors() {
    local c
    c=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/transactions/withdraw" \
        -d '{"tx_id":"T-ERR-1","account":"10000001","amount":"99999.00"}')
    assert_eq 422 "$c" "saldo insuficiente 422"

    c=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/transactions/deposit" \
        -d '{"tx_id":"T-ERR-2","account":"99999999","amount":"10.00"}')
    assert_eq 422 "$c" "conta inexistente 422"

    c=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/transactions/deposit" \
        -d '{"tx_id":"T-ERR-3","account":"10000001","amount":"10.5"}')
    assert_eq 400 "$c" "amount 1 decimal 400"

    c=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/transactions/deposit" \
        -d '{"tx_id":"T-ERR-4","account":"10000001","amount":10.5}')
    assert_eq 400 "$c" "amount float 400"

    c=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/transactions/deposit" \
        -d '{"tx_id":"T-ERR-5","account":"10000001","amount":"-5.00"}')
    assert_eq 400 "$c" "amount negativo 400"

    c=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/transactions/deposit" \
        -d 'nao json')
    assert_eq 400 "$c" "json invalido 400"

    c=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/accounts/123")
    assert_eq 400 "$c" "conta malformada 400"

    c=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/naoexiste")
    assert_eq 404 "$c" "rota inexistente 404"

    c=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/accounts/99999999")
    assert_eq 404 "$c" "conta inexistente GET 404"
}

# ------------------------------------------------------- idempotencia
test_idempotency() {
    local r1 r2 c1 c2
    r1=$(curl -s -w '\n%{http_code}' -X POST "$BASE/transactions/deposit" \
        -d '{"tx_id":"T-IDEM-1","account":"10000001","amount":"50.00"}')
    c1=$(echo "$r1" | tail -1)
    r2=$(curl -s -w '\n%{http_code}' -X POST "$BASE/transactions/deposit" \
        -d '{"tx_id":"T-IDEM-1","account":"10000001","amount":"50.00"}')
    c2=$(echo "$r2" | tail -1); r2=$(echo "$r2" | head -1)
    assert_eq 201 "$c1" "primeira execucao 201"
    assert_eq 200 "$c2" "replay 200"
    assert_eq True "$(echo "$r2" | jget "['replay']")" "replay flag"
    local bal
    bal=$(curl -s "$BASE/accounts/10000001" | jget "['balance_cents']")
    # 79850 + 5000 (uma unica vez)
    assert_eq 84850 "$bal" "idempotencia: credito unico"
}

test_idempotency_restart() {
    kill "$API_PID"; wait "$API_PID" 2>/dev/null
    LBAPI_DATA_DIR="$D" LBAPI_PORT="$PORT" \
        nohup python3 api/lbapi.py >"$D-api.log" 2>&1 &
    API_PID=$!
    for _ in $(seq 1 30); do
        curl -s -o /dev/null "$BASE/health" 2>/dev/null && break
        sleep 0.5
    done
    local r c
    r=$(curl -s -w '\n%{http_code}' -X POST "$BASE/transactions/deposit" \
        -d '{"tx_id":"T-IDEM-1","account":"10000001","amount":"50.00"}')
    c=$(echo "$r" | tail -1); r=$(echo "$r" | head -1)
    assert_eq 200 "$c" "replay apos restart 200"
    assert_eq True "$(echo "$r" | jget "['replay']")" "replay flag apos restart"
}

# ------------------------------------------------------ concorrencia
test_concurrency() {
    local n=30 base
    base=$(curl -s "$BASE/accounts/10000002" | jget "['balance_cents']")
    seq 1 $n | xargs -P $n -I{} \
        curl -s -o /dev/null -X POST "$BASE/transactions/deposit" \
        -d "{\"tx_id\":\"T-CONC-{}\",\"account\":\"10000002\",\"amount\":\"10.00\"}"
    local bal esperado
    bal=$(curl -s "$BASE/accounts/10000002" | jget "['balance_cents']")
    esperado=$((base + n * 1000))
    assert_eq "$esperado" "$bal" "concorrencia $n depositos"
}

# --------------------------------------------- reconciliacao independente
test_reconcile() {
    # Saldo via CLI (opcao 8) deve bater com o da API
    local via_cli via_api
    via_cli=$(printf '8\n10000001\n0\n' | "$LB_BIN" "$D" 2>/dev/null \
        | grep -o 'Saldo: R\$ [0-9.,]*' | head -1 | sed 's/.*R\$ //;s/\.//g;s/,/./')
    via_api=$(curl -s "$BASE/accounts/10000001" | jget "['balance']")
    assert_eq "$via_cli" "$via_api" "reconciliacao CLI x API"
}

# ---------------------------------------------------------------- main
setup || { echo "setup falhou"; exit 1; }
trap teardown EXIT
test_health
test_deposit_flow
test_withdraw_fees
test_transfer_fees
test_reversal
test_statement
test_tx_lookup
test_errors
test_idempotency
test_idempotency_restart
test_concurrency
test_reconcile

echo ""
echo "=========================================="
echo "API: $PASS passaram, $FAIL falharam"
echo "=========================================="
[ "$FAIL" -eq 0 ]

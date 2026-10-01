#!/bin/bash
# test_api.sh — suíte da camada HTTP/REST (TESTE 4, Fases C–H).
# Uso: ./tests/test_api.sh
# Não toca nos dados reais: usa diretório temporário próprio.
#
# Portabilidade (D31): usa tests/httpc.py (stdlib Python) em vez de
# curl, que pode não existir no Windows/MSYS2. O diretório de teste
# é relativo ao repo: o MSYS2 não converte variáveis de ambiente
# (só argv), então um caminho absoluto estilo /tmp divergiria entre
# o .exe COBOL e o Python nativo.

set -u
cd "$(dirname "$0")/.." || exit 1
REPO="$PWD"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); }
bad()  { FAIL=$((FAIL+1)); echo "FALHOU: $1"; }

D=./test-tmp-lbapi-$$
PORT=8137
BASE="http://127.0.0.1:$PORT/api/v1"
export LB_BIN="$REPO/bin/legacybank"
# shellcheck disable=SC1091
source tests/lib.sh
HTTPC="$REPO/tests/httpc.py"
export HTTPC

# hget/hpost/hcode: wrappers finos sobre httpc.py (mesma semântica
# do curl usado antes: corpo, corpo+\n+código, só código).
hget()  { "$PYBIN" "$HTTPC" GET "$1"; }
hpost() { "$PYBIN" "$HTTPC" POST "$1" "$2"; }
hcode() { "$PYBIN" "$HTTPC" --code "$@"; }
hbcode(){ "$PYBIN" "$HTTPC" --body-code "$@"; }

setup() {
    rm -rf "$D"
    ./bin/lb-init "$D" >/dev/null || return 1
    run_menu "$D" 1 "Api User" "12345678901" "a@a.com" \
             3 "C000001" "CC" 3 "C000001" "CP" 0 >/dev/null || return 1
    LBAPI_DATA_DIR="$D" LBAPI_PORT="$PORT" \
        nohup "$PYBIN" api/lbapi.py >"$D-api.log" 2>&1 &
    API_PID=$!
    for _ in $(seq 1 30); do
        hget "$BASE/health" >/dev/null 2>&1 && return 0
        sleep 0.5
    done
    echo "API nao subiu"; tail -5 "$D-api.log"; return 1
}

teardown() {
    kill "$API_PID" 2>/dev/null
    wait "$API_PID" 2>/dev/null
    rm -rf "$D" "$D-api.log"
}

jget() { "$PYBIN" -c "import json,sys; print(json.load(sys.stdin)$1)"; }

assert_eq() { # esperado obtido rotulo
    if [ "$1" = "$2" ]; then ok; else bad "$3 (esperado=$1 obtido=$2)"; fi
}

# ---------------------------------------------------------- contrato
test_health() {
    local b c
    b=$(hget "$BASE/health"); c=$(hcode GET "$BASE/health")
    assert_eq 200 "$c" "health status"
    assert_eq ok "$(echo "$b" | jget "['api']")" "health api"
    assert_eq ok "$(echo "$b" | jget "['core']")" "health core"
}

test_deposit_flow() {
    local r c
    r=$(hbcode POST "$BASE/transactions/deposit" \
        '{"tx_id":"T-DEP-1","account":"10000001","amount":"1000.00"}')
    c=$(echo "$r" | tail -1); r=$(echo "$r" | head -1)
    assert_eq 201 "$c" "deposit status"
    assert_eq accepted "$(echo "$r" | jget "['status']")" "deposit status body"
    assert_eq 0 "$(echo "$r" | jget "['rc']")" "deposit rc"

    # saldo via API
    r=$(hget "$BASE/accounts/10000001")
    assert_eq 100000 "$(echo "$r" | jget "['balance_cents']")" "saldo apos deposito"
    assert_eq "1000.00" "$(echo "$r" | jget "['balance']")" "saldo formatado"
}

test_withdraw_fees() {
    hpost "$BASE/transactions/withdraw" \
        '{"tx_id":"T-SAQ-1","account":"10000001","amount":"200.00"}' >/dev/null
    local r
    r=$(hget "$BASE/accounts/10000001")
    # 1000.00 - 200.00 - 1.50 (tarifa do core)
    assert_eq 79850 "$(echo "$r" | jget "['balance_cents']")" "saque+tarifa"
}

test_transfer_fees() {
    hpost "$BASE/transactions/transfer" \
        '{"tx_id":"T-TRF-1","from_account":"10000001","to_account":"10000002","amount":"300.00"}' >/dev/null
    local a b
    a=$(hget "$BASE/accounts/10000001" | jget "['balance_cents']")
    b=$(hget "$BASE/accounts/10000002" | jget "['balance_cents']")
    # A: 798.50 - 300.00 - 2.00 = 496.50 ; B: 300.00
    assert_eq 49650 "$a" "transfer origem+tarifa"
    assert_eq 30000 "$b" "transfer destino"
}

test_reversal() {
    local r c
    r=$(hbcode POST "$BASE/transactions/reversal" \
        '{"tx_id":"T-REV-1","original_tx_id":"T-TRF-1"}')
    c=$(echo "$r" | tail -1)
    assert_eq 201 "$c" "reversal status"
    local a b
    a=$(hget "$BASE/accounts/10000001" | jget "['balance_cents']")
    b=$(hget "$BASE/accounts/10000002" | jget "['balance_cents']")
    assert_eq 79850 "$a" "estorno origem"
    assert_eq 0 "$b" "estorno destino"
}

test_statement() {
    local r n cur
    r=$(hget "$BASE/accounts/10000001/statement")
    n=$(echo "$r" | "$PYBIN" -c "import json,sys; print(len(json.load(sys.stdin)['movements']))")
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
    r=$(hget "$BASE/transactions/T-DEP-1")
    assert_eq OK "$(echo "$r" | jget "['result']")" "tx lookup result"
    c=$(hcode GET "$BASE/transactions/INEXISTENTE")
    assert_eq 404 "$c" "tx inexistente 404"
}

# --------------------------------------------------------------- erros
test_errors() {
    local c
    c=$(hcode POST "$BASE/transactions/withdraw" \
        '{"tx_id":"T-ERR-1","account":"10000001","amount":"99999.00"}')
    assert_eq 422 "$c" "saldo insuficiente 422"

    c=$(hcode POST "$BASE/transactions/deposit" \
        '{"tx_id":"T-ERR-2","account":"99999999","amount":"10.00"}')
    assert_eq 422 "$c" "conta inexistente 422"

    c=$(hcode POST "$BASE/transactions/deposit" \
        '{"tx_id":"T-ERR-3","account":"10000001","amount":"10.5"}')
    assert_eq 400 "$c" "amount 1 decimal 400"

    c=$(hcode POST "$BASE/transactions/deposit" \
        '{"tx_id":"T-ERR-4","account":"10000001","amount":10.5}')
    assert_eq 400 "$c" "amount float 400"

    c=$(hcode POST "$BASE/transactions/deposit" \
        '{"tx_id":"T-ERR-5","account":"10000001","amount":"-5.00"}')
    assert_eq 400 "$c" "amount negativo 400"

    c=$(hcode POST "$BASE/transactions/deposit" 'nao json')
    assert_eq 400 "$c" "json invalido 400"

    c=$(hcode GET "$BASE/accounts/123")
    assert_eq 400 "$c" "conta malformada 400"

    c=$(hcode GET "$BASE/naoexiste")
    assert_eq 404 "$c" "rota inexistente 404"

    c=$(hcode GET "$BASE/accounts/99999999")
    assert_eq 404 "$c" "conta inexistente GET 404"
}

# ------------------------------------------------------- idempotencia
test_idempotency() {
    local r1 r2 c1 c2
    r1=$(hbcode POST "$BASE/transactions/deposit" \
        '{"tx_id":"T-IDEM-1","account":"10000001","amount":"50.00"}')
    c1=$(echo "$r1" | tail -1)
    r2=$(hbcode POST "$BASE/transactions/deposit" \
        '{"tx_id":"T-IDEM-1","account":"10000001","amount":"50.00"}')
    c2=$(echo "$r2" | tail -1); r2=$(echo "$r2" | head -1)
    assert_eq 201 "$c1" "primeira execucao 201"
    assert_eq 200 "$c2" "replay 200"
    assert_eq True "$(echo "$r2" | jget "['replay']")" "replay flag"
    local bal
    bal=$(hget "$BASE/accounts/10000001" | jget "['balance_cents']")
    # 79850 + 5000 (uma unica vez)
    assert_eq 84850 "$bal" "idempotencia: credito unico"
}

test_idempotency_restart() {
    kill "$API_PID"; wait "$API_PID" 2>/dev/null
    LBAPI_DATA_DIR="$D" LBAPI_PORT="$PORT" \
        nohup "$PYBIN" api/lbapi.py >"$D-api.log" 2>&1 &
    API_PID=$!
    for _ in $(seq 1 30); do
        hget "$BASE/health" >/dev/null 2>&1 && break
        sleep 0.5
    done
    local r c
    r=$(hbcode POST "$BASE/transactions/deposit" \
        '{"tx_id":"T-IDEM-1","account":"10000001","amount":"50.00"}')
    c=$(echo "$r" | tail -1); r=$(echo "$r" | head -1)
    assert_eq 200 "$c" "replay apos restart 200"
    assert_eq True "$(echo "$r" | jget "['replay']")" "replay flag apos restart"
}

# ------------------------------------------------------ concorrencia
test_concurrency() {
    local n=30 base
    base=$(hget "$BASE/accounts/10000002" | jget "['balance_cents']")
    seq 1 $n | xargs -P $n -I{} \
        "$PYBIN" "$HTTPC" POST "$BASE/transactions/deposit" \
        "{\"tx_id\":\"T-CONC-{}\",\"account\":\"10000002\",\"amount\":\"10.00\"}" \
        >/dev/null
    local bal esperado
    bal=$(hget "$BASE/accounts/10000002" | jget "['balance_cents']")
    esperado=$((base + n * 1000))
    assert_eq "$esperado" "$bal" "concorrencia $n depositos"
}

# --------------------------------------------- reconciliacao independente
test_reconcile() {
    # Saldo via CLI (opcao 8) deve bater com o da API
    local via_cli via_api
    via_cli=$(printf '8\n10000001\n0\n' | "$LB_BIN" "$D" 2>/dev/null \
        | grep -o 'Saldo: R\$ [0-9.,]*' | head -1 | sed 's/.*R\$ //;s/\.//g;s/,/./')
    via_api=$(hget "$BASE/accounts/10000001" | jget "['balance']")
    assert_eq "$via_cli" "$via_api" "reconciliacao CLI x API"
}

# --------------------------------------------- TESTE 5: cadastros
test_customers() {
    local r c
    r=$(hget "$BASE/customers")
    assert_eq 1 "$(echo "$r" | jget "['count']")" "customers iniciais"

    r=$(hbcode POST "$BASE/customers" \
        '{"name":"Novo Cliente","cpf":"987.654.321-00","email":"novo@c.com"}')
    c=$(echo "$r" | tail -1); r=$(echo "$r" | head -1)
    assert_eq 201 "$c" "novo cliente 201"
    assert_eq C000002 "$(echo "$r" | jget "['id']")" "id sequencial"

    r=$(hget "$BASE/customers/C000002")
    assert_eq "Novo Cliente" "$(echo "$r" | jget "['name']")" "get cliente"

    c=$(hcode GET "$BASE/customers/C999999")
    assert_eq 404 "$c" "cliente inexistente 404"

    c=$(hcode POST "$BASE/customers" \
        '{"name":"X","cpf":"abc","email":"x@x.com"}')
    assert_eq 422 "$c" "cpf invalido 422 (regra do core)"

    c=$(hcode POST "$BASE/customers" \
        '{"name":"X;injection","cpf":"111.222.333-44","email":"x@x.com"}')
    assert_eq 400 "$c" "ponto-e-virgula 400 (envelope)"
}

test_accounts_crud() {
    local r c newacc
    r=$(hget "$BASE/accounts")
    assert_eq 2 "$(echo "$r" | jget "['count']")" "accounts iniciais"

    r=$(hbcode POST "$BASE/accounts" \
        '{"customer_id":"C000001","type":"CP"}')
    c=$(echo "$r" | tail -1); r=$(echo "$r" | head -1)
    assert_eq 201 "$c" "nova conta 201"
    newacc=$(echo "$r" | jget "['account']")
    assert_eq 10000003 "$newacc" "numero sequencial"

    c=$(hcode POST "$BASE/accounts" \
        '{"customer_id":"C999999","type":"CC"}')
    assert_eq 422 "$c" "cliente inexistente 422"

    c=$(hcode POST "$BASE/accounts" \
        '{"customer_id":"C000001","type":"XX"}')
    assert_eq 400 "$c" "tipo invalido 400"

    # bloqueio: saque rejeitado pelo core; depois desbloqueio
    c=$(hcode POST "$BASE/accounts/10000002/block" "")
    assert_eq 200 "$c" "bloqueio 200"
    c=$(hcode POST "$BASE/transactions/withdraw" \
        '{"tx_id":"T-BLK-1","account":"10000002","amount":"1.00"}')
    assert_eq 422 "$c" "saque em conta bloqueada 422"
    c=$(hcode POST "$BASE/accounts/10000002/unblock" "")
    assert_eq 200 "$c" "desbloqueio 200"

    c=$(hcode POST "$BASE/accounts/99999999/block" "")
    assert_eq 404 "$c" "bloqueio conta inexistente 404"

    # encerramento: com saldo o core rejeita; zerada encerra
    c=$(hcode POST "$BASE/accounts/10000002/close" "")
    assert_eq 422 "$c" "encerrar com saldo 422"
    c=$(hcode POST "$BASE/accounts/$newacc/close" "")
    assert_eq 200 "$c" "encerrar zerada 200"
    r=$(hget "$BASE/accounts?status=E")
    assert_eq 1 "$(echo "$r" | jget "['count']")" "filtro status=E"
    r=$(hget "$BASE/accounts?status=A")
    [ "$(echo "$r" | jget "['count']")" -ge 2 ] && ok || \
        bad "filtro status=A"
}

# --------------------------------------------- TESTE 5: leituras
test_dashboard() {
    local r
    r=$(hget "$BASE/dashboard")
    assert_eq 2 "$(echo "$r" | jget "['customers']")" "dashboard clientes"
    assert_eq 3 "$(echo "$r" | jget "['accounts']")" "dashboard contas"
    [ "$(echo "$r" | jget "['transactions']")" -ge 30 ] && ok || \
        bad "dashboard transacoes"
    [ "$(echo "$r" | jget "['total_balance_cents']")" -gt 0 ] && ok || \
        bad "dashboard saldo total"
    [ "$(echo "$r" | "$PYBIN" -c \
        "import json,sys; print(len(json.load(sys.stdin)['recent']))")" \
        -ge 1 ] && ok || bad "dashboard recentes"
}

test_transactions_list() {
    local r n
    r=$(hget "$BASE/transactions?limit=5")
    assert_eq 5 "$(echo "$r" | jget "['count']")" "transactions limit=5"
    r=$(hget "$BASE/transactions?account=10000002")
    n=$(echo "$r" | "$PYBIN" -c \
        "import json,sys; ds=json.load(sys.stdin)['transactions']; \
print(all(t['account']=='10000002' for t in ds))")
    assert_eq True "$n" "filtro por conta"
    r=$(hget "$BASE/transactions?result=REJEITADA")
    n=$(echo "$r" | "$PYBIN" -c \
        "import json,sys; ds=json.load(sys.stdin)['transactions']; \
print(all(t['result']=='REJEITADA' for t in ds))")
    assert_eq True "$n" "filtro por resultado"
}

test_audit() {
    local r
    r=$(hget "$BASE/audit?limit=3")
    assert_eq 3 "$(echo "$r" | jget "['count']")" "audit limit=3"
    r=$(hget "$BASE/audit?limit=500")
    [ "$(echo "$r" | jget "['count']")" -le 300 ] && ok || \
        bad "audit respeita teto de 300"
}

# --------------------------------------------- TESTE 5: lote via HTTP
test_batch() {
    local r c before after
    before=$(hget "$BASE/accounts/10000001" | jget "['balance_cents']")
    r=$(hbcode POST "$BASE/batch" \
        'DEPOSITO;TX-LOTE-1;10000001;25.00
LIXO;TX-LOTE-2
SAQUE;TX-LOTE-3;10000001;5.00')
    c=$(echo "$r" | tail -1); r=$(echo "$r" | head -1)
    assert_eq 200 "$c" "batch 200"
    assert_eq 2 "$(echo "$r" | jget "['accepted']")" "batch aceitas"
    assert_eq 1 "$(echo "$r" | jget "['invalid']")" "batch invalidas"
    assert_eq 1 "$(echo "$r" | "$PYBIN" -c \
        "import json,sys; print(len(json.load(sys.stdin)['errors']))")" \
        "batch erros listados"
    after=$(hget "$BASE/accounts/10000001" | jget "['balance_cents']")
    # 25.00 - 5.00 - 1.50 (tarifa do core)
    assert_eq $((before + 2500 - 500 - 150)) "$after" \
        "batch refletido no saldo"
    [ -z "$(ls "$D"/lote_web_* 2>/dev/null)" ] && ok || \
        bad "temporario do lote removido"
}

# ------------------------------------------------- auth demo (TESTE 5, adendo §8)
# Sobe uma segunda API com LBAPI_TOKEN definido e valida o 401.
test_auth() {
    local P2=8138
    local B2="http://127.0.0.1:$P2/api/v1"
    local LOG="$D-auth.log"
    LBAPI_DATA_DIR="$D" LBAPI_PORT="$P2" LBAPI_TOKEN="tok-teste-123" \
        LBAPI_DEMO_MODE=1 \
        nohup "$PYBIN" api/lbapi.py >"$LOG" 2>&1 &
    local pid=$!
    local ok_up=0
    for _ in $(seq 1 30); do
        hget "$B2/health" >/dev/null 2>&1 && { ok_up=1; break; }
        sleep 0.5
    done
    if [ "$ok_up" -eq 0 ]; then
        bad "API com token nao subiu"; tail -5 "$LOG"
        kill "$pid" 2>/dev/null; return
    fi
    # health sempre aberto, mesmo com token
    assert_eq 200 "$(hcode GET "$B2/health")" "health aberto com token"
    assert_eq "True" "$(hget "$B2/health" | jget "['demo']")" \
        "health expoe demo:true"
    assert_eq "ephemeral" "$(hget "$B2/health" | jget "['storage']")" \
        "health expoe storage:ephemeral"
    # sem token -> 401
    assert_eq 401 "$(hcode GET "$B2/dashboard")" \
        "dashboard sem token = 401"
    assert_eq 401 "$(hcode POST "$B2/customers" '{}')" \
        "POST sem token = 401"
    # token errado -> 401
    assert_eq 401 "$("$PYBIN" "$HTTPC" --code -H 'Authorization: Bearer errado' \
        GET "$B2/dashboard")" "token errado = 401"
    # token certo -> 200
    assert_eq 200 "$("$PYBIN" "$HTTPC" --code -H 'Authorization: Bearer tok-teste-123' \
        GET "$B2/dashboard")" "token certo = 200"
    local body
    body=$("$PYBIN" "$HTTPC" -H 'Authorization: Bearer tok-teste-123' \
        GET "$B2/dashboard")
    assert_eq "True" "$(echo "$body" | "$PYBIN" -c \
        "import json,sys; print('customers' in json.load(sys.stdin))")" \
        "dashboard autenticado retorna dados"
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; rm -f "$LOG"
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
test_customers
test_accounts_crud
test_dashboard
test_transactions_list
test_audit
test_batch
test_auth

echo ""
echo "=========================================="
echo "API: $PASS passaram, $FAIL falharam"
echo "=========================================="
[ "$FAIL" -eq 0 ]

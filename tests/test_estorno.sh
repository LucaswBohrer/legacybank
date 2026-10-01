#!/bin/bash
# test_estorno.sh - suíte do estorno de transações (TESTE 3).
#
# Cobre: estorno de depósito, saque e transferência (com devolução
# integral da tarifa, D21); segundo estorno (RC 14); original
# inexistente (RC 12); original rejeitada / estorno de estorno
# (RC 13); idempotência do TX-ID do estorno (imediata e após
# restart); saldo insuficiente na perna de débito (RC 4);
# atomicidade da transferência; vínculo original<->estorno no
# registry, journal e auditoria; batch misto; extrato e relatório.
set -u
cd "$(dirname "$0")/.."
source tests/lib.sh

LB_BIN=./bin/legacybank
LB_LOTE=./bin/lb-lote
LB_INIT=./bin/lb-init
TDIR=$(mktemp -d)
trap 'rm -rf "$TDIR"' EXIT

$LB_INIT "$TDIR" >/dev/null
run_menu "$TDIR" 1 "Estorno" "999.888.777-66" "e@e.com" \
    3 "C000001" "CC" 3 "C000001" "CC" 0 >/dev/null

saldo() { parse_saldo "$(run_menu "$TDIR" 8 "$1" 0)"; }
# saldo em centavos (inteiro, sem zeros a esquerda), para comparacao exata
saldo_c() { saldo "$1" | tr -d '.' | sed 's/^0*//; s/^$/0/'; }
lote() { $LB_LOTE "$TDIR" "$1" 2>&1; }

echo "--- estorno: deposito volta ao saldo anterior ---"
cat > "$TDIR/e01.txt" <<'EOF'
DEPOSITO;TX-E01;10000001;1000.00
EOF
out=$(lote "$TDIR/e01.txt")
assert_eq "saldo apos deposito" "100000" "$(saldo_c 10000001)"
cat > "$TDIR/e02.txt" <<'EOF'
ESTORNO;TX-E02;TX-E01
EOF
out=$(lote "$TDIR/e02.txt")
assert_contains "estorno de deposito ok" "0000001 ok" "$out"
assert_eq "saldo apos estorno de deposito" "0" "$(saldo_c 10000001)"
assert_contains "registry: estorno vinculado" \
    "OK;ESTORNO de TX-E01 DEPOSITO" "$(grep '^TX-E02;' "$TDIR/tx_registry.dat")"
assert_contains "registry: original carimbada" \
    ";ESTORNADA" "$(grep '^TX-E01;' "$TDIR/tx_registry.dat")"
assert_contains "auditoria: vinculo estorno_de" \
    "estorno_de=TX-E01" "$(cat "$TDIR/auditoria.log")"
assert_contains "journal: movimento ESTORNO" \
    ";ESTORNO;10000001;;" "$(cat "$TDIR/movimentos.dat")"

echo "--- estorno: segundo estorno da mesma original -> RC 14 ---"
cat > "$TDIR/e03.txt" <<'EOF'
ESTORNO;TX-E03;TX-E01
EOF
out=$(lote "$TDIR/e03.txt")
assert_contains "2o estorno rejeitado" "0000001 rejeitadas" "$out"
assert_contains "mensagem RC 14" "ja estornada" "$out"
assert_eq "saldo intacto apos 2o estorno" "0" "$(saldo_c 10000001)"

echo "--- estorno: saque devolve valor + tarifa ---"
cat > "$TDIR/s01.txt" <<'EOF'
DEPOSITO;TX-S00;10000001;1000.00
SAQUE;TX-S01;10000001;300.00
EOF
lote "$TDIR/s01.txt" >/dev/null
assert_eq "saldo apos saque (300+1.50)" "69850" "$(saldo_c 10000001)"
cat > "$TDIR/s02.txt" <<'EOF'
ESTORNO;TX-S02;TX-S01
EOF
out=$(lote "$TDIR/s02.txt")
assert_contains "estorno de saque ok" "0000001 ok" "$out"
assert_eq "saldo apos estorno de saque (volta a 1000)" "100000" "$(saldo_c 10000001)"
assert_contains "journal: estorno de saque inclui tarifa" \
    "Estorno de saque TX-S01 (inclui tarifa)" "$(cat "$TDIR/movimentos.dat")"
cat > "$TDIR/s03.txt" <<'EOF'
ESTORNO;TX-S03;TX-S01
EOF
out=$(lote "$TDIR/s03.txt")
assert_contains "2o estorno de saque rejeitado" "0000001 rejeitadas" "$out"
assert_eq "saldo intacto" "100000" "$(saldo_c 10000001)"

echo "--- estorno: transferencia eh atomica ---"
cat > "$TDIR/t01.txt" <<'EOF'
TRANSFERENCIA;TX-T01;10000001;10000002;200.00
EOF
lote "$TDIR/t01.txt" >/dev/null
assert_eq "origem apos transferencia" "79800" "$(saldo_c 10000001)"
assert_eq "destino apos transferencia" "20000" "$(saldo_c 10000002)"
cat > "$TDIR/t02.txt" <<'EOF'
ESTORNO;TX-T02;TX-T01
EOF
out=$(lote "$TDIR/t02.txt")
assert_contains "estorno de transferencia ok" "0000001 ok" "$out"
assert_eq "origem volta a 1000 (devolve 200+2)" "100000" "$(saldo_c 10000001)"
assert_eq "destino volta a 0" "0" "$(saldo_c 10000002)"
assert_contains "journal: perna do valor" \
    ";ESTORNO;10000002;10000001;" "$(cat "$TDIR/movimentos.dat")"
assert_contains "journal: perna da tarifa" \
    "Devolucao de tarifa TX-T01" "$(cat "$TDIR/movimentos.dat")"
cat > "$TDIR/t03.txt" <<'EOF'
ESTORNO;TX-T03;TX-T01
EOF
out=$(lote "$TDIR/t03.txt")
assert_contains "2o estorno de transferencia rejeitado" "0000001 rejeitadas" "$out"
assert_eq "origem intacta" "100000" "$(saldo_c 10000001)"
assert_eq "destino intacto" "0" "$(saldo_c 10000002)"

echo "--- estorno: original inexistente -> RC 12 ---"
cat > "$TDIR/x01.txt" <<'EOF'
ESTORNO;TX-X01;TX-NOTEXIST
EOF
out=$(lote "$TDIR/x01.txt")
assert_contains "original inexistente rejeitada" "0000001 rejeitadas" "$out"
assert_contains "mensagem RC 12" "nao encontrada" "$out"
assert_eq "saldo intacto" "100000" "$(saldo_c 10000001)"
assert_contains "rejeicao registrada no registry" \
    "TX-X01" "$(cat "$TDIR/tx_registry.dat")"

echo "--- estorno: original REJEITADA -> RC 13 ---"
cat > "$TDIR/r02.txt" <<'EOF'
SAQUE;TX-R03;10000001;999999.00
EOF
lote "$TDIR/r02.txt" >/dev/null
cat > "$TDIR/r03.txt" <<'EOF'
ESTORNO;TX-R04;TX-R03
EOF
out=$(lote "$TDIR/r03.txt")
assert_contains "estorno de rejeitada rejeitado" "0000001 rejeitadas" "$out"
assert_contains "mensagem RC 13" "nao pode ser estornada" "$out"
assert_eq "saldo intacto" "100000" "$(saldo_c 10000001)"

echo "--- estorno: estorno de estorno -> RC 13 ---"
cat > "$TDIR/ee01.txt" <<'EOF'
ESTORNO;TX-EE01;TX-E02
EOF
out=$(lote "$TDIR/ee01.txt")
assert_contains "estorno de estorno rejeitado" "0000001 rejeitadas" "$out"
assert_contains "mensagem RC 13 (estorno)" "nao pode ser estornada" "$out"
assert_eq "saldo intacto" "100000" "$(saldo_c 10000001)"

echo "--- estorno: idempotencia imediata do TX-ID do estorno ---"
cat > "$TDIR/d01.txt" <<'EOF'
ESTORNO;TX-D01;TX-S00
ESTORNO;TX-D01;TX-S00
EOF
out=$(lote "$TDIR/d01.txt")
assert_contains "1 ok" "0000001 ok" "$out"
assert_contains "1 duplicada" "0000001 duplicadas" "$out"
assert_eq "saldo apos 1 estorno (debita 1000)" "0" "$(saldo_c 10000001)"

echo "--- estorno: idempotencia apos restart (indice reconstruido) ---"
out=$(lote "$TDIR/d01.txt")
assert_contains "apos restart: 0 ok" "0000000 ok" "$out"
assert_contains "apos restart: 2 duplicadas" "0000002 duplicadas" "$out"
assert_eq "saldo intacto apos restart" "0" "$(saldo_c 10000001)"

echo "--- estorno: saldo insuficiente na perna de debito -> RC 4 ---"
cat > "$TDIR/f01.txt" <<'EOF'
DEPOSITO;TX-F01;10000001;500.00
SAQUE;TX-F02;10000001;400.00
EOF
lote "$TDIR/f01.txt" >/dev/null
assert_eq "saldo antes" "9850" "$(saldo_c 10000001)"
cat > "$TDIR/f02.txt" <<'EOF'
ESTORNO;TX-F03;TX-F01
EOF
out=$(lote "$TDIR/f02.txt")
assert_contains "estorno sem saldo rejeitado" "0000001 rejeitadas" "$out"
assert_contains "mensagem RC 4" "Saldo insuficiente" "$out"
assert_eq "saldo intacto (nada debitado)" "9850" "$(saldo_c 10000001)"
assert_contains "original NAO carimbada" \
    "TX-F01;" "$(grep '^TX-F01;' "$TDIR/tx_registry.dat" | grep -v ESTORNADA)"

echo "--- estorno: lote misto ---"
cat > "$TDIR/m01.txt" <<'EOF'
DEPOSITO;TX-M01;10000001;100.00
ESTORNO;TX-M02;TX-M01
ESTORNO;TX-M03;TX-NOTEXIST
ESTORNO;TX-M02;TX-M01
SAQUE;TX-M04;10000001;10.00
ESTORNO;TX-M05;TX-M04
EOF
out=$(lote "$TDIR/m01.txt")
assert_contains "misto: 4 ok" "0000004 ok" "$out"
assert_contains "misto: 1 rejeitada" "0000001 rejeitadas" "$out"
assert_contains "misto: 1 duplicada" "0000001 duplicadas" "$out"
# 9850 +100 -100 -10 -1.50 +10 +1.50 = 9850
assert_eq "saldo final do lote misto" "9850" "$(saldo_c 10000001)"

echo "--- estorno: extrato exibe movimentos ESTORNO ---"
out=$(run_menu "$TDIR" 7 "10000001" 0)
assert_contains "extrato tem ESTORNO" "ESTORNO" "$out"

echo "--- estorno: relatorio conta estornos ---"
out=$(run_menu "$TDIR" 14 0)
assert_contains "relatorio tem linha de estornos" "Estornos (" "$out"

echo "--- estorno: CLI opcao 15 ---"
cat > "$TDIR/c01.txt" <<'EOF'
DEPOSITO;TX-C01;10000001;50.00
EOF
lote "$TDIR/c01.txt" >/dev/null
antes=$(saldo_c 10000001)
out=$(run_menu "$TDIR" 15 "TX-C01" 0)
assert_contains "CLI: estorno efetuado" "Estorno efetuado" "$out"
assert_contains "CLI: exibe novo TX-ID" "Novo TX-ID (estorno):" "$out"
depois=$(saldo_c 10000001)
assert_eq "CLI: saldo debitado em 50.00" "$((antes - 5000))" "$depois"
out=$(run_menu "$TDIR" 15 "TX-C01" 0)
assert_contains "CLI: 2o estorno rejeitado" "ja estornada" "$out"

echo "--- estorno: formato antigo (sem valor=) via journal ---"
# Simula registry da baseline anterior: DETALHE sem "valor=".
# O journal continua estruturado e eh a fonte da verdade.
# Os 3 estornos tem efeito liquido zero: saldos voltam ao snapshot.
A0=$(saldo_c 10000001); B0=$(saldo_c 10000002)
cat > "$TDIR/g01.txt" <<'EOF'
DEPOSITO;TX-G01;10000001;500.00
SAQUE;TX-G02;10000001;100.00
TRANSFERENCIA;TX-G03;10000001;10000002;50.00
EOF
lote "$TDIR/g01.txt" >/dev/null
python3 - "$TDIR/tx_registry.dat" <<'PY'
import re, sys
p = sys.argv[1]
out = []
for l in open(p).read().splitlines():
    m = re.match(r'^(TX-G0[123]);([^;]+);OK;(.*)$', l)
    if m:
        tid, dt, _ = m.groups()
        det = {'TX-G01': 'DEPOSITO 500.00', 'TX-G02': 'SAQUE 100.00',
               'TX-G03': 'TRANSFERENCIA 50.00'}[tid]
        l = f'{tid};{dt};OK;{det}'
    out.append(l)
open(p, 'w').write('\n'.join(out) + '\n')
PY
# A=346.50 B=50.00 -> apos estornos: A=0 B=0
cat > "$TDIR/g02.txt" <<'EOF'
ESTORNO;TX-G11;TX-G03
ESTORNO;TX-G12;TX-G02
ESTORNO;TX-G13;TX-G01
EOF
out=$(lote "$TDIR/g02.txt")
assert_contains "legado: 3 ok" "0000003 ok" "$out"
assert_eq "legado: conta A volta ao snapshot" "$A0" "$(saldo_c 10000001)"
assert_eq "legado: conta B volta ao snapshot" "$B0" "$(saldo_c 10000002)"
assert_contains "legado: original carimbada" \
    ";ESTORNADA" "$(grep '^TX-G01;' "$TDIR/tx_registry.dat")"
# restart: indice e carimbo persistem
out=$(run_menu "$TDIR" 15 "TX-G01" 0)
assert_contains "legado: 2o estorno rejeitado apos restart" "ja estornada" "$out"

print_summary "test_estorno"

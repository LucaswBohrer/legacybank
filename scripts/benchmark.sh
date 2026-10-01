#!/bin/bash
# Benchmark de carga do LEGACYBANK.
# Uso: ./scripts/benchmark.sh <arquivo-lote> <rotulo> [dir-dados]
# Exemplo: ./scripts/benchmark.sh /tmp/lote100k.txt baseline
#
# Fluxo identico ao benchmark v1.0: init, cliente, 2 contas (CC/CP),
# deposito inicial de R$ 1.000.000,00, lote via lb-lote.
# Ao final imprime: tempo real, contadores do lote, saldos e
# tamanhos dos arquivos, e salva tudo em /tmp/bench-<rotulo>.txt
set -u
LOTE="${1:?informe o arquivo de lote}"
ROTULO="${2:?informe o rotulo}"
DADOS="${3:-/tmp/bench-$ROTULO}"
BIN=./bin

rm -rf "$DADOS"
"$BIN/lb-init" "$DADOS" >/dev/null
"$BIN/legacybank" "$DADOS" >/dev/null <<'EOF'
1
Bench Carga
11111111111
bench@carga.teste
3
C000001
CC
3
C000001
CP
4
10000001
1000000.00
0
EOF

INICIO=$(date +%s.%N)
OUT=$("$BIN/lb-lote" "$DADOS" "$LOTE" 2>&1)
RC=$?
FIM=$(date +%s.%N)
TEMPO=$(awk -v a="$INICIO" -v b="$FIM" 'BEGIN{printf "%.3f", b-a}')

{
echo "=== BENCHMARK LEGACYBANK [$ROTULO] ==="
echo "lote: $LOTE ($(wc -l < "$LOTE") linhas)"
echo "tempo_real_s: $TEMPO"
echo "rc_lb_lote: $RC"
echo "--- saida lb-lote ---"
echo "$OUT"
echo "--- saldos finais ---"
awk -F';' '{print $1": "$5}' "$DADOS/contas.dat"
echo "--- arquivos ---"
wc -l "$DADOS"/movimentos.dat "$DADOS"/tx_registry.dat "$DADOS"/auditoria.log
} | tee "/tmp/bench-$ROTULO.txt"

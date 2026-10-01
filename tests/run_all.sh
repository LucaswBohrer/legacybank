#!/bin/bash
# run_all.sh - executa toda a suite de testes do LEGACYBANK
set -u
cd "$(dirname "$0")/.."

if [ ! -x ./bin/legacybank ] || [ ! -x ./bin/lb-lote ] || [ ! -x ./bin/lb-init ] || [ ! -x ./bin/lb-api ]; then
    echo "Binarios nao encontrados. Rode ./scripts/build.sh primeiro."
    exit 2
fi

TOTAL_FAIL=0
for t in tests/test_funcional.sh tests/test_integridade.sh tests/test_batch.sh tests/test_indice.sh tests/test_estorno.sh tests/test_api.sh tests/test_portabilidade.sh; do
    echo ""
    echo "########## $t ##########"
    bash "$t"
    rc=$?
    TOTAL_FAIL=$((TOTAL_FAIL + rc))
done

if [ "${1:-}" = "--carga" ]; then
    echo ""
    echo "########## tests/test_carga.sh ##########"
    bash tests/test_carga.sh
    rc=$?
    TOTAL_FAIL=$((TOTAL_FAIL + rc))
else
    echo ""
    echo "(teste de carga pulado; rode com --carga para incluir 100k transacoes)"
fi

echo ""
if [ "$TOTAL_FAIL" -eq 0 ]; then
    echo "=========================================="
    echo "TODOS OS TESTES PASSARAM"
    echo "=========================================="
else
    echo "=========================================="
    echo "FALHAS TOTAIS: $TOTAL_FAIL"
    echo "=========================================="
fi
exit $TOTAL_FAIL

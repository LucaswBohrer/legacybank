#!/bin/bash
# build.sh - compila todos os executaveis do LEGACYBANK
# Uso: ./scripts/build.sh
set -e
cd "$(dirname "$0")/.."

COBFLAGS="-I src"
mkdir -p bin

echo "== LEGACYBANK build =="
echo "[1/3] legacybank (menu interativo)..."
cobc -x $COBFLAGS -o bin/legacybank \
    src/legacybank.cbl \
    src/lb-dados.cbl \
    src/lb-financ.cbl \
    src/lb-cad.cbl \
    src/lb-consulta.cbl

echo "[2/3] lb-lote (processador batch)..."
cobc -x $COBFLAGS -o bin/lb-lote \
    src/lb-lote.cbl \
    src/lb-dados.cbl \
    src/lb-financ.cbl \
    src/lb-cad.cbl \
    src/lb-consulta.cbl

echo "[3/3] lb-init (inicializador)..."
cobc -x $COBFLAGS -o bin/lb-init \
    src/lb-init.cbl \
    src/lb-dados.cbl

echo "OK: bin/legacybank, bin/lb-lote, bin/lb-init"

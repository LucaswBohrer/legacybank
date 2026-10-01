#!/bin/sh
# Entrypoint do container LEGACYBANK.
# - garante o diretorio de dados e inicializa os 6 arquivos (lb-init);
# - respeita $PORT (Render/Heroku) com fallback para LBAPI_PORT/8123;
# - inicia a API servindo tambem o frontend estatico.
set -e

DATA_DIR="${LBAPI_DATA_DIR:-/data}"
PORT="${PORT:-${LBAPI_PORT:-8123}}"
export LBAPI_PORT="$PORT"

mkdir -p "$DATA_DIR"
/app/bin/lb-init "$DATA_DIR" >/dev/null 2>&1 || /app/bin/lb-init "$DATA_DIR"

echo "[legacybank] data=$DATA_DIR port=$PORT"
exec python3 /app/api/lbapi.py

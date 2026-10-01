#!/bin/bash
# dev-web.sh — sobe API + frontend em modo desenvolvimento.
# API: 127.0.0.1:8123 (api/lbapi.py) | Frontend: http://localhost:5173 (Vite, proxy /api)
set -e
cd "$(dirname "$0")/.."

DATA_DIR="${LBAPI_DATA_DIR:-./data}"
PORT="${LBAPI_PORT:-8123}"

if [ ! -d "$DATA_DIR" ]; then
  echo "[dev-web] inicializando dados em $DATA_DIR..."
  ./bin/lb-init "$DATA_DIR" >/dev/null
fi

# API em background (se já não estiver rodando)
if ! curl -sf "http://127.0.0.1:$PORT/api/v1/health" >/dev/null 2>&1; then
  echo "[dev-web] subindo API em 127.0.0.1:$PORT..."
  LBAPI_DATA_DIR="$DATA_DIR" LBAPI_PORT="$PORT" python3 api/lbapi.py &
  API_PID=$!
  trap "kill $API_PID 2>/dev/null" EXIT
  sleep 1
else
  echo "[dev-web] API já rodando em 127.0.0.1:$PORT"
fi

echo "[dev-web] subindo Vite em http://localhost:5173 ..."
cd web && npm run dev

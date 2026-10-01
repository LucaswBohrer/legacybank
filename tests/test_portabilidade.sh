#!/bin/bash
# test_portabilidade.sh — testes de portabilidade Windows/MSYS2 (D29-D31).
#
# Cobre, rodando no Linux, exatamente os trechos alterados para
# portabilidade (sem regressao do comportamento Unix):
#   - lb-init sem shell: mkdir -p via CBL_CREATE_DIR/CBL_CHECK_FILE_EXIST
#     (aninhado, idempotente, trailing slash, backslash, caminho relativo)
#   - fluxo fim-a-fim num diretorio aninhado (init -> CLI -> driver)
#   - api/lbapi.py: _resolve_bin (ramo .exe) e _bin_executable
#
# Convencao de asserts: a do tests/lib.sh —
#   assert_eq "descricao" "esperado" "obtido"
#   assert_contains "descricao" "agulha" "palheiro"
#
# O ramo Windows de verdade (rename com destino existente, cmd.exe)
# so e exercitavel no Windows; aqui garante-se que o caminho feliz
# do Linux ficou bit-a-bit igual.
# Uso: ./tests/test_portabilidade.sh

set -u
cd "$(dirname "$0")/.." || exit 1
REPO="$PWD"
LB_BIN="$REPO/bin/legacybank"
export LB_BIN
# shellcheck disable=SC1091
source tests/lib.sh

T=./test-tmp-port-$$

cleanup() { rm -rf "$T"; }
trap cleanup EXIT

t_init_nested() {
    ./bin/lb-init "$T/n1/n2/n3" >/dev/null
    assert_eq "init aninhado rc" "0" "$?"
    assert_eq "init aninhado cria niveis" "sim" \
        "$([ -d "$T/n1/n2/n3" ] && echo sim || echo nao)"
}

t_init_idempotente() {
    ./bin/lb-init "$T/n1/n2/n3" >/dev/null
    assert_eq "init repetido rc (mkdir -p nao falha)" "0" "$?"
}

t_init_trailing_slash() {
    ./bin/lb-init "$T/ts/" >/dev/null
    assert_eq "init trailing slash rc" "0" "$?"
    assert_eq "init trailing slash cria dir" "sim" \
        "$([ -d "$T/ts" ] && echo sim || echo nao)"
}

t_init_backslash() {
    ./bin/lb-init "$T\win\sub" >/dev/null
    assert_eq "init backslash rc" "0" "$?"
    assert_eq "init backslash normaliza para /" "sim" \
        "$([ -d "$T/win/sub" ] && echo sim || echo nao)"
}

t_init_relativo() {
    ./bin/lb-init "$T/rel" >/dev/null
    assert_eq "init relativo rc" "0" "$?"
    assert_eq "init relativo cria dir" "sim" \
        "$([ -d "$T/rel" ] && echo sim || echo nao)"
}

t_e2e_nested() {
    local D="$T/n1/n2/n3" out saldo
    run_menu "$D" 1 "Port User" "12345678901" "p@p.com" \
             3 "C000001" "CC" 0 >/dev/null
    out=$("./bin/lb-api" "$D" DEPOSIT TX-PORT1 10000001 25000 2>&1)
    assert_contains "deposito via driver RC 00" "RC: 00" "$out"
    saldo=$(parse_saldo "$(run_menu "$D" 8 10000001 0)")
    assert_eq "saldo fim-a-fim em dir aninhado" "250.00" "$saldo"
}

t_init_cria_arquivos() {
    local D="$T/files" f ok_todos=1
    ./bin/lb-init "$D" >/dev/null
    for f in clientes.dat contas.dat movimentos.dat tx_registry.dat \
             sequencia.dat auditoria.log; do
        [ -f "$D/$f" ] || { ok_todos=0; break; }
    done
    assert_eq "init cria os 6 arquivos" "1" "$ok_todos"
}

t_init_nao_trunca() {
    local D="$T/files" saldo
    run_menu "$D" 1 "Port User" "12345678901" "p@p.com" \
             3 "C000001" "CC" 0 >/dev/null
    "./bin/lb-api" "$D" DEPOSIT TX-PORT2 10000001 77700 >/dev/null 2>&1
    ./bin/lb-init "$D" >/dev/null
    assert_eq "re-init rc" "0" "$?"
    saldo=$(parse_saldo "$(run_menu "$D" 8 10000001 0)")
    assert_eq "re-init nao trunca a base" "777.00" "$saldo"
}

t_resolve_bin() {
    local td="$T/fakebin" r l1 l2 l3
    mkdir -p "$td"
    touch "$td/lb-api.exe"
    chmod +x "$td/lb-api.exe"
    r=$("$PYBIN" - "$td" <<'PY'
# Simula Windows sem tocar no modulo os global: troca apenas o nome
# `os` dentro do namespace do lbapi por um stub com name="nt".
# (Atribuir os.name="nt" de verdade quebra imports do stdlib, pois
# http.server -> shutil tentaria `import nt`.)
import sys, types
sys.path.insert(0, "api")
import lbapi
import os as real_os
stub = types.SimpleNamespace(name="nt", path=real_os.path,
                             access=real_os.access, environ=real_os.environ)
lbapi.os = stub
base = sys.argv[1] + "/lb-api"
print(lbapi._resolve_bin(base))                    # so .exe existe
print(lbapi._resolve_bin(base + ".exe"))           # .exe direto
print(lbapi._resolve_bin(sys.argv[1] + "/ausente"))# nenhum existe
PY
)
    l1=$(echo "$r" | sed -n '1p'); l2=$(echo "$r" | sed -n '2p')
    l3=$(echo "$r" | sed -n '3p')
    assert_eq "resolve_bin: acha .exe" "$td/lb-api.exe" "$l1"
    assert_eq "resolve_bin: .exe direto" "$td/lb-api.exe" "$l2"
    assert_eq "resolve_bin: sem candidato mantem base" "$td/ausente" "$l3"
}

t_bin_executable() {
    local td="$T/fakebin" r l1 l2
    r=$("$PYBIN" - "$td/lb-api.exe" "$td/ausente" <<'PY'
import sys
sys.path.insert(0, "api")
import lbapi
print(lbapi._bin_executable(sys.argv[1]))
print(lbapi._bin_executable(sys.argv[2]))
PY
)
    l1=$(echo "$r" | sed -n '1p'); l2=$(echo "$r" | sed -n '2p')
    assert_eq "bin_executable: existente+x" "True" "$l1"
    assert_eq "bin_executable: ausente" "False" "$l2"
}

t_init_nested
t_init_idempotente
t_init_trailing_slash
t_init_backslash
t_init_relativo
t_e2e_nested
t_init_cria_arquivos
t_init_nao_trunca
t_resolve_bin
t_bin_executable

print_summary "test_portabilidade.sh"
[ "$FAIL" -eq 0 ]

#!/usr/bin/env python3
"""httpc.py - cliente HTTP minimo (somente stdlib) para a suite de testes.

Substitui o `curl` em tests/test_api.sh: no Windows/MSYS2 o curl pode
nao estar instalado, mas o Python (requisito da propria API) sempre
esta. Semantica espelhada do curl usado nos testes:

    httpc.py GET url                 -> corpo em stdout (exit 0;
                                        exit 1 se falhar a conexao)
    httpc.py --code GET url          -> somente o status HTTP
    httpc.py --body-code POST url -d '{...}'
                                     -> corpo, "\\n", status
                                        (como curl -w '\\n%{http_code}')

Status de erro HTTP (4xx/5xx) ainda imprime corpo/codigo com exit 0,
como `curl -s` faz; so falha de conexao retorna exit != 0.
"""

import http.client
import sys
import urllib.parse

TIMEOUT = 30


def main(argv):
    mode = "body"
    if argv and argv[0] in ("--code", "--body-code"):
        mode = argv[0][2:]
        argv = argv[1:]
    if len(argv) < 2:
        sys.stderr.write("uso: httpc.py [--code|--body-code] METODO URL [DADOS]\n")
        return 2
    method, url = argv[0].upper(), argv[1]
    data = argv[2] if len(argv) > 2 else None

    p = urllib.parse.urlparse(url)
    if p.scheme not in ("http", "https"):
        sys.stderr.write("httpc.py: esquema nao suportado\n")
        return 2
    conn_cls = (http.client.HTTPSConnection if p.scheme == "https"
                else http.client.HTTPConnection)
    host = p.hostname
    port = p.port or (443 if p.scheme == "https" else 80)
    path = p.path or "/"
    if p.query:
        path += "?" + p.query

    body = data.encode("utf-8") if data is not None else None
    headers = {}
    if body is not None:
        headers["Content-Type"] = "application/json"
        headers["Content-Length"] = str(len(body))
    try:
        conn = conn_cls(host, port, timeout=TIMEOUT)
        conn.request(method, path, body=body, headers=headers)
        resp = conn.getresponse()
        payload = resp.read()
        code = resp.status
    except (OSError, http.client.HTTPException) as e:
        sys.stderr.write(f"httpc.py: falha de conexao: {e}\n")
        return 1

    out = sys.stdout.buffer
    if mode in ("body", "body-code"):
        out.write(payload)
    if mode == "body-code":
        out.write(b"\n")
    if mode in ("code", "body-code"):
        out.write(str(code).encode("ascii"))
    out.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

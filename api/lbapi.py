#!/usr/bin/env python3
"""
LEGACYBANK API — camada de integracao HTTP sobre o core COBOL (D25).

Arquitetura:
    HTTP Client -> esta API (Python stdlib) -> bin/lb-api (subprocesso)
                                              -> core COBOL (fonte de verdade)

A API NAO implementa regra financeira. Ela valida o envelope HTTP,
converte valores para centavos inteiros, despacha para o driver COBOL
via argv (sem shell) e traduz o resultado para JSON.

Idempotencia: usa o TX-ID do core (tx_registry persistido). Nenhum
estado financeiro vive nesta camada; restart da API nao perde nada.

Concorrencia: todas as invocacoes ao core sao serializadas por um lock
global (D28), pois o core e single-user sem file locking (L01).

Dinheiro: nunca float. O campo `amount` e string decimal ("100.50");
a conversao para centavos usa Decimal.

Uso:
    LBAPI_DATA_DIR=./data LBAPI_PORT=8123 python3 api/lbapi.py
"""

import json
import logging
import os
import re
import subprocess
import tempfile
import threading
import time
from decimal import Decimal, InvalidOperation
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

VERSION = "1.1.0"
API_PREFIX = "/api/v1"

# ---------------------------------------------------------------- config

DATA_DIR = os.environ.get("LBAPI_DATA_DIR", "./data")
# Render/Heroku injetam $PORT; LBAPI_PORT tem precedencia quando definido.
PORT = int(os.environ.get("LBAPI_PORT", os.environ.get("PORT", "8123")))
HOST = os.environ.get("LBAPI_HOST", "127.0.0.1")
TIMEOUT = float(os.environ.get("LBAPI_TIMEOUT", "30"))
# Auth demo-grade (§8 do adendo TESTE 5): quando definido e nao-vazio, todos
# os endpoints /api/v1/* exigem "Authorization: Bearer <token>" (exceto
# /api/v1/health, usado pelo health check da plataforma). Local: vazio = livre.
# NUNCA commitar o valor — ver .env.example e render.yaml (generateValue).
API_TOKEN = os.environ.get("LBAPI_TOKEN", "")
# Modo demo: 1 = health expoe demo:true/storage:ephemeral e a UI exibe o selo
# "DEMO ENVIRONMENT". Deploy gratuito usa 1 (filesystem efemero).
DEMO_MODE = os.environ.get("LBAPI_DEMO_MODE", "") == "1"
BIN = os.environ.get(
    "LBAPI_BIN",
    os.path.join(os.path.dirname(os.path.abspath(__file__)),
                 "..", "bin", "lb-api"),
)
BIN = os.path.normpath(BIN)
# Binario do processador batch (mesmo diretorio do driver).
LOTE_BIN = os.path.normpath(
    os.path.join(os.path.dirname(BIN), "lb-lote"))
# Frontend estatico (servido pela propria API no deploy Docker).
WEB_DIR = os.environ.get(
    "LBAPI_WEB_DIR",
    os.path.normpath(os.path.join(os.path.dirname(
        os.path.abspath(__file__)), "..", "web", "dist")),
)


def _resolve_bin(path):
    """Resolve o caminho do binario do core de forma portavel.

    No Windows o executavel gerado pelo cobc e `lb-api.exe`; o
    padrao `../bin/lb-api` (sem extensao) nao existiria como
    arquivo e a API reportaria core indisponivel (D31).
    """
    if os.path.isfile(path):
        return path
    if os.name == "nt":
        cand = path + ".exe"
        if os.path.isfile(cand):
            return cand
    return path


def _bin_executable(path):
    """No Windows nao ha bit executavel: existir basta. No Unix
    mantem a checagem X_OK original."""
    if not os.path.isfile(path):
        return False
    if os.name == "nt":
        return True
    return os.access(path, os.X_OK)


BIN = _resolve_bin(BIN)
LOTE_BIN = _resolve_bin(LOTE_BIN)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
log = logging.getLogger("lbapi")

# ------------------------------------------------------- erros do core

class CoreUnavailable(Exception):
    """Binario ausente, timeout, crash ou resposta ilegiveis."""


class CoreClient:
    """Invoca bin/lb-api como subprocesso. Um lock global serializa
    todas as chamadas (D28). Argumentos via lista (sem shell)."""

    _lock = threading.Lock()

    def __init__(self, bin_path=BIN, data_dir=DATA_DIR, timeout=TIMEOUT):
        self.bin = bin_path
        self.data_dir = data_dir
        self.timeout = timeout

    def call(self, op, *args):
        """Roda `lb-api <data_dir> <op> [args]` e devolve dict das
        linhas 'CHAVE: valor' do stdout. Levanta CoreUnavailable se o
        core nao respondeu de forma utilizavel."""
        if not _bin_executable(self.bin):
            raise CoreUnavailable(f"binario do core ausente: {self.bin}")
        if not os.path.isdir(self.data_dir):
            raise CoreUnavailable(
                f"diretorio de dados ausente: {self.data_dir}")
        cmd = [self.bin, self.data_dir, op] + [str(a) for a in args]
        with CoreClient._lock:
            t0 = time.monotonic()
            try:
                p = subprocess.run(
                    cmd, capture_output=True, text=True,
                    timeout=self.timeout)
            except subprocess.TimeoutExpired:
                raise CoreUnavailable(
                    f"timeout apos {self.timeout}s no core (op={op})")
            except OSError as e:
                raise CoreUnavailable(f"falha ao executar o core: {e}")
            dt_ms = int((time.monotonic() - t0) * 1000)
        out = self._parse(p.stdout)
        if "RC" not in out:
            # Driver nao produziu saida maquina-legivel: crash ou erro.
            err = (p.stderr or "").strip().splitlines()
            detail = err[-1] if err else f"exit={p.returncode}"
            raise CoreUnavailable(
                f"resposta invalida do core (op={op}): {detail}")
        out["_duration_ms"] = dt_ms
        out["_exit"] = p.returncode
        return out

    # Chaves que aparecem N vezes -> sempre lista (mesmo com 1 item).
    LIST_KEYS = {"STMT-MOV", "CLI-REC", "CTA-REC", "TXR-REC",
                 "AUD-REC", "DB-RECENT"}

    @staticmethod
    def _parse(stdout):
        res = {}
        for line in stdout.splitlines():
            if ":" not in line:
                continue
            k, v = line.split(":", 1)
            k = k.strip()
            if not k or not re.fullmatch(r"[A-Z0-9_.-]+", k):
                continue
            v = v.strip()
            if k in CoreClient.LIST_KEYS:
                res.setdefault(k, []).append(v)
            elif k not in res:
                res[k] = v
            # Duplicata inesperada de chave escalar: mantem a primeira.
        return res


core = CoreClient()

# ------------------------------------------------------------- validacao

RE_TXID = re.compile(r"^[A-Za-z0-9_-]{1,24}$")
RE_ACCOUNT = re.compile(r"^\d{8}$")
# "123" ou "123.45" (ate 11 digitos inteiros = limite do PIC 9(13))
RE_AMOUNT = re.compile(r"^\d{1,11}(\.\d{2})?$")
MAX_CENTS = 9_999_999_999_999  # PIC 9(13)


def parse_amount(s):
    """'100.50' -> 10050 (int). Levanta ValueError se invalido.
    Nunca usa float."""
    if not isinstance(s, str) or not RE_AMOUNT.fullmatch(s):
        raise ValueError(
            "amount deve ser string decimal como \"100.50\" ou \"100\"")
    try:
        cents = int(Decimal(s) * 100)
    except InvalidOperation:
        raise ValueError("amount invalido")
    if cents <= 0:
        raise ValueError("amount deve ser maior que zero")
    if cents > MAX_CENTS:
        raise ValueError("amount excede o limite suportado")
    return cents


def check_txid(s):
    if not isinstance(s, str) or not RE_TXID.fullmatch(s):
        raise ValueError(
            "tx_id deve ter 1-24 caracteres [A-Za-z0-9_-]")
    return s


def check_account(s):
    if not isinstance(s, str) or not RE_ACCOUNT.fullmatch(s):
        raise ValueError("account deve ter 8 digitos")
    return s


# ';' e ':' sao separadores do protocolo do driver; controles/quebras
# de linha quebrariam o argv. A API so valida o envelope: o conteudo
# (CPF, e-mail, tipo) e validado pelo core (RC -> 422).
RE_BAD_FIELD = re.compile(r'[;:\x00-\x1f\x7f]')
RE_CUSTOMER_ID = re.compile(r'^C\d{6}$')


def check_field(value, label, max_len):
    if not isinstance(value, str):
        raise ValueError("%s deve ser string" % label)
    value = value.strip()
    if not value or len(value) > max_len:
        raise ValueError(
            "%s invalido (1-%d caracteres)" % (label, max_len))
    if RE_BAD_FIELD.search(value):
        raise ValueError("%s contem caractere proibido" % label)
    return value


def check_customer_id(s):
    s = check_field(s, "customer_id", 7)
    if not RE_CUSTOMER_ID.fullmatch(s):
        raise ValueError("customer_id deve ser 'C' + 6 digitos")
    return s


def parse_customer_line(line):
    """'ID;NOME;CPF;EMAIL;DATA;STATUS'."""
    parts = line.split(";")
    keys = ("id", "name", "cpf", "email", "opened", "status")
    return dict(zip(keys, parts))


def parse_account_list_line(line):
    """'NUMERO;CLIENTE-ID;TIPO;STATUS;SALDO;DATA'."""
    parts = line.split(";")
    keys = ("account", "customer_id", "type", "status",
            "balance_cents", "opened")
    return dict(zip(keys, parts))


RE_TX_ACCT = re.compile(r"conta=(\d{8})")
RE_TX_VALUE = re.compile(r"valor=(\d{1,13})")
RE_TX_FEE = re.compile(r"tarifa=(\d{1,13})")


def parse_tx_list_line(line):
    """'TX-ID;DATAHORA;RESULTADO;DETALHE...' (detalhe pode conter ';').

    O detalhe e texto livre do core; aqui so extraimos campos para
    exibicao (tipo/conta/valor/tarifa). Nenhuma regra financeira."""
    parts = line.split(";", 3)
    keys = ("tx_id", "timestamp", "result", "detail")
    d = dict(zip(keys, parts))
    detail = d.get("detail", "")
    d["kind"] = detail.split(" ", 1)[0] if detail else ""
    m = RE_TX_ACCT.search(detail)
    d["account"] = m.group(1) if m else None
    m = RE_TX_VALUE.search(detail)
    d["value_cents"] = int(m.group(1)) if m else None
    m = RE_TX_FEE.search(detail)
    d["fee_cents"] = int(m.group(1)) if m else None
    return d


def parse_audit_line(line):
    """'DATAHORA | EVENTO'."""
    ts, sep, event = line.partition(" | ")
    if sep:
        return {"timestamp": ts.strip(), "event": event.strip()}
    return {"timestamp": "", "event": line.strip()}


def parse_journal_line(line):
    """Linha bruta do journal: SEQ;DATAHORA;TIPO;CONTA;DEST;VALOR;TX;DESC."""
    parts = line.split(";", 7)
    keys = ("seq", "timestamp", "type", "account", "dest_account",
            "value_cents", "tx_id", "description")
    return dict(zip(keys, parts))


def parse_dashboard(r):
    """Agregados 'DB-*' vindos do driver."""
    def gi(k):
        try:
            return int(str(r.get(k, "0")).strip())
        except (ValueError, TypeError):
            return 0
    return {
        "customers": gi("DB-CLIENTS"),
        "accounts": gi("DB-ACCOUNTS"),
        "accounts_active": gi("DB-ACCOUNTS-A"),
        "accounts_blocked": gi("DB-ACCOUNTS-B"),
        "accounts_closed": gi("DB-ACCOUNTS-E"),
        "total_balance_cents": gi("DB-TOTAL-CENTS"),
        "transactions": gi("DB-TXS"),
        "movements": gi("DB-MOVS"),
        "recent": [parse_journal_line(v)
                   for v in r.get("DB-RECENT", [])],
    }


def rc_int(r):
    """Extrai RC como int, tolerando '00'/'0' do COBOL."""
    try:
        return int(str(r.get("RC", "")).strip())
    except (ValueError, TypeError):
        return -1


def cents_to_str(c):
    c = int(c)
    neg = "-" if c < 0 else ""
    c = abs(c)
    return f"{neg}{c // 100}.{c % 100:02d}"


# ------------------------------------------------------- mapeamento RC

# RCs que significam rejeicao semantica do core -> HTTP 422
RC_REJECT = {1, 2, 3, 4, 5, 11, 12, 13, 14}


def tx_lookup(tx_id):
    """Consulta o registry; devolve dict ou None se inexistente."""
    try:
        r = core.call("TX", tx_id)
    except CoreUnavailable:
        return None
    if rc_int(r) != 0:
        return None
    return {
        "tx_id": r.get("TX-ID", tx_id),
        "timestamp": r.get("TX-DATAHORA"),
        "result": r.get("TX-RESULTADO"),
        "detail": r.get("TX-DETALHE"),
    }


# ----------------------------------------------------------------- HTTP

class Handler(BaseHTTPRequestHandler):
    server_version = "LBAPI/" + VERSION

    # -- utilidades -------------------------------------------------
    def _send(self, status, obj):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _err(self, status, code, message, **extra):
        self._send(status, {"error": code, "message": message, **extra})

    def _check_auth(self, path, t0):
        """Auth demo-grade: 401 se LBAPI_TOKEN definido e Bearer ausente/invalido.

        /api/v1/health fica sempre aberto (health check da plataforma).
        Retorna True se autorizado (ou auth desabilitada), False se negado
        (ja respondeu 401).
        """
        if not API_TOKEN:
            return True
        if path == f"{API_PREFIX}/health":
            return True
        auth = self.headers.get("Authorization", "")
        if auth == f"Bearer {API_TOKEN}":
            return True
        self._api_log(t0, None, "unauthorized", "-", 401)
        self._err(401, "unauthorized",
                  "token de acesso demo ausente ou invalido "
                  "(header Authorization: Bearer <LBAPI_TOKEN>)")
        return False

    def _body(self):
        try:
            n = int(self.headers.get("Content-Length", 0))
        except ValueError:
            n = 0
        if n <= 0 or n > 1_000_000:
            return None
        try:
            return json.loads(self.rfile.read(n).decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            return None

    def _raw_body(self, max_bytes=1_000_000):
        """Corpo como texto UTF-8 (endpoint de lote)."""
        try:
            n = int(self.headers.get("Content-Length", 0))
        except ValueError:
            n = 0
        if n <= 0 or n > max_bytes:
            return None
        data = self.rfile.read(n)
        if b"\x00" in data:
            return None
        try:
            return data.decode("utf-8")
        except UnicodeDecodeError:
            return None

    def log_message(self, fmt, *args):  # silencia o log padrao
        pass

    def _api_log(self, t0, tx_id, op, rc, http):
        dt = int((time.monotonic() - t0) * 1000)
        log.info("method=%s path=%s tx_id=%s op=%s duration_ms=%d rc=%s http=%d",
                 self.command, urlparse(self.path).path,
                 tx_id or "-", op, dt, rc, http)

    # -- roteamento -------------------------------------------------
    def do_GET(self):
        t0 = time.monotonic()
        u = urlparse(self.path)
        path = u.path
        try:
            if path == f"{API_PREFIX}/health":
                self._health(t0)
            elif path.startswith(f"{API_PREFIX}/") or path == API_PREFIX:
                if not self._check_auth(path, t0):
                    return
                self._route_get(path, u, t0)
            elif self._serve_static(path):
                self._api_log(t0, None, "static", "-", 200)
            else:
                self._api_log(t0, None, "not_found", "-", 404)
                self._err(404, "not_found", "recurso inexistente")
        except CoreUnavailable as e:
            self._api_log(t0, None, "core", "-", 503)
            self._err(503, "core_unavailable", str(e))
        except Exception as e:  # noqa: BLE001 - nunca vazar stack
            log.exception("erro interno")
            self._api_log(t0, None, "internal", "-", 500)
            self._err(500, "internal_error", "erro interno")

    def _route_get(self, path, u, t0):
        """Rotas GET autenticadas (o health check ja foi tratado antes)."""
        try:
            if path == f"{API_PREFIX}/dashboard":
                self._dashboard(t0)
            elif path == f"{API_PREFIX}/customers":
                self._customers(t0)
            elif (m := re.fullmatch(
                    rf"{API_PREFIX}/customers/(C\d+)", path)):
                self._customer_one(m.group(1), t0)
            elif path == f"{API_PREFIX}/accounts":
                self._accounts(t0, parse_qs(u.query))
            elif (m := re.fullmatch(
                    rf"{API_PREFIX}/accounts/(\d+)/statement", path)):
                self._statement(m.group(1), t0)
            elif (m := re.fullmatch(
                    rf"{API_PREFIX}/accounts/(\d+)", path)):
                self._account(m.group(1), t0)
            elif path == f"{API_PREFIX}/transactions":
                self._transactions(t0, parse_qs(u.query))
            elif (m := re.fullmatch(
                    rf"{API_PREFIX}/transactions/([A-Za-z0-9_-]+)", path)):
                self._tx_get(m.group(1), t0)
            elif path == f"{API_PREFIX}/audit":
                self._audit(t0, parse_qs(u.query))
            else:
                self._api_log(t0, None, "not_found", "-", 404)
                self._err(404, "not_found", "recurso inexistente")
        except CoreUnavailable as e:
            self._api_log(t0, None, "core", "-", 503)
            self._err(503, "core_unavailable", str(e))
        except Exception as e:  # noqa: BLE001 - nunca vazar stack
            log.exception("erro interno")
            self._api_log(t0, None, "internal", "-", 500)
            self._err(500, "internal_error", "erro interno")

    def do_POST(self):
        t0 = time.monotonic()
        path = urlparse(self.path).path
        if path.startswith(f"{API_PREFIX}/"):
            if not self._check_auth(path, t0):
                return
        try:
            routes = {
                f"{API_PREFIX}/transactions/deposit": ("deposit", self._deposit),
                f"{API_PREFIX}/transactions/withdraw": ("withdraw", self._withdraw),
                f"{API_PREFIX}/transactions/transfer": ("transfer", self._transfer),
                f"{API_PREFIX}/transactions/reversal": ("reversal", self._reversal),
                f"{API_PREFIX}/customers": ("new_customer", self._new_customer),
                f"{API_PREFIX}/accounts": ("new_account", self._new_account),
                f"{API_PREFIX}/batch": ("batch", self._batch),
            }
            if path in routes:
                op, fn = routes[path]
                fn(t0, op)
            elif (m := re.fullmatch(
                    rf"{API_PREFIX}/accounts/(\d+)/(block|unblock|close)",
                    path)):
                self._account_status(m.group(1), m.group(2), t0)
            else:
                self._api_log(t0, None, "not_found", "-", 404)
                self._err(404, "not_found", "recurso inexistente")
        except CoreUnavailable as e:
            self._api_log(t0, None, "core", "-", 503)
            self._err(503, "core_unavailable", str(e))
        except Exception:  # noqa: BLE001
            log.exception("erro interno")
            self._api_log(t0, None, "internal", "-", 500)
            self._err(500, "internal_error", "erro interno")

    # -- endpoints --------------------------------------------------
    def _health(self, t0):
        """Distingue API ok / core ok / core indisponivel."""
        try:
            r = core.call("BALANCE", "00000000")
            # Qualquer RC maquina-legivel prova que o core executou.
            core_st = "ok"
            detail = {"rc": r.get("RC")}
        except CoreUnavailable as e:
            core_st = "unavailable"
            detail = {"reason": str(e)}
        st = 200 if core_st == "ok" else 503
        self._api_log(t0, None, "health", "-", st)
        self._send(st, {"api": "ok", "core": core_st,
                        "version": VERSION,
                        "demo": DEMO_MODE,
                        "storage": "ephemeral" if DEMO_MODE else "local",
                        **detail})

    def _account(self, acc, t0):
        try:
            check_account(acc)
        except ValueError as e:
            self._api_log(t0, None, "account", "-", 400)
            self._err(400, "invalid_account", str(e))
            return
        r = core.call("ACCOUNT", acc)
        if rc_int(r) != 0:
            self._api_log(t0, None, "account", r.get("RC"), 404)
            self._err(404, "account_not_found", "conta inexistente")
            return
        bal = int(r["CTA-SALDO"])
        self._api_log(t0, None, "account", "0", 200)
        self._send(200, {
            "account": r.get("CTA-NUMERO", acc),
            "type": r.get("CTA-TIPO"),
            "status": r.get("CTA-STATUS"),
            "balance_cents": bal,
            "balance": cents_to_str(bal),
        })

    def _statement(self, acc, t0):
        try:
            check_account(acc)
        except ValueError as e:
            self._api_log(t0, None, "statement", "-", 400)
            self._err(400, "invalid_account", str(e))
            return
        r = core.call("STATEMENT", acc)
        if "STMT-ERROR" in r:
            self._api_log(t0, None, "statement", "-", 404)
            self._err(404, "account_not_found", "conta inexistente")
            return
        movs = []
        for m in r.get("STMT-MOV", []):
            parts = m.split(";")
            if len(parts) != 5:
                continue
            ts, tipo, efeito, corrido, tx = parts
            movs.append({
                "timestamp": ts, "type": tipo,
                "effect_cents": int(efeito),
                "effect": cents_to_str(int(efeito)),
                "running_balance_cents": int(corrido),
                "running_balance": cents_to_str(int(corrido)),
                "tx_id": tx,
            })
        opening = int(r.get("STMT-OPENING", "0"))
        current = int(r.get("STMT-CURRENT", "0"))
        self._api_log(t0, None, "statement", "0", 200)
        self._send(200, {
            "account": r.get("STMT-ACCOUNT", acc),
            "opening_balance_cents": opening,
            "opening_balance": cents_to_str(opening),
            "movements": movs,
            "current_balance_cents": current,
            "current_balance": cents_to_str(current),
        })

    def _tx_get(self, tx_id, t0):
        try:
            check_txid(tx_id)
        except ValueError as e:
            self._api_log(t0, None, "tx", "-", 400)
            self._err(400, "invalid_tx_id", str(e))
            return
        info = tx_lookup(tx_id)
        if info is None:
            self._api_log(t0, tx_id, "tx", "-", 404)
            self._err(404, "transaction_not_found",
                      "transacao inexistente", tx_id=tx_id)
            return
        self._api_log(t0, tx_id, "tx", "0", 200)
        self._send(200, {"tx_id": info["tx_id"],
                         "timestamp": info["timestamp"],
                         "result": info["result"],
                         "detail": info["detail"]})

    # -- listagens / dashboard / auditoria (TESTE 5) -----------------
    def _list_call(self, op, *args):
        """Chama operacao de leitura do driver; 503 se o core falhar."""
        r = core.call(op, *args)
        if rc_int(r) != 0:
            raise CoreUnavailable(
                "resposta invalida do core (op=%s)" % op)
        return r

    def _dashboard(self, t0):
        r = self._list_call("DASHBOARD")
        d = parse_dashboard(r)
        d["total_balance"] = cents_to_str(d["total_balance_cents"])
        for mv in d["recent"]:
            try:
                c = int(mv.get("value_cents") or 0)
            except (ValueError, TypeError):
                c = 0
            mv["value"] = cents_to_str(c)
        self._api_log(t0, None, "dashboard", "0", 200)
        self._send(200, d)

    def _customers(self, t0):
        r = self._list_call("LIST-CLIENTS")
        items = [parse_customer_line(v)
                 for v in r.get("CLI-REC", [])]
        self._api_log(t0, None, "customers", "0", 200)
        self._send(200, {"customers": items, "count": len(items)})

    def _customer_one(self, cid, t0):
        try:
            check_customer_id(cid)
        except ValueError as e:
            self._api_log(t0, None, "customer", "-", 400)
            self._err(400, "invalid_customer_id", str(e))
            return
        r = self._list_call("LIST-CLIENTS")
        for v in r.get("CLI-REC", []):
            c = parse_customer_line(v)
            if c.get("id") == cid:
                self._api_log(t0, None, "customer", "0", 200)
                self._send(200, c)
                return
        self._api_log(t0, None, "customer", "-", 404)
        self._err(404, "customer_not_found", "cliente inexistente")

    def _accounts(self, t0, qs):
        status = (qs.get("status") or [""])[0].upper()
        if status and status not in ("A", "B", "E"):
            self._api_log(t0, None, "accounts", "-", 400)
            self._err(400, "invalid_status",
                      "status deve ser A, B ou E")
            return
        cust = (qs.get("customer_id") or [""])[0]
        if cust:
            try:
                check_customer_id(cust)
            except ValueError as e:
                self._api_log(t0, None, "accounts", "-", 400)
                self._err(400, "invalid_customer_id", str(e))
                return
        r = self._list_call("LIST-ACCOUNTS")
        items = []
        for v in r.get("CTA-REC", []):
            a = parse_account_list_line(v)
            if status and a.get("status") != status:
                continue
            if cust and a.get("customer_id") != cust:
                continue
            try:
                bal = int(a.get("balance_cents") or 0)
            except (ValueError, TypeError):
                bal = 0
            a["balance_cents"] = bal
            a["balance"] = cents_to_str(bal)
            items.append(a)
        self._api_log(t0, None, "accounts", "0", 200)
        self._send(200, {"accounts": items, "count": len(items)})

    def _transactions(self, t0, qs):
        try:
            limit = int((qs.get("limit") or ["200"])[0])
        except ValueError:
            limit = 200
        limit = max(1, min(limit, 1000))
        acct = (qs.get("account") or [""])[0]
        if acct:
            try:
                check_account(acct)
            except ValueError as e:
                self._api_log(t0, None, "transactions", "-", 400)
                self._err(400, "invalid_account", str(e))
                return
        result = (qs.get("result") or [""])[0].upper()
        if result and result not in ("OK", "REJEITADA", "DUPLICADA"):
            self._api_log(t0, None, "transactions", "-", 400)
            self._err(400, "invalid_result",
                      "result deve ser OK, REJEITADA ou DUPLICADA")
            return
        q = (qs.get("q") or [""])[0].strip()
        r = self._list_call("LIST-TXS")
        items = []
        for v in r.get("TXR-REC", []):
            t = parse_tx_list_line(v)
            if acct and t.get("account") != acct:
                continue
            if result and t.get("result") != result:
                continue
            if q and q.lower() not in (
                    (t.get("tx_id") or "") + " " +
                    (t.get("detail") or "")).lower():
                continue
            items.append(t)
        items = items[-limit:]
        items.reverse()
        self._api_log(t0, None, "transactions", "0", 200)
        self._send(200, {"transactions": items, "count": len(items)})

    def _audit(self, t0, qs):
        try:
            limit = int((qs.get("limit") or ["100"])[0])
        except ValueError:
            limit = 100
        limit = max(1, min(limit, 300))
        r = self._list_call("LIST-AUDIT", str(limit))
        items = [parse_audit_line(v) for v in r.get("AUD-REC", [])]
        self._api_log(t0, None, "audit", "0", 200)
        self._send(200, {"events": items, "count": len(items)})

    # -- cadastros e status de conta (TESTE 5) ------------------------
    def _new_customer(self, t0, op):
        b = self._body()
        if b is None:
            self._api_log(t0, None, op, "-", 400)
            self._err(400, "invalid_json", "corpo JSON invalido")
            return
        try:
            name = check_field(b.get("name"), "name", 60)
            cpf = check_field(b.get("cpf"), "cpf", 14)
            email = check_field(b.get("email"), "email", 60)
        except (ValueError, AttributeError) as e:
            self._api_log(t0, None, op, "-", 400)
            self._err(400, "invalid_payload", str(e))
            return
        r = core.call("NEW-CLIENT", name, cpf, email)
        rc = rc_int(r)
        msg = r.get("MSG", "")
        if rc == 0:
            self._api_log(t0, None, op, rc, 201)
            self._send(201, {"id": r.get("CLI-ID"),
                             "status": "created", "rc": rc,
                             "rc_message": msg})
        elif rc in (5, 8):
            self._api_log(t0, None, op, rc, 422)
            self._err(422, "customer_rejected", msg, rc=rc)
        else:
            self._api_log(t0, None, op, rc, 500)
            self._err(500, "unexpected_rc",
                      f"RC inesperado do core: {rc}", rc=rc,
                      rc_message=msg)

    def _new_account(self, t0, op):
        b = self._body()
        if b is None:
            self._api_log(t0, None, op, "-", 400)
            self._err(400, "invalid_json", "corpo JSON invalido")
            return
        try:
            cid = check_customer_id(b.get("customer_id"))
            tipo = check_field(b.get("type"), "type", 2).upper()
            if tipo not in ("CC", "CP"):
                raise ValueError("type deve ser CC ou CP")
        except (ValueError, AttributeError) as e:
            self._api_log(t0, None, op, "-", 400)
            self._err(400, "invalid_payload", str(e))
            return
        r = core.call("NEW-ACCOUNT", cid, tipo)
        rc = rc_int(r)
        msg = r.get("MSG", "")
        if rc == 0:
            self._api_log(t0, None, op, rc, 201)
            self._send(201, {"account": r.get("CTA-NUMERO"),
                             "customer_id": cid, "type": tipo,
                             "status": "created", "rc": rc,
                             "rc_message": msg})
        elif rc in (5, 7):
            self._api_log(t0, None, op, rc, 422)
            self._err(422, "account_rejected", msg, rc=rc)
        else:
            self._api_log(t0, None, op, rc, 500)
            self._err(500, "unexpected_rc",
                      f"RC inesperado do core: {rc}", rc=rc,
                      rc_message=msg)

    def _account_status(self, acc, action, t0):
        try:
            check_account(acc)
        except ValueError as e:
            self._api_log(t0, None, "account_" + action, "-", 400)
            self._err(400, "invalid_account", str(e))
            return
        op = {"block": "BLOCK", "unblock": "UNBLOCK",
              "close": "CLOSE-ACCT"}[action]
        r = core.call(op, acc)
        rc = rc_int(r)
        msg = r.get("MSG", "")
        if rc == 0:
            self._api_log(t0, None, "account_" + action, rc, 200)
            self._send(200, {"account": acc, "action": action,
                             "status": "ok", "rc": rc,
                             "rc_message": msg})
        elif rc == 1:
            self._api_log(t0, None, "account_" + action, rc, 404)
            self._err(404, "account_not_found", msg, rc=rc)
        elif rc in (3, 9):
            self._api_log(t0, None, "account_" + action, rc, 422)
            self._err(422, "account_rejected", msg, rc=rc)
        else:
            self._api_log(t0, None, "account_" + action, rc, 500)
            self._err(500, "unexpected_rc",
                      f"RC inesperado do core: {rc}", rc=rc,
                      rc_message=msg)

    # -- operacoes financeiras --------------------------------------
    def _financial(self, t0, op, tx_id, core_args, extra_resp=None):
        """Executa a operacao no core e mapeia RC -> HTTP (D27)."""
        r = core.call(op, tx_id, *core_args)
        rc = rc_int(r)
        if rc < 0:
            rc = 99
        msg = r.get("MSG", "")
        if rc == 0:
            self._api_log(t0, tx_id, op.lower(), rc, 201)
            self._send(201, {"tx_id": tx_id, "operation": op.lower(),
                             "status": "accepted", "rc": rc,
                             "rc_message": msg,
                             **(extra_resp or {})})
        elif rc == 6:
            # Replay idempotente: devolve o resultado original (200).
            info = tx_lookup(tx_id) or {}
            self._api_log(t0, tx_id, op.lower(), rc, 200)
            self._send(200, {"tx_id": tx_id, "operation": op.lower(),
                             "status": "duplicate", "replay": True,
                             "rc": rc, "rc_message": msg,
                             "original": info})
        elif rc in RC_REJECT:
            self._api_log(t0, tx_id, op.lower(), rc, 422)
            self._send(422, {"tx_id": tx_id, "operation": op.lower(),
                             "status": "rejected", "rc": rc,
                             "rc_message": msg})
        else:
            self._api_log(t0, tx_id, op.lower(), rc, 500)
            self._err(500, "unexpected_rc",
                      f"RC inesperado do core: {rc}",
                      tx_id=tx_id, rc=rc, rc_message=msg)

    def _deposit(self, t0, op):
        b = self._body()
        if b is None:
            self._api_log(t0, None, op, "-", 400)
            self._err(400, "invalid_json", "corpo JSON invalido")
            return
        try:
            tx_id = check_txid(b.get("tx_id"))
            acc = check_account(b.get("account"))
            cents = parse_amount(b.get("amount"))
        except (ValueError, AttributeError) as e:
            self._api_log(t0, b.get("tx_id") if b else None, op, "-", 400)
            self._err(400, "invalid_payload", str(e))
            return
        self._financial(t0, "DEPOSIT", tx_id, (acc, cents))

    def _withdraw(self, t0, op):
        b = self._body()
        if b is None:
            self._api_log(t0, None, op, "-", 400)
            self._err(400, "invalid_json", "corpo JSON invalido")
            return
        try:
            tx_id = check_txid(b.get("tx_id"))
            acc = check_account(b.get("account"))
            cents = parse_amount(b.get("amount"))
        except (ValueError, AttributeError) as e:
            self._api_log(t0, b.get("tx_id") if b else None, op, "-", 400)
            self._err(400, "invalid_payload", str(e))
            return
        self._financial(t0, "WITHDRAW", tx_id, (acc, cents))

    def _transfer(self, t0, op):
        b = self._body()
        if b is None:
            self._api_log(t0, None, op, "-", 400)
            self._err(400, "invalid_json", "corpo JSON invalido")
            return
        try:
            tx_id = check_txid(b.get("tx_id"))
            src = check_account(b.get("from_account"))
            dst = check_account(b.get("to_account"))
            cents = parse_amount(b.get("amount"))
        except (ValueError, AttributeError) as e:
            self._api_log(t0, b.get("tx_id") if b else None, op, "-", 400)
            self._err(400, "invalid_payload", str(e))
            return
        self._financial(t0, "TRANSFER", tx_id, (src, dst, cents))

    def _reversal(self, t0, op):
        b = self._body()
        if b is None:
            self._api_log(t0, None, op, "-", 400)
            self._err(400, "invalid_json", "corpo JSON invalido")
            return
        try:
            tx_id = check_txid(b.get("tx_id"))
            orig = check_txid(b.get("original_tx_id"))
        except (ValueError, AttributeError) as e:
            self._api_log(t0, b.get("tx_id") if b else None, op, "-", 400)
            self._err(400, "invalid_payload", str(e))
            return
        self._financial(t0, "REVERSAL", tx_id, (orig,))

    # -- lote -------------------------------------------------------
    def _batch(self, t0, op):
        """Recebe o arquivo de lote como texto, processa com bin/lb-lote
        (o motor de lote continua sendo o COBOL) e devolve o resumo.
        O arquivo temporario e isolado por nome unico e removido apos
        o processamento; os dados normais nunca sao tocados."""
        text = self._raw_body()
        if text is None:
            self._api_log(t0, None, op, "-", 400)
            self._err(400, "invalid_body",
                      "corpo deve ser texto UTF-8 de ate 1MB")
            return
        if not [ln for ln in text.splitlines()
                if ln.strip() and not ln.strip().startswith("#")]:
            self._api_log(t0, None, op, "-", 400)
            self._err(400, "empty_batch", "lote vazio")
            return
        if not os.path.isdir(DATA_DIR):
            raise CoreUnavailable(
                "diretorio de dados ausente: %s" % DATA_DIR)
        ts = time.strftime("%Y%m%d_%H%M%S")
        tmp_path = os.path.join(
            DATA_DIR, "lote_web_%d_%s.txt" % (os.getpid(), ts))
        try:
            with open(tmp_path, "w", encoding="utf-8") as f:
                f.write(text if text.endswith("\n") else text + "\n")
        except OSError as e:
            self._api_log(t0, None, op, "-", 500)
            self._err(500, "internal_error",
                      "falha ao gravar lote: %s" % e)
            return
        try:
            result = self._run_lote(tmp_path)
        finally:
            try:
                os.remove(tmp_path)
            except OSError:
                pass
        self._api_log(t0, None, op, "0", 200)
        self._send(200, result)

    def _run_lote(self, lote_path):
        """Roda bin/lb-lote sob o lock global e interpreta a saida."""
        if not _bin_executable(LOTE_BIN):
            raise CoreUnavailable(
                "binario lb-lote ausente: %s" % LOTE_BIN)
        cmd = [LOTE_BIN, DATA_DIR, lote_path]
        with CoreClient._lock:
            try:
                p = subprocess.run(
                    cmd, capture_output=True, text=True,
                    timeout=TIMEOUT)
            except subprocess.TimeoutExpired:
                raise CoreUnavailable(
                    "timeout no processamento do lote")
            except OSError as e:
                raise CoreUnavailable(
                    "falha ao executar lb-lote: %s" % e)
        out = p.stdout or ""
        res = {"processed": 0, "accepted": 0, "rejected": 0,
               "duplicates": 0, "invalid": 0,
               "errors": [], "report": None}
        m = re.search(
            r"Lote concluido:\s*(\d+)\s*ok,\s*(\d+)\s*rejeitadas,\s*"
            r"(\d+)\s*duplicadas,\s*(\d+)\s*invalidas\.", out)
        if m:
            nums = [int(x) for x in m.groups()]
            (res["accepted"], res["rejected"],
             res["duplicates"], res["invalid"]) = nums
            res["processed"] = sum(nums)
        for line in out.splitlines():
            if re.match(r"Linha \d+:", line.strip()):
                res["errors"].append(line.strip()[:200])
        m2 = re.search(r"Relatorio:\s*(\S+)", out)
        if m2:
            data_abs = os.path.abspath(DATA_DIR)
            rp_abs = os.path.abspath(
                os.path.join(DATA_DIR,
                             os.path.basename(m2.group(1).strip())))
            if (rp_abs.startswith(data_abs + os.sep)
                    and os.path.isfile(rp_abs)):
                try:
                    with open(rp_abs, encoding="utf-8") as f:
                        res["report"] = f.read(20000)
                except OSError:
                    pass
        if p.returncode != 0 and not m:
            raise CoreUnavailable(
                "lb-lote falhou (exit=%d)" % p.returncode)
        return res

    # -- frontend estatico (deploy Docker) --------------------------
    STATIC_TYPES = {
        ".html": "text/html; charset=utf-8",
        ".js": "application/javascript; charset=utf-8",
        ".css": "text/css; charset=utf-8",
        ".json": "application/json; charset=utf-8",
        ".png": "image/png",
        ".svg": "image/svg+xml",
        ".ico": "image/x-icon",
        ".txt": "text/plain; charset=utf-8",
        ".map": "application/json; charset=utf-8",
    }

    def _serve_static(self, path):
        """Serve web/dist quando existir (deploy em container unico).
        SPA: qualquer caminho desconhecido cai no index.html."""
        if not path or path.startswith(API_PREFIX):
            return False
        web_abs = os.path.abspath(WEB_DIR)
        if not os.path.isfile(os.path.join(web_abs, "index.html")):
            return False
        rel = path.lstrip("/") or "index.html"
        full = os.path.abspath(os.path.join(web_abs, rel))
        if not full.startswith(web_abs + os.sep):
            return False
        if os.path.isdir(full) or not os.path.isfile(full):
            full = os.path.join(web_abs, "index.html")
        try:
            with open(full, "rb") as f:
                body = f.read()
        except OSError:
            return False
        ctype = self.STATIC_TYPES.get(
            os.path.splitext(full)[1].lower(),
            "application/octet-stream")
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(body)
        return True


def main():
    if not os.path.isfile(BIN):
        log.warning("binario do core nao encontrado em %s "
                    "(health reportara core indisponivel)", BIN)
    srv = ThreadingHTTPServer((HOST, PORT), Handler)
    log.info("LBAPI %s ouvindo em %s:%d (data=%s, core=%s)",
             VERSION, HOST, PORT, DATA_DIR, BIN)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        srv.server_close()


if __name__ == "__main__":
    main()

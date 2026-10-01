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
import threading
import time
from decimal import Decimal, InvalidOperation
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

VERSION = "1.0.0"
API_PREFIX = "/api/v1"

# ---------------------------------------------------------------- config

DATA_DIR = os.environ.get("LBAPI_DATA_DIR", "./data")
PORT = int(os.environ.get("LBAPI_PORT", "8123"))
TIMEOUT = float(os.environ.get("LBAPI_TIMEOUT", "30"))
BIN = os.environ.get(
    "LBAPI_BIN",
    os.path.join(os.path.dirname(os.path.abspath(__file__)),
                 "..", "bin", "lb-api"),
)
BIN = os.path.normpath(BIN)

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
        if not (os.path.isfile(self.bin) and os.access(self.bin, os.X_OK)):
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
            # STMT-MOV aparece N vezes -> lista
            if k == "STMT-MOV":
                res.setdefault(k, []).append(v.strip())
            else:
                res[k] = v.strip()
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
        path = urlparse(self.path).path
        try:
            if path == f"{API_PREFIX}/health":
                self._health(t0)
            elif (m := re.fullmatch(
                    rf"{API_PREFIX}/accounts/(\d+)/statement", path)):
                self._statement(m.group(1), t0)
            elif (m := re.fullmatch(
                    rf"{API_PREFIX}/accounts/(\d+)", path)):
                self._account(m.group(1), t0)
            elif (m := re.fullmatch(
                    rf"{API_PREFIX}/transactions/([A-Za-z0-9_-]+)", path)):
                self._tx_get(m.group(1), t0)
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
        try:
            routes = {
                f"{API_PREFIX}/transactions/deposit": ("deposit", self._deposit),
                f"{API_PREFIX}/transactions/withdraw": ("withdraw", self._withdraw),
                f"{API_PREFIX}/transactions/transfer": ("transfer", self._transfer),
                f"{API_PREFIX}/transactions/reversal": ("reversal", self._reversal),
            }
            if path in routes:
                op, fn = routes[path]
                fn(t0, op)
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
                        "version": VERSION, **detail})

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


def main():
    if not os.path.isfile(BIN):
        log.warning("binario do core nao encontrado em %s "
                    "(health reportara core indisponivel)", BIN)
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    log.info("LBAPI %s ouvindo em 127.0.0.1:%d (data=%s, core=%s)",
             VERSION, PORT, DATA_DIR, BIN)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        srv.server_close()


if __name__ == "__main__":
    main()

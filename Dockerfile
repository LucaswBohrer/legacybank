# LEGACYBANK — Dockerfile (deploy gratuito, ex: Render)
#
# Container unico: frontend estatico + API Python + core COBOL.
# O GnuCOBOL 3.2.0 e compilado do fonte (mesma versao do desenvolvimento;
# o comportamento das ENTRYs foi validado nessa versao).
#
# Build:  docker build -t legacybank .
# Run:    docker run -p 8123:8123 -e PORT=8123 legacybank
#
# NOTA: no plano gratuito o filesystem e efimero — os dados somem
# em restart/redeploy. A UI sinaliza "modo demo".

# -------------------------------------------------- stage 1: COBOL
FROM debian:bookworm-slim AS cobol
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential curl ca-certificates \
        libgmp-dev libdb-dev gettext \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /tmp
# NOTA: o tarball oficial e gnucobol-3.2.tar.gz (nao "3.2.0"); verificado em
# 2026-10-01 — a URL com "3.2.0" retorna 404 no SourceForge.
RUN curl -fsSL --retry 3 --retry-delay 5 -o gnucobol.tar.gz \
        https://sourceforge.net/projects/gnucobol/files/gnucobol/3.2/gnucobol-3.2.tar.gz/download \
    && tar xzf gnucobol.tar.gz \
    && cd gnucobol-3.2 \
    && ./configure --without-db --without-readline >/dev/null \
    && make -j$(nproc) >/dev/null \
    && make install >/dev/null \
    && ldconfig
WORKDIR /app
COPY src/ src/
COPY scripts/build.sh scripts/build.sh
RUN ./scripts/build.sh && ls -la bin/

# -------------------------------------------------- stage 2: frontend
FROM node:20-alpine AS web
WORKDIR /app/web
COPY web/package.json web/package-lock.json* ./
RUN npm ci --no-audit --no-fund || npm install --no-audit --no-fund
COPY web/ ./
RUN npm run build && ls -la dist/

# -------------------------------------------------- stage 3: runtime
FROM python:3.12-slim-bookworm AS runtime
# libcob (runtime do GnuCOBOL) copiado do stage de build
COPY --from=cobol /usr/local/lib/libcob.so* /usr/local/lib/
COPY --from=cobol /usr/local/lib/gnucobol /usr/local/lib/gnucobol
RUN ldconfig
WORKDIR /app
# binarios COBOL compilados
COPY --from=cobol /app/bin/ bin/
# API Python (stdlib apenas)
COPY api/ api/
# frontend estatico
COPY --from=web /app/web/dist/ web/dist/
# script de entrada
COPY docker/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh \
    && python3 -c "import ast; ast.parse(open('/app/api/lbapi.py').read())" \
    && ls bin/ && test -x bin/lb-api && test -f web/dist/index.html

ENV LBAPI_HOST=0.0.0.0 \
    LBAPI_DATA_DIR=/data \
    LBAPI_BIN=/app/bin/lb-api \
    LBAPI_WEB_DIR=/app/web/dist \
    LBAPI_DEMO_MODE=1 \
    PYTHONUNBUFFERED=1
EXPOSE 8123
VOLUME /data
ENTRYPOINT ["/app/entrypoint.sh"]

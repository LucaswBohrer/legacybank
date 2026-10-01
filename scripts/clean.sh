#!/bin/bash
# clean.sh - remove artefatos de build
set -e
cd "$(dirname "$0")/.."
rm -rf bin
echo "bin/ removido."

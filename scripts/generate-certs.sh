#!/usr/bin/env bash
# generate-certs.sh
#
# Generates locally-trusted TLS certificates using mkcert.
# Run this once after cloning the repository, or whenever you need to
# add new domains to the certificate.
#
# Prerequisites:
#   - mkcert must be installed: https://github.com/FiloSottile/mkcert
#     Ubuntu/Debian:  sudo apt install mkcert
#     Arch:           sudo pacman -S mkcert
#     macOS:          brew install mkcert
#     Windows (WSL2): install mkcert on both Windows and WSL2 sides,
#                     then run `mkcert -install` in both environments.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CERTS_DIR="${PROJECT_ROOT}/certs"

# ── Dependency check ───────────────────────────────────────────────────────────
if ! command -v mkcert &>/dev/null; then
  echo ""
  echo "ERROR: mkcert is not installed or not in PATH."
  echo ""
  echo "Install it from: https://github.com/FiloSottile/mkcert"
  echo ""
  echo "  Ubuntu/Debian : sudo apt install mkcert"
  echo "  Arch Linux    : sudo pacman -S mkcert"
  echo "  macOS         : brew install mkcert"
  echo ""
  exit 1
fi

# ── Install local CA (idempotent) ──────────────────────────────────────────────
echo ">>> Installing mkcert local CA (sudo may be required)..."
mkcert -install

# ── Generate certificate ───────────────────────────────────────────────────────
mkdir -p "${CERTS_DIR}"

echo ""
echo ">>> Generating certificate for: *.local, localhost, 127.0.0.1, ::1"
echo "    Output: ${CERTS_DIR}/local.{crt,key}"
echo ""

mkcert \
  -cert-file "${CERTS_DIR}/local.crt" \
  -key-file  "${CERTS_DIR}/local.key" \
  "*.local" \
  "localhost" \
  "127.0.0.1" \
  "::1"

echo ""
echo ">>> Certificate generated successfully."
echo ""
echo "──────────────────────────────────────────────────────────────────────────"
echo " NEXT STEP: Add your local domains to /etc/hosts"
echo "──────────────────────────────────────────────────────────────────────────"
echo ""
echo "  Add a line like the following for each project domain you use:"
echo ""
echo "    127.0.0.1   traefik.local myapp.local api.local"
echo ""
echo "  On WSL2, also update the Windows hosts file:"
echo "    C:\\Windows\\System32\\drivers\\etc\\hosts"
echo ""
echo "  Then start the infrastructure:"
echo "    make up"
echo ""

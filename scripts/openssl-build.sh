#!/bin/bash
set -euo pipefail

log() { printf '[%s] %s\n' "openssl-build" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }
trap 'die "command failed (line ${LINENO}): ${BASH_COMMAND}"' ERR

: "${OPENSSL_VERSION:?OPENSSL_VERSION is required}"

TAG="openssl-${OPENSSL_VERSION}"
TARBALL="${TAG}.tar.gz"
PREFIX="/usr/local/openssl"
DOWNLOAD_DIR="/usr/src/downloads"
SOURCE_DIR="/usr/src/${TAG}"

verify_file() {
  test -f "$1" || die "missing: $1"
}

verify_dir() {
  test -d "$1" || die "missing: $1"
}

cd /usr/src

if [ ! -f "${DOWNLOAD_DIR}/${TARBALL}" ]; then
  log "Downloading ${TARBALL}"
  wget -O "${DOWNLOAD_DIR}/${TARBALL}" \
    "https://github.com/openssl/openssl/releases/download/${TAG}/${TARBALL}"
fi

log "Verifying SHA256"
wget -O "${DOWNLOAD_DIR}/${TARBALL}.sha256" \
  "https://github.com/openssl/openssl/releases/download/${TAG}/${TARBALL}.sha256"
EXPECTED_SHA256=$(awk '{print $1}' "${DOWNLOAD_DIR}/${TARBALL}.sha256")
test -n "${EXPECTED_SHA256}" || die "empty SHA256 file for ${TARBALL}"
echo "${EXPECTED_SHA256}  ${DOWNLOAD_DIR}/${TARBALL}" | sha256sum -c -

log "Extracting"
tar -xzf "${DOWNLOAD_DIR}/${TARBALL}"

cd "${SOURCE_DIR}"
log "Configuring"
./config enable-tls1_3 no-docs threads --prefix="${PREFIX}" --libdir=lib

log "Building"
make -j"$(nproc)"

log "Installing"
make install_sw install_ssldirs

log "Verifying installation"
verify_file "${PREFIX}/bin/openssl"
verify_file "${PREFIX}/include/openssl/ssl.h"
verify_dir "${PREFIX}/lib"
verify_file "${PREFIX}/lib/pkgconfig/libssl.pc"
verify_file "${PREFIX}/lib/pkgconfig/libcrypto.pc"

LD_LIBRARY_PATH="${PREFIX}/lib:${LD_LIBRARY_PATH:-}" \
  "${PREFIX}/bin/openssl" version -a
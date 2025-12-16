#!/bin/bash
set -euo pipefail

log() { printf '[%s] %s\n' "ngtcp2-build" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }
trap 'die "command failed (line ${LINENO}): ${BASH_COMMAND}"' ERR

: "${OPENSSL_VERSION:?OPENSSL_VERSION is required}"

NGTCP2_VERSION="${NGTCP2_VERSION:-head}"

OPENSSL_PREFIX="/usr/local/openssl"
NGTCP2_PREFIX="/usr/local/ngtcp2"
GIT_CACHE="/usr/src/git-cache/ngtcp2"
SOURCE_DIR="/usr/src/ngtcp2"

export PKG_CONFIG_PATH="${OPENSSL_PREFIX}/lib/pkgconfig:${NGTCP2_PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export PKG_CONFIG_PATH="${PKG_CONFIG_PATH}:/usr/lib/pkgconfig:/usr/share/pkgconfig"

verify_pkg() {
  pkg-config --exists "$1" || die "pkg-config cannot find $1"
}

if [ "${NGTCP2_VERSION}" = "head" ]; then
  log "Building ngtcp2 from HEAD against OpenSSL ${OPENSSL_VERSION}"
else
  log "Building ngtcp2 v${NGTCP2_VERSION} against OpenSSL ${OPENSSL_VERSION}"
fi

test -x "${OPENSSL_PREFIX}/bin/openssl" || \
  die "OpenSSL not installed at ${OPENSSL_PREFIX}"

verify_pkg gnutls
verify_pkg libbrotlienc
verify_pkg libbrotlidec

if [ ! -d "${GIT_CACHE}/.git" ]; then
  log "Cloning ngtcp2 repository"
  git clone --recursive https://github.com/ngtcp2/ngtcp2.git "${GIT_CACHE}"
fi

cd "${GIT_CACHE}"
git fetch origin --force

if [ "${NGTCP2_VERSION}" = "head" ]; then
  git fetch origin main master --force
  if git show-ref --verify --quiet refs/remotes/origin/main; then
    git checkout origin/main
  elif git show-ref --verify --quiet refs/remotes/origin/master; then
    git checkout origin/master
  else
    die "Could not find main or master branch"
  fi
else
  git fetch --tags --force
  git checkout "v${NGTCP2_VERSION}"
fi

git submodule update --init --recursive

rm -rf "${SOURCE_DIR}"
mkdir -p "${SOURCE_DIR}"
cp -a "${GIT_CACHE}/." "${SOURCE_DIR}/"

cd "${SOURCE_DIR}"
log "Generating build system"
autoreconf -i

log "Configuring"
./configure \
  --prefix="${NGTCP2_PREFIX}" \
  --libdir="${NGTCP2_PREFIX}/lib" \
  --enable-lib-only \
  --with-openssl="${OPENSSL_PREFIX}" \
  --with-gnutls \
  --with-libbrotlienc \
  --with-libbrotlidec

log "Building"
make -j"$(nproc)"

log "Installing"
make install

log "Verifying installation"
test -d "${NGTCP2_PREFIX}/lib/pkgconfig" || \
  die "missing: ${NGTCP2_PREFIX}/lib/pkgconfig"

verify_pkg libngtcp2

if pkg-config --exists libngtcp2_crypto_ossl; then
  log "OpenSSL crypto helper: $(pkg-config --modversion libngtcp2_crypto_ossl)"
elif pkg-config --exists libngtcp2_crypto_openssl; then
  log "OpenSSL crypto helper: $(pkg-config --modversion libngtcp2_crypto_openssl)"
else
  die "missing: libngtcp2_crypto_ossl or libngtcp2_crypto_openssl"
fi

verify_pkg libngtcp2_crypto_gnutls
log "GnuTLS crypto helper: $(pkg-config --modversion libngtcp2_crypto_gnutls)"

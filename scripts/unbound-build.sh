#!/bin/bash
set -euo pipefail

log() { printf '[%s] %s\n' "unbound-build" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }
trap 'die "command failed (line ${LINENO}): ${BASH_COMMAND}"' ERR

: "${OPENSSL_VERSION:?OPENSSL_VERSION is required}"

OPENSSL_PREFIX="/usr/local/openssl"
NGTCP2_PREFIX="/usr/local/ngtcp2"
GIT_CACHE="/usr/src/git-cache/unbound"
SOURCE_DIR="/usr/src/unbound"
INSTALL_DIR="/tmp/unbound-install"
BUILD_LOG="/tmp/unbound-build.log"

verify_pkg() {
  pkg-config --exists "$1" || die "pkg-config cannot find $1"
}

test -x "${OPENSSL_PREFIX}/bin/openssl" || \
  die "OpenSSL not installed at ${OPENSSL_PREFIX}"

# Begin Script

if pkg-config --exists libsystemd; then
  HAS_SYSTEMD=1
  verify_pkg libsystemd
  SYSTEMD_STATUS="enabled"
else
  HAS_SYSTEMD=0
  SYSTEMD_STATUS="disabled"
fi

verify_pkg libngtcp2
verify_pkg libprotobuf-c

if ! pkg-config --exists libngtcp2_crypto_ossl && \
   ! pkg-config --exists libngtcp2_crypto_openssl; then
  die "missing: libngtcp2_crypto_ossl or libngtcp2_crypto_openssl"
fi

log "Building unbound (OpenSSL ${OPENSSL_VERSION}, systemd: ${SYSTEMD_STATUS})..."

if [ ! -d "${GIT_CACHE}/.git" ]; then
  git clone -q https://github.com/NLnetLabs/unbound.git "${GIT_CACHE}"
fi

cd "${GIT_CACHE}"
git fetch -q origin master --force
git checkout -q origin/master

rm -rf "${SOURCE_DIR}"
mkdir -p "${SOURCE_DIR}"
cp -a "${GIT_CACHE}/." "${SOURCE_DIR}/"

cd "${SOURCE_DIR}"
CONFIGURE_OPTS=(
  --prefix=/usr
  --sysconfdir=/etc/unbound
  --localstatedir=/var
  --enable-dnscrypt
  --enable-dnstap
  --enable-doq
  --enable-pie
  --enable-relro-now
  --enable-subnet
  --enable-tfo-client
  --enable-tfo-server
  --enable-cachedb
  --with-libevent
  --with-libnghttp2
  --with-libngtcp2
  --with-pyunbound
  --with-libhiredis
  --with-pidfile=/var/run/unbound.pid
  --with-rootkey-file=/var/lib/unbound/root.key
  --with-ssl="${OPENSSL_PREFIX}"
  --with-libngtcp2="${NGTCP2_PREFIX}"
  --enable-debug
)

if [ "${HAS_SYSTEMD}" = "1" ]; then
  CONFIGURE_OPTS+=(--enable-systemd)
fi

./configure "${CONFIGURE_OPTS[@]}" >"${BUILD_LOG}" 2>&1
make -j"$(nproc)" >>"${BUILD_LOG}" 2>&1
make install DESTDIR="${INSTALL_DIR}" >>"${BUILD_LOG}" 2>&1

test -f "${INSTALL_DIR}/usr/sbin/unbound" || \
  die "unbound binary not installed at ${INSTALL_DIR}/usr/sbin/unbound"

strip --strip-unneeded "${INSTALL_DIR}/usr/sbin/unbound" >>"${BUILD_LOG}" 2>&1 || true

log "✓ $("${INSTALL_DIR}/usr/sbin/unbound" -V 2>&1 | head -n 1)"
if [ -s "${BUILD_LOG}" ]; then
  log "Build output (last 20 lines):"
  tail -n 20 "${BUILD_LOG}" | sed 's/^/  /' >&2
fi
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

verify_pkg() {
  pkg-config --exists "$1" || die "pkg-config cannot find $1"
}

test -x "${OPENSSL_PREFIX}/bin/openssl" || \
  die "OpenSSL not installed at ${OPENSSL_PREFIX}"

if pkg-config --exists libsystemd; then
  HAS_SYSTEMD=1
  verify_pkg libsystemd
else
  HAS_SYSTEMD=0
  log "libsystemd not found, building without systemd support"
fi

verify_pkg libngtcp2
verify_pkg libprotobuf-c

if ! pkg-config --exists libngtcp2_crypto_ossl && \
   ! pkg-config --exists libngtcp2_crypto_openssl; then
  die "missing: libngtcp2_crypto_ossl or libngtcp2_crypto_openssl"
fi

log "Building unbound from HEAD (OpenSSL ${OPENSSL_VERSION})"

if [ ! -d "${GIT_CACHE}/.git" ]; then
  log "Cloning unbound repository"
  git clone https://github.com/NLnetLabs/unbound.git "${GIT_CACHE}"
fi

cd "${GIT_CACHE}"
git fetch origin master --force
git checkout origin/master

rm -rf "${SOURCE_DIR}"
mkdir -p "${SOURCE_DIR}"
cp -a "${GIT_CACHE}/." "${SOURCE_DIR}/"

cd "${SOURCE_DIR}"
log "Configuring"
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

./configure "${CONFIGURE_OPTS[@]}"

log "Building"
make -j"$(nproc)"

log "Installing"
make install DESTDIR="${INSTALL_DIR}"

log "Verifying installation"
test -f "${INSTALL_DIR}/usr/sbin/unbound" || \
  die "unbound binary not installed at ${INSTALL_DIR}/usr/sbin/unbound"

strip --strip-unneeded "${INSTALL_DIR}/usr/sbin/unbound" || true

log "unbound OK: $("${INSTALL_DIR}/usr/sbin/unbound" -V 2>&1 | head -n 1)"
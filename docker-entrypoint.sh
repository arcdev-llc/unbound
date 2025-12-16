#!/bin/sh
set -eu

umask 077
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

CONF="${UNBOUND_CONF:-/etc/unbound/unbound.conf}"

# Fail fast on invalid config.
# Quote defensively; also guard against an empty CONF.
[ -n "${CONF}" ] || { echo "UNBOUND_CONF resolved to empty" >&2; exit 64; }
exec_test=/usr/sbin/unbound-checkconf
[ -x "${exec_test}" ] || { echo "missing ${exec_test}" >&2; exit 127; }
"${exec_test}" "${CONF}"

# Ensure root trust anchor exists (state lives in /var/lib/unbound).
# Create directory if a mis-mounted volume erased it (read-only rootfs compatible if volume is writable).
STATE_DIR=/var/lib/unbound
ROOTKEY="${STATE_DIR}/root.key"

[ -d "${STATE_DIR}" ] || mkdir -p "${STATE_DIR}"

if [ ! -f "${ROOTKEY}" ]; then
  # unbound-anchor writes the file; keep it in the state dir only.
  /usr/sbin/unbound-anchor -a "${ROOTKEY}"
  chmod 0600 "${ROOTKEY}" || true
fi

exec "$@"

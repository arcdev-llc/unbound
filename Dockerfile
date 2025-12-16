# syntax=docker/dockerfile:1.7
ARG ALPINE_VERSION=3.21.5
ARG OPENSSL_VERSION=3.6.0
ARG NGTCP2_VERSION=head

############################
# Base toolchain (build deps)
############################
FROM alpine:${ALPINE_VERSION} AS toolchain
ARG TARGETPLATFORM
WORKDIR /usr/src

RUN --mount=type=cache,target=/var/cache/apk,id=apk-cache-${TARGETPLATFORM},sharing=locked \
    apk add --no-cache \
      bash ca-certificates \
      wget git \
      clang llvm lld \
      build-base linux-headers \
      ccache \
      pkgconf \
      autoconf automake libtool \
      perl

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# Baseline hardening flags for native code you compile in this image.
# (musl makes _FORTIFY_SOURCE less dramatic than glibc, but it’s still standard.)
ENV CC=clang \
    CXX=clang++ \
    CFLAGS="-O2 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -fPIE" \
    CXXFLAGS="-O2 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -fPIE" \
    LDFLAGS="-Wl,-z,relro -Wl,-z,now -pie" \
    PATH="/usr/lib/ccache:$PATH" \
    CCACHE_DIR="/ccache" \
    CCACHE_BASEDIR="/usr/src" \
    CCACHE_COMPILERCHECK="content" \
    CCACHE_SLOPPINESS="time_macros,include_file_mtime,locale"

############################
# OpenSSL build
############################
FROM toolchain AS openssl-builder
ARG TARGETPLATFORM
ARG OPENSSL_VERSION

COPY --chmod=0755 scripts/openssl-build.sh /usr/local/bin/openssl-build.sh

RUN --mount=type=cache,target=/usr/src/downloads,id=downloads-${TARGETPLATFORM} \
    --mount=type=cache,target=/ccache,id=ccache-openssl-${TARGETPLATFORM} \
    OPENSSL_VERSION="${OPENSSL_VERSION}" \
    /usr/local/bin/openssl-build.sh

############################
# ngtcp2 build
############################
FROM toolchain AS ngtcp2-builder
ARG TARGETPLATFORM
ARG NGTCP2_VERSION
ARG OPENSSL_VERSION

COPY --chmod=0755 scripts/ngtcp2-build.sh /usr/local/bin/ngtcp2-build.sh
COPY --from=openssl-builder /usr/local/openssl /usr/local/openssl

RUN --mount=type=cache,target=/var/cache/apk,id=apk-cache-${TARGETPLATFORM},sharing=locked \
    apk add --no-cache brotli-dev gnutls-dev

ENV PKG_CONFIG_PATH=/usr/local/openssl/lib/pkgconfig \
    CPPFLAGS="-I/usr/local/openssl/include" \
    LDFLAGS="-Wl,-rpath,/usr/local/openssl/lib -L/usr/local/openssl/lib ${LDFLAGS}"

RUN --mount=type=cache,target=/usr/src/git-cache,id=git-cache-${TARGETPLATFORM} \
    --mount=type=cache,target=/ccache,id=ccache-ngtcp2-${TARGETPLATFORM} \
    NGTCP2_VERSION="${NGTCP2_VERSION}" \
    /usr/local/bin/ngtcp2-build.sh

############################
# Unbound build
############################
FROM toolchain AS builder
ARG TARGETPLATFORM
ARG OPENSSL_VERSION
WORKDIR /usr/src/unbound

RUN --mount=type=cache,target=/var/cache/apk,id=apk-cache-${TARGETPLATFORM},sharing=locked \
    apk add --no-cache \
      bison flex \
      expat-dev \
      libevent-dev \
      hiredis-dev \
      protobuf protobuf-dev \
      protobuf-c protobuf-c-dev \
      nghttp2-dev \
      swig \
      libsodium-dev \
      python3 python3-dev \
      py3-setuptools \
      libcap libcap-utils

COPY --from=openssl-builder /usr/local/openssl /usr/local/openssl
COPY --from=ngtcp2-builder  /usr/local/ngtcp2  /usr/local/ngtcp2

COPY --chmod=0755 scripts/unbound-build.sh /usr/local/bin/unbound-build.sh

ENV PKG_CONFIG_PATH=/usr/local/openssl/lib/pkgconfig:/usr/local/ngtcp2/lib/pkgconfig \
    CPPFLAGS="-I/usr/local/openssl/include -I/usr/local/ngtcp2/include" \
    LDFLAGS="-Wl,-rpath,/usr/local/ngtcp2/lib:/usr/local/openssl/lib -L/usr/local/ngtcp2/lib -L/usr/local/openssl/lib ${LDFLAGS}"

RUN --mount=type=cache,target=/ccache,id=ccache-unbound-${TARGETPLATFORM} \
    --mount=type=cache,target=/usr/src/git-cache,id=git-cache-${TARGETPLATFORM} \
    OPENSSL_VERSION="${OPENSSL_VERSION}" \
    /usr/local/bin/unbound-build.sh

RUN setcap cap_net_bind_service=+ep /tmp/unbound-install/usr/sbin/unbound

############################
# Runtime
############################
FROM alpine:${ALPINE_VERSION} AS runtime
ARG TARGETPLATFORM

RUN --mount=type=cache,target=/var/cache/apk,id=apk-cache-${TARGETPLATFORM},sharing=locked \
    apk add --no-cache \
      ca-certificates \
      expat \
      libevent \
      libsodium

COPY --from=openssl-builder /usr/local/openssl/lib/ /usr/local/openssl/lib/
COPY --from=ngtcp2-builder  /usr/local/ngtcp2/lib/  /usr/local/ngtcp2/lib/
COPY --from=builder /tmp/unbound-install/ /

# musl loader path: keep this, but make it deterministic and minimal.
RUN arch="$(apk --print-arch)" \
    && case "$arch" in \
        x86_64) musl_path=/etc/ld-musl-x86_64.path ;; \
        aarch64) musl_path=/etc/ld-musl-aarch64.path ;; \
        *) musl_path="/etc/ld-musl-${arch}.path" ;; \
    esac \
    && printf '%s\n' /usr/local/openssl/lib /usr/local/ngtcp2/lib >> "${musl_path}" \
    && test -x /usr/sbin/unbound

# Non-root user, tight perms, and read-only-rootfs-friendly layout.
# Use /run (tmpfs) rather than writing under /var/run.
RUN addgroup -S unbound \
    && adduser  -S -G unbound -h /var/lib/unbound -s /sbin/nologin unbound \
    && mkdir -p /var/lib/unbound /etc/unbound /run/unbound \
    && chown -R unbound:unbound /var/lib/unbound /etc/unbound /run/unbound \
    && chmod 0750 /var/lib/unbound /etc/unbound /run/unbound

ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

VOLUME ["/etc/unbound", "/var/lib/unbound"]

EXPOSE 53/udp 53/tcp 853/tcp 853/udp
STOPSIGNAL SIGTERM

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD unbound-host -C /etc/unbound/unbound.conf -v cloudflare.com > /dev/null 2>&1 || exit 1

COPY --chmod=0755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

USER unbound
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/usr/sbin/unbound", "-d", "-c", "/etc/unbound/unbound.conf"]

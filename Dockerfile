# syntax=docker/dockerfile:1
# The MIT License
#
# Copyright (c) 2019-2026, Serhiy Makarenko

ARG DEBIAN_RELEASE=trixie
# Both lines are bumped by .github/workflows/unbound-release.yml, which
# verifies the release's OpenPGP signature before recording the hash.
ARG UNBOUND_VERSION=1.26.0
ARG UNBOUND_SHA256=

# ------------------------------------------------------------------ source
# Runs on the build host's own architecture, so fetching and verifying the
# tarball never happens under emulation (the arm/v7 build runs in QEMU).
FROM --platform=$BUILDPLATFORM debian:${DEBIAN_RELEASE}-slim AS source

ARG UNBOUND_VERSION
ARG UNBOUND_SHA256
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN test -n "${UNBOUND_SHA256}" || { echo "UNBOUND_SHA256 is required" >&2; exit 1; } && \
    curl -fsSLO "https://nlnetlabs.nl/downloads/unbound/unbound-${UNBOUND_VERSION}.tar.gz" && \
    echo "${UNBOUND_SHA256}  unbound-${UNBOUND_VERSION}.tar.gz" | sha256sum -c - && \
    tar xzf "unbound-${UNBOUND_VERSION}.tar.gz" && \
    mv "unbound-${UNBOUND_VERSION}" unbound

# ----------------------------------------------------------------- builder
FROM debian:${DEBIAN_RELEASE}-slim AS builder

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      build-essential libexpat1-dev libssl-dev && \
    rm -rf /var/lib/apt/lists/*

COPY --from=source /src/unbound /src/unbound
WORKDIR /src/unbound
RUN ./configure \
      --disable-static \
      --with-rootkey-file=/var/lib/unbound/root.key && \
    make -j"$(nproc)" && \
    make install DESTDIR=/out

# ----------------------------------------------------------------- runtime
FROM debian:${DEBIAN_RELEASE}-slim

ARG UNBOUND_VERSION
ARG DEBIAN_FRONTEND=noninteractive

LABEL maintainer="serhiy.makarenko@me.com" \
      org.opencontainers.image.title="nlnetlabs-unbound-resolver" \
      org.opencontainers.image.version="${UNBOUND_VERSION}" \
      org.opencontainers.image.licenses="MIT"

RUN apt-get update && \
    apt-get install -y --no-install-recommends libssl3t64 libexpat1 && \
    rm -rf /var/lib/apt/lists/*

# Same UID/GID 88 as the 2019-2021 image, so host file ownership still works.
RUN groupadd -g 88 unbound && \
    useradd -r -u 88 -g unbound -d /var/lib/unbound -s /usr/sbin/nologin \
      -c "Unbound DNS resolver" unbound

COPY --from=builder /out/usr/local/ /usr/local/

# /usr/local/lib is already in Debian's ld.so.conf, so no LD_LIBRARY_PATH.
# /usr/local/etc/unbound (the default chroot) stays owned by unbound, as in
# the old image, so legacy configs that keep root.key there still work.
RUN ldconfig && \
    install -d -o unbound -g unbound -m 0755 /var/lib/unbound && \
    chown unbound:unbound /usr/local/etc/unbound

COPY --chmod=0755 docker-entrypoint.sh /usr/local/sbin/docker-entrypoint.sh

# Home of the trust anchor in the current config layout. It is runtime
# state: it must survive container recreation and stay writable so that
# RFC 5011 can follow root key rollovers.
VOLUME ["/var/lib/unbound"]

EXPOSE 53/tcp 53/udp

ENTRYPOINT ["/usr/local/sbin/docker-entrypoint.sh"]
CMD ["-d", "-p", "-c", "/usr/local/etc/unbound/unbound.conf"]

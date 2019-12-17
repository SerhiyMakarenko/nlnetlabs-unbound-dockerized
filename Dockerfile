# The MIT License
#
# Copyright (c) 2019, Serhiy Makarenko

FROM debian:10-slim AS builder

ARG UNBOUND_VERSION=1.9.6

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends --no-install-suggests \
    curl file libssl-dev libexpat1-dev build-essential ca-certificates && \
    curl -RL -O "https://nlnetlabs.nl/downloads/unbound/unbound-${UNBOUND_VERSION}.tar.gz" && \
    tar xvzf unbound-${UNBOUND_VERSION}.tar.gz && \
    cd unbound-${UNBOUND_VERSION} && \
    ./configure \
    	--disable-static && \
    make && \
    make install

FROM debian:10-slim
LABEL maintainer="serhiy@makarenko.me"

ARG DEBIAN_FRONTEND=noninteractive

ENV LD_LIBRARY_PATH=/usr/local/lib

RUN apt-get update && \
    apt-get install -y --no-install-recommends --no-install-suggests \
    libssl1.1 libexpat1 && \
    rm -rf /var/lib/apt/lists/*

RUN groupadd -g 88 unbound && \
	useradd -c "Unbound DNS resolver" -d /usr/local/etc/unbound -u 88 \
        -g unbound -s /bin/false unbound

COPY --from=builder /usr/local /usr/local

RUN /usr/local/sbin/unbound-anchor -a /usr/local/etc/unbound/root.key || true && chown -R unbound:unbound /usr/local/etc/unbound

EXPOSE 53/tcp 53/udp

ENTRYPOINT ["/usr/local/sbin/unbound"]
CMD ["-d", "-c", "/usr/local/etc/unbound/unbound.conf"]

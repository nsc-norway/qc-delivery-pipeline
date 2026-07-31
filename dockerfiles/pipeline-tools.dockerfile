FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        bash \
        ca-certificates \
        coreutils \
        openssl \
        procps \
        sed \
        tar \
    && rm -rf /var/lib/apt/lists/*
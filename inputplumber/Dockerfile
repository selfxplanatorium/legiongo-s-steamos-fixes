# Builder for the patched InputPlumber (Debian-based, glibc older than SteamOS).
FROM rust:1.92
RUN apt-get update && apt-get install -y --no-install-recommends \
      libclang-dev libudev-dev pkg-config \
    && rm -rf /var/lib/apt/lists/*

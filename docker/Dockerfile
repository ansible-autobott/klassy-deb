# syntax=docker/dockerfile:1
#
# Per-release klassy builder image. Parameterised by:
#   BASE_IMAGE  the distro base (e.g. debian:trixie-slim, debian:sid-slim)
#   RELEASE     selects docker/deps/<release>.list and package metadata
# so the build links against that release's Qt / KDE Frameworks stack.
#
#   docker build --build-arg BASE_IMAGE=debian:trixie-slim --build-arg RELEASE=debian13_trixie \
#     -t klassy-deb:debian13_trixie docker
#
# Build context is the `docker/` directory (deps/ + build-package.sh).

ARG BASE_IMAGE=debian:trixie-slim
FROM ${BASE_IMAGE}

# RELEASE selects the deps list + package metadata (see docker/deps/<release>.list).
ARG RELEASE=debian13_trixie
ENV DEBIAN_FRONTEND=noninteractive

# Toolchain common to every release/stack.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        git \
        pkg-config \
        gettext \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Release-specific KDE / Qt build dependencies.
COPY deps/ /tmp/deps/
RUN apt-get update \
    && sed 's/#.*//' "/tmp/deps/${RELEASE}.list" | xargs -r apt-get install -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Build + package script.
COPY build-package.sh /usr/local/bin/build-package.sh
RUN chmod +x /usr/local/bin/build-package.sh

WORKDIR /work
ENTRYPOINT ["/usr/local/bin/build-package.sh"]

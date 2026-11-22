# syntax=docker/dockerfile:1
#
# RIPE Atlas Software Probe - container image
# Builds the official Debian packages from
# https://github.com/RIPE-NCC/ripe-atlas-software-probe and installs them
# into a slim Debian runtime image.

ARG DEBIAN_VERSION=trixie

# ---------------------------------------------------------------------------
# Builder: compile the .deb packages from the upstream release tag
# ---------------------------------------------------------------------------
FROM debian:${DEBIAN_VERSION}-slim AS builder

ARG ATLAS_VERSION=5130
ARG ATLAS_REPO=https://github.com/RIPE-NCC/ripe-atlas-software-probe.git

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates git build-essential debhelper dh-autoreconf \
      autoconf automake libtool autotools-dev libssl-dev \
      psmisc net-tools systemd \
 && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "${ATLAS_VERSION}" "${ATLAS_REPO}" /build/src

WORKDIR /build/src
RUN dpkg-buildpackage -b -us -uc \
 && mkdir -p /out \
 && cp ../ripe-atlas-common_*.deb ../ripe-atlas-probe_*.deb /out/

# ---------------------------------------------------------------------------
# Runtime
# ---------------------------------------------------------------------------
FROM debian:${DEBIAN_VERSION}-slim

ARG ATLAS_VERSION=5130

LABEL org.opencontainers.image.title="ripe-atlas-probe" \
      org.opencontainers.image.description="RIPE Atlas Software Probe in a container" \
      org.opencontainers.image.version="${ATLAS_VERSION}" \
      org.opencontainers.image.licenses="GPL-3.0" \
      io.ripe.atlas.version="${ATLAS_VERSION}"

COPY --from=builder /out/*.deb /tmp/debs/

# Install runtime deps first so systemd-sysusers / setcap are available
# when the package maintainer scripts run.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates tini systemd libcap2-bin openssh-client psmisc \
      iproute2 net-tools procps \
 && apt-get install -y --no-install-recommends /tmp/debs/*.deb \
 # The postinst generates a probe key - never ship a key inside the image.
 && rm -f /etc/ripe-atlas/probe_key /etc/ripe-atlas/probe_key.pub \
 # Keep pristine copies of /etc/ripe-atlas so that an empty bind mount
 # can be re-populated by the entrypoint.
 && mkdir -p /usr/share/ripe-atlas-docker \
 && cp -a /etc/ripe-atlas /usr/share/ripe-atlas-docker/etc-defaults \
 && echo "${ATLAS_VERSION}" > /usr/share/ripe-atlas-docker/VERSION \
 && rm -rf /tmp/debs /var/lib/apt/lists/*

COPY --chmod=0755 docker/entrypoint.sh /usr/local/bin/entrypoint.sh

# /etc/ripe-atlas       : probe key + config.txt  (MUST be persisted)
# /var/spool/ripe-atlas : measurement data / crons
VOLUME ["/etc/ripe-atlas", "/var/spool/ripe-atlas"]

ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/local/bin/entrypoint.sh"]

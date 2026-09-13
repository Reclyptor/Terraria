# syntax=docker/dockerfile:1
#
# ghcr.io/reclyptor/terraria — vanilla Terraria dedicated server on the GameOps toolkit.
# Adapter contract: https://github.com/Reclyptor/GameOps/blob/master/docs/CONTRACT.md

ARG GAMEOPS_VERSION=1.0.0
FROM ghcr.io/reclyptor/gameops:${GAMEOPS_VERSION} AS gameops

FROM debian:trixie-slim

# Server release baked into the image (terraria.org numbers releases without
# dots: 1458 = 1.4.5.8). Runtime updates replace it; this is only the start.
ARG RELEASE=1458
ARG RELEASE_SHA256=f513a4ac9789d34af766291ae217c9cd7d9472e13782a0e2b17512f70d7a8334
ARG PUID=1000
ARG PGID=1000

SHELL ["/bin/bash", "-eo", "pipefail", "-c"]

# unzip: the server bundle is a zip (also needed for runtime updates).
# curl is build-time only.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates unzip curl \
 && groupadd --system --gid "${PGID}" terraria \
 && useradd --system --uid "${PUID}" --gid "${PGID}" --no-create-home --shell /usr/sbin/nologin terraria \
 && curl -fsSL --retry 5 -o /tmp/terraria.zip \
        "https://terraria.org/api/download/pc-dedicated-server/terraria-server-${RELEASE}.zip" \
 && echo "${RELEASE_SHA256}  /tmp/terraria.zip" | sha256sum -c - \
 && unzip -q /tmp/terraria.zip -d /tmp/terraria \
 && mkdir -p /opt/terraria \
 && cp -a "/tmp/terraria/${RELEASE}/Linux/." /opt/terraria/ \
 && cp "/tmp/terraria/${RELEASE}/Windows/serverconfig.txt" /opt/terraria/serverconfig-example.txt \
 && rm -rf /tmp/terraria /tmp/terraria.zip \
 && chmod +x /opt/terraria/TerrariaServer /opt/terraria/TerrariaServer.bin.x86_64 \
 && printf '%s\n' "${RELEASE}" > /opt/terraria/VERSION \
 && apt-get purge -y --auto-remove curl \
 && rm -rf /var/lib/apt/lists/* \
 && install -d -o "${PUID}" -g "${PGID}" /data /backups \
 && chown -R "${PUID}:${PGID}" /opt/terraria

COPY --from=gameops /opt/gameops /opt/gameops
COPY adapter/ /opt/game/

RUN chmod 0644 /opt/game/adapter.sh /opt/game/lib/*.sh /opt/game/templates/* \
 && bash -n /opt/game/adapter.sh /opt/game/lib/*.sh \
 && test -x /opt/terraria/TerrariaServer.bin.x86_64

ENV PATH="/opt/gameops/bin:${PATH}" \
    HOME=/data \
    MONO_IOMAP=all \
    DATA_DIR=/data \
    BACKUP_DIR=/backups \
    SERVER_NAME=Terraria \
    PORT=7777 \
    GATE_ENABLED=true \
    GATE_TARGET_PORT=7778 \
    GATE_EXPECT=Terraria \
    WORLD_NAME=world \
    WORLD_SIZE=2 \
    MAX_PLAYERS=8

USER ${PUID}:${PGID}
VOLUME ["/data", "/backups"]
EXPOSE 7777/tcp 9110/tcp
HEALTHCHECK --interval=60s --timeout=10s --start-period=15m --retries=3 CMD ["gameops", "health"]
ENTRYPOINT ["gameops", "run"]

LABEL org.opencontainers.image.title="terraria" \
      org.opencontainers.image.description="Vanilla Terraria dedicated server with backups, in-place auto-updates, Discord notifications and player events, on the GameOps toolkit" \
      org.opencontainers.image.source="https://github.com/Reclyptor/Terraria" \
      org.opencontainers.image.licenses="MIT" \
      terraria.release="${RELEASE}"

#!/bin/sh
# Entrypoint for the RIPE Atlas software probe container.
#
# Replicates what systemd (sysusers/tmpfiles/unit) and the package postinst
# would do on a normal host, then drops privileges and runs the probe.
set -eu

ATLAS_USER=ripe-atlas
ATLAS_GROUP=ripe-atlas
ETC_DIR=/etc/ripe-atlas
SPOOL_DIR=/var/spool/ripe-atlas
KEY="${ETC_DIR}/probe_key"
CONFIG="${ETC_DIR}/config.txt"
DEFAULTS=/usr/share/ripe-atlas-docker/etc-defaults

log() { printf '[entrypoint] %s\n' "$*"; }

url_encode() {
	printf '%s' "$1" | sed -e 's/%/%25/g' -e 's/ /%20/g' -e 's/+/%2B/g' \
		-e 's,/,%2F,g' -e 's/=/%3D/g'
}

# Set or remove KEY=VALUE in config.txt from an environment variable.
set_config() {
	name="$1"
	value="$2"
	touch "${CONFIG}"
	sed -i "/^${name}=/d" "${CONFIG}"
	if [ -n "${value}" ]; then
		printf '%s=%s\n' "${name}" "${value}" >> "${CONFIG}"
	fi
}

log "RIPE Atlas software probe $(cat /usr/share/ripe-atlas-docker/VERSION 2>/dev/null || echo unknown)"

# --- /etc/ripe-atlas ---------------------------------------------------------
mkdir -p "${ETC_DIR}"
# Restore packaged defaults (e.g. "mode") without overwriting user files.
cp -an "${DEFAULTS}/." "${ETC_DIR}/"

# --- config.txt from environment ------------------------------------------
# Only variables that are actually set are touched; unset = leave as is.
[ "${RXTXRPT+x}" ]        && set_config RXTXRPT "${RXTXRPT}"
[ "${TELNETD_PORT+x}" ]   && set_config TELNETD_PORT "${TELNETD_PORT}"
[ "${HTTP_POST_PORT+x}" ] && set_config HTTP_POST_PORT "${HTTP_POST_PORT}"

# --- probe key ---------------------------------------------------------------
if [ ! -f "${KEY}" ]; then
	comment="${PROBE_KEY_COMMENT:-$(hostname -s | tr -cd 'a-zA-Z0-9._-')}"
	log "No probe key found, generating a new one (${KEY})"
	ssh-keygen -q -t ed25519 -N '' -C "${comment}" -f "${KEY}"
fi

chown -R "${ATLAS_USER}:${ATLAS_GROUP}" "${ETC_DIR}"
chmod 0770 "${ETC_DIR}"
chmod 0600 "${KEY}"
chmod 0644 "${KEY}.pub"

pubkey="$(cat "${KEY}.pub")"
cat <<EOF
------------------------------------------------------------
Probe public key (${KEY}.pub):
    ${pubkey}

If this probe is not registered yet, register it at:
    https://atlas.ripe.net/register/swprobe?key=$(url_encode "${pubkey}")
------------------------------------------------------------
EOF

# --- runtime / spool dirs (what systemd-tmpfiles does on a host) ------------
for f in /usr/lib/tmpfiles.d/ripe-atlas*.conf; do
	[ -f "$f" ] && systemd-tmpfiles --create "$f" >/dev/null 2>&1 || true
done
mkdir -p "${SPOOL_DIR}"
# Fix ownership if the volume was created by someone else (e.g. bind mount).
if [ "$(stat -c %U "${SPOOL_DIR}")" != "${ATLAS_USER}" ]; then
	log "Fixing ownership of ${SPOOL_DIR}"
	chown -R "${ATLAS_USER}:${ATLAS_GROUP}" "${SPOOL_DIR}"
	chmod 2775 "${SPOOL_DIR}"
fi

# Allow "docker run ... <command>" for debugging (e.g. bash).
if [ "$#" -gt 0 ]; then
	exec "$@"
fi

# --- run the probe as the unprivileged user (like the systemd unit) ---------
cd "${SPOOL_DIR}"
export HOME="${SPOOL_DIR}"
log "Starting ripe-atlas"
exec setpriv --reuid="${ATLAS_USER}" --regid="${ATLAS_GROUP}" --init-groups \
	/usr/sbin/ripe-atlas

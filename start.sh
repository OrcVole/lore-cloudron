#!/bin/bash
set -eu

echo "==> Lore Server starting"

CONFIG_DIR=/app/data/config
STORE_DIR=/app/data/store
# Where the Cloudron tls addon puts the material, and where we stage a copy the
# unprivileged app user can actually read. See the TLS section below.
CERT_SRC=/etc/certs
CERT_DIR=/run/lore/certs
CERT_FILE="${CERT_DIR}/tls_cert.pem"
PKEY_FILE="${CERT_DIR}/tls_key.pem"

# ---------------------------------------------------------------- layout
# Every store path is pinned into /app/data by local.toml. With no configuration the
# server derives a path under the system temporary directory, which upstream says a
# reboot can clear. That is silent data loss, so the directories are created here and
# the pinned paths are asserted below.

mkdir -p "${CONFIG_DIR}" "${STORE_DIR}/immutable" "${STORE_DIR}/mutable"

# ---------------------------------------------------------------- configuration
# Seeded once, then owned by the administrator. /app/code is read-only at runtime, so
# the editable copy has to live under /app/data. This is also where JWT authentication
# is configured; see POSTINSTALL.md.

if [[ ! -f "${CONFIG_DIR}/local.toml" ]]; then
    echo "==> Seeding default configuration into ${CONFIG_DIR}"
    cp /app/code/config/local.toml "${CONFIG_DIR}/local.toml"
else
    echo "==> Existing configuration found at ${CONFIG_DIR}/local.toml, leaving it alone"
fi

# Guard the store-path trap explicitly rather than trusting the seed. An administrator
# who edits local.toml and removes the pinned paths gets a server that silently writes
# into a temporary directory, and loses everything on the next reboot.
if ! grep -q '^path = "/app/data/store/immutable"' "${CONFIG_DIR}/local.toml" \
   || ! grep -q '^path = "/app/data/store/mutable"' "${CONFIG_DIR}/local.toml"; then
    echo "!!! WARNING: ${CONFIG_DIR}/local.toml does not pin both store paths into /app/data."
    echo "!!! With unpinned paths the server writes into the system temporary directory,"
    echo "!!! which a reboot can clear, and Cloudron will not back the data up."
    echo "!!! Restore the [immutable_store.local] and [mutable_store.local] path values."
fi

# ---------------------------------------------------------------- TLS
# The Cloudron tls addon supplies the certificate and key read-only at /etc/certs, owned
# by root. Both public endpoints terminate their own TLS on 41337; nginx only fronts the
# HTTP health port. Without a real certificate the QUIC endpoint self-signs an ephemeral
# one for localhost and no ordinary client can connect.
#
# The addon's key is NOT readable by the unprivileged app user. Measured 2026-08-04: the
# server starts, then dies with "malformed private key: I/O error: Permission denied".
# So the material is copied while still root, into tmpfs, and handed to the app user.
# Same approach as our Prosody package, which copies into /app/data/certs; /run is used
# here instead so that private key material never enters a backup.
#
# Re-done on every boot, never cached. The addon restarts the app on renewal, so this
# is also what picks up a renewed certificate.
#
# The addon may not have provisioned by the very first boot, so poll briefly before
# giving up. Exiting non-zero restarts the app, which picks the certificate up later.

for _ in $(seq 1 30); do
    [[ -f "${CERT_SRC}/tls_cert.pem" && -f "${CERT_SRC}/tls_key.pem" ]] && break
    sleep 1
done

if [[ ! -f "${CERT_SRC}/tls_cert.pem" || ! -f "${CERT_SRC}/tls_key.pem" ]]; then
    echo "!!! FATAL: TLS material absent from ${CERT_SRC} after 30s."
    echo "!!! The 'tls' addon must be declared in CloudronManifest.json and provisioned."
    exit 1
fi

mkdir -p "${CERT_DIR}"
cp -L "${CERT_SRC}/tls_cert.pem" "${CERT_FILE}"
cp -L "${CERT_SRC}/tls_key.pem" "${PKEY_FILE}"
chown -R cloudron:cloudron "${CERT_DIR}"
chmod 0755 "${CERT_DIR}"
chmod 0644 "${CERT_FILE}"
chmod 0640 "${PKEY_FILE}"

# Verify AS THE APP USER, not as root. Checking readability as root is the bug this
# guard originally had: it reported success while the server could not read the key.
if ! gosu cloudron:cloudron test -r "${CERT_FILE}" || ! gosu cloudron:cloudron test -r "${PKEY_FILE}"; then
    echo "!!! FATAL: the cloudron user cannot read the copied TLS material."
    echo "!!!   ${CERT_FILE}: $(stat -c '%A %U:%G' "${CERT_FILE}")"
    echo "!!!   ${PKEY_FILE}: $(stat -c '%A %U:%G' "${PKEY_FILE}")"
    exit 1
fi
echo "==> TLS material staged for the app user: $(stat -c '%A %U:%G' "${PKEY_FILE}") ${PKEY_FILE}"

# ---------------------------------------------------------------- ownership
# Re-asserted on every boot, not only on first run. The recursive pass over the store is
# guarded, because a content-addressed store of large binary assets can hold a very large
# number of files and an unconditional chown -R would grow the boot time without bound.

chown cloudron:cloudron /app/data "${CONFIG_DIR}" "${STORE_DIR}"
chown -R cloudron:cloudron "${CONFIG_DIR}"
chmod 700 "${CONFIG_DIR}"

if [[ "$(stat -c '%U' "${STORE_DIR}/immutable")" != "cloudron" \
   || "$(stat -c '%U' "${STORE_DIR}/mutable")" != "cloudron" ]]; then
    echo "==> Store ownership wrong, re-asserting recursively (may take a while on a large store)"
    chown -R cloudron:cloudron "${STORE_DIR}"
else
    echo "==> Store ownership already correct, skipping the recursive pass"
fi

# ---------------------------------------------------------------- run
# exec so that SIGTERM reaches the server rather than this script.
# LORE_ENV defaults to "local", so local.toml in the config directory is the layer applied
# over the defaults baked into the binary.

echo "==> Starting loreserver ($(/app/code/bin/loreserver --version))"
exec gosu cloudron:cloudron /app/code/bin/loreserver --config "${CONFIG_DIR}"

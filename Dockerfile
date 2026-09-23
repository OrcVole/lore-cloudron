# Lore Server for Cloudron.
#
# The binary is fetched from the pinned upstream release, not compiled. Upstream's own
# lore-server/Dockerfile compiles from source and needs several GB of RAM; the released
# binary links cleanly against cloudron/base with no additional packages, verified with
# the dynamic linker on 2026-08-04:
#   linux-vdso, libgcc_s, libm, libc, ld-linux-x86-64 -- all present on the base.
#
# linux/amd64 only. The aarch64 Linux asset is built for Graviton3 with SVE
# (...-neoverse-512tvb...) and is not a general arm64 build.

FROM cloudron/base:5.1.0@sha256:1c0666c9abe9e2090d33686826d4e97769b799124573118d41e0d7485135748e AS fetch

ARG LORE_VERSION=0.10.0
# sha256 of loreserver-v0.10.0-x86_64-unknown-linux-gnu.tar.gz, 15,908,281 bytes.
ARG LORE_SHA256=bf589c3946cd1078d702e7116d35d2d8e3fc4e1964d92237bc073a64528a01a3

# Pin the exact filename. The debug asset (lore-debug-...) is 353 MB and sorts adjacent
# to the 15 MB one wanted here, and the CLI asset (lore-...) sorts adjacent too.
RUN mkdir -p /build && cd /build \
    && curl -fsSL -o loreserver.tar.gz \
        "https://github.com/EpicGames/lore/releases/download/v${LORE_VERSION}/loreserver-v${LORE_VERSION}-x86_64-unknown-linux-gnu.tar.gz" \
    && echo "${LORE_SHA256}  loreserver.tar.gz" | sha256sum -c - \
    && tar -xzf loreserver.tar.gz \
    && chmod +x loreserver \
    && ./loreserver --version

FROM cloudron/base:5.1.0@sha256:1c0666c9abe9e2090d33686826d4e97769b799124573118d41e0d7485135748e

# TRAP: the release tarball ships loreserver as rw-r--r--, with no exec bit. Running it
# without chmod fails with "Permission denied", which misreads as a mount or security
# fault. The chmod happens in the fetch stage above; COPY --from preserves the mode.
COPY --from=fetch /build/loreserver /app/code/bin/loreserver
COPY --from=fetch /build/LICENSE.txt /app/code/UPSTREAM-LICENSE.txt
COPY --from=fetch /build/THIRD-PARTY-NOTICES.txt /app/code/THIRD-PARTY-NOTICES.txt

# Seed configuration. start.sh copies this into /app/data/config on first boot so an
# administrator can edit it; /app/code is read-only at runtime.
COPY local.toml /app/code/config/local.toml

COPY start.sh /app/code/start.sh
RUN chmod +x /app/code/start.sh

# CMD, never ENTRYPOINT: ENTRYPOINT breaks Cloudron debug mode.
CMD [ "/app/code/start.sh" ]

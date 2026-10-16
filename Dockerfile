# Lore Server for Cloudron.
#
# The binary is fetched from the pinned upstream release, not compiled. Upstream's own
# lore-server/Dockerfile compiles from source and needs several GB of RAM; the released
# binary links cleanly against cloudron/base with no additional packages, verified with
# the dynamic linker on 2026-08-04:
#   linux-vdso, libgcc_s, libm, libc, ld-linux-x86-64 -- all present on the base.
# Rechecked on cloudron/base 6.0.0 (Ubuntu 26.04) on 2026-10-16: the fetch stage below fails
# the build if ldd reports any library as not found.
#
# linux/amd64 only. The aarch64 Linux asset is built for Graviton3 with SVE
# (...-neoverse-512tvb...) and is not a general arm64 build.

FROM docker.io/cloudron/base:6.0.0@sha256:9bed4c8fa880645f8e669041ee28febe941481d00e9445e3e5a5483cb541d09b AS fetch

ARG LORE_VERSION=0.10.1
# sha256 of loreserver-v0.10.1-x86_64-unknown-linux-gnu.tar.gz, 16,368,874 bytes.
ARG LORE_SHA256=65b76ff56d8262c26f036e4a8db1df58c5c29d80ec1a49920f137ff6d0767ebd

# Pin the exact filename. The debug asset (lore-debug-...) is 353 MB and sorts adjacent
# to the 15 MB one wanted here, and the CLI asset (lore-...) sorts adjacent too.
RUN mkdir -p /build && cd /build \
    && curl -fsSL -o loreserver.tar.gz \
        "https://github.com/EpicGames/lore/releases/download/v${LORE_VERSION}/loreserver-v${LORE_VERSION}-x86_64-unknown-linux-gnu.tar.gz" \
    && echo "${LORE_SHA256}  loreserver.tar.gz" | sha256sum -c - \
    && tar -xzf loreserver.tar.gz \
    && chmod +x loreserver \
    && ./loreserver --version \
    && ! ldd ./loreserver | grep -q 'not found'

FROM docker.io/cloudron/base:6.0.0@sha256:9bed4c8fa880645f8e669041ee28febe941481d00e9445e3e5a5483cb541d09b

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

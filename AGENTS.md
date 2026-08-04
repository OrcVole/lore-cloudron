# AGENTS.md — working contract for this package

Settled decisions. If you are picking this repository up, read this before changing anything, and
add to it when you settle something new. A decision recorded here has already cost someone an
argument or a debugging session.

## What this is

A community Cloudron package for Lore Server, Epic Games' content-addressed version control system
for very large binary assets. Headless: no web interface, driven by the `lore` CLI and SDKs.

| | |
| --- | --- |
| Manifest id | `io.github.orcvole.lore` |
| Image | `ghcr.io/orcvole/lore-cloudron`, tagged `<upstreamVersion>-<pkg-rev>` |
| Upstream | https://github.com/EpicGames/lore, MIT |
| Base | `cloudron/base:5.0.0` pinned by digest |
| Architecture | `linux/amd64` only |

## Settled decisions

**Fetch the binary, do not compile.** Upstream's own server Dockerfile compiles from source and
wants several gigabytes of RAM. The released binary links cleanly against the base with no extra
packages. Pin the exact asset filename and its SHA-256.

**`linux/amd64` only.** The aarch64 Linux asset is `-neoverse-512tvb`, built for Graviton3 with SVE.
It is not a general arm64 build and must not be treated as one.

**`chmod +x` after extraction, always.** The release tarball ships the binary `rw-r--r--`. Removing
that step produces a `Permission denied` at start-up that reads like a mount or security fault.

**TLS material is staged into `/run`, never used in place.** The `tls` addon's key is root-owned and
unreadable by the `cloudron` user; the server starts and then dies on `malformed private key`.
`start.sh` copies it while still root, chowns to the app user, sets the key to `0640`, and verifies
readability **as that user** via `gosu`. Checking as root is the bug this guard originally had, and
it reported success while the server could not read the key.

`/run` rather than `/app/data` deliberately: private key material must not enter a backup.

**`verify_client_certs = false` explicitly on both public endpoints.** The gRPC compile-time default
is `true`, which upstream defines as requiring mutual TLS, and an ordinary client has no certificate.
Do not remove these lines and do not rely on the default. See ADR 0001.

**No `cert_chain`.** It is the CA bundle for verifying client certificates, and no endpoint verifies
them.

**No certificate block on `[server.http]`.** Cloudron's nginx terminates TLS for `httpPort`.

**Internal endpoints stay disabled.** `quic_internal` and `grpc_internal` require mutual TLS and,
unlike the public endpoints, enforce the `cert_chain` requirement at startup. Single-node has no use
for replication.

**All three store paths pinned into `/app/data`.** Unconfigured, Lore derives them under the system
temporary directory, which upstream says a reboot can clear and which is not backed up. `start.sh`
re-checks this on every boot and warns loudly if an edited config has dropped the pins.

Do not "tidy" the store paths on an existing install. The server appends a second directory level of
its own (`store/immutable/immutable/`), and changing the configured paths orphans the data.

**Configuration is seeded once into `/app/data/config`, then left alone.** `/app/code` is read-only
at runtime, so the administrator-editable copy has to live in the data directory. Package updates do
not overwrite it.

**The recursive `chown` over the store is guarded.** Doctrine says re-assert ownership every boot; an
unconditional recursive pass over a content-addressed store of large binaries would grow boot time
without bound. The guard checks both store roots and re-asserts when either is wrong.

**The data plane ships unauthenticated**, as upstream ships it. Both hardening paths live in
`POSTINSTALL.md`. Do not invent credentials.

## Things that are known and unresolved

- **Does `verify_client_certs = true` actually break a client?** Upstream says it requires mutual
  TLS; an `openssl s_client` probe saw no client-certificate request and completed the handshake.
  Needs a real `lore` client. Nothing depends on the answer, but it belongs in `FOR-UPSTREAM.md`.
- **Does `lore repository gc` churn directories during a live backup?** This is the ClickHouse
  `tmp_merge` failure class and can abort an entire server's backup run, not just this app's. If it
  does, the immutable store moves to a `persistentDirs` path with a `backupCommand`.
- **Does the in-memory lock store lose locks across a restart?** Documented, not yet observed.

## Traps for the next person

- **The debug release asset is over twenty times the size** of the one you want and sorts adjacent to
  it, as does the CLI asset. Pin the exact filename.
- **`minBoxVersion` is `9.2.0`, and do not raise it to 10.0.0.** `OPERATING-DEFAULTS.md` §4 says the
  community store demands ≥ 10.0.0. **No such Cloudron version exists**; 9.2.0 is current. Setting
  10.0.0 makes the package uninstallable everywhere and produces
  `400 App version requires a new platform version` at install. That happened here, and it was then
  rationalised into four documents before being caught. See the retraction in `docs/DEBUGGING.md`.
- **A rebuilt image is a different digest.** Gates passed by a different digest prove nothing about
  this one. Rebuild means restart the ladder at gate 0.
- **Something must drive it the way a client would.** This package has no browser surface, so no
  rendering check and no status-code check can find a broken data plane. Gate 2 must connect a real
  `lore` client over gRPC/TCP.

## House rules

British spelling. No em dashes. No contractions in repository prose. Commit solely as
`OrcVole <Most+github@OrcadianVole.com>`, with no `Co-Authored-By`, no generated-with trailer and no
tool attribution anywhere. Public repository carries techniques only: no real domains, no inventory
of what else runs on the rig, no internal hostnames.

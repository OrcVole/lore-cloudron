# Lore Server for Cloudron

A community Cloudron package for [Lore](https://github.com/EpicGames/lore), Epic Games' open-source
version control system for very large binary assets.

Lore is written in Rust, MIT licensed, and content-addressed with BLAKE3 and Zstandard compression.
It is a **headless server**: there is no web interface, and the service is driven by the `lore`
command-line client and the language SDKs. Upstream's roadmap lists a web client as committed for
2027, with a VS Code plugin in progress before that.

| | |
| --- | --- |
| Upstream | <https://github.com/EpicGames/lore> |
| Upstream version packaged | 0.8.6 |
| Package version | 0.1.0 |
| Licence | MIT, both upstream and this packaging |
| Architecture | `linux/amd64` only, see below |

## There is no web interface, and the Open button returns a 404

Worth stating before anything else, because it is the first thing a user meets. Cloudron requires an
`httpPort` and puts an **Open** button beside every installed application. Lore's HTTP endpoint
serves exactly one path, `/health_check`, so that button returns an empty **404**. Nothing is
broken; there is simply nothing to open.

All work happens through the `lore` command-line client against port 41337. `docs/FOR-UPSTREAM.md`
asks upstream to consider answering `/` with a short informational response, which would fix this
for every hosted deployment rather than only this package.

Upstream's roadmap commits to a web client in **2027**, with a VS Code plugin in progress before
that. When it arrives this package will need revisiting rather than updating; `AGENTS.md` records
what changes.

## Topology

Three listeners, and only one of them is an ordinary web port:

| Endpoint | Port | Transport | Fronted by Cloudron's proxy | Terminates its own TLS |
| --- | --- | --- | --- | --- |
| QUIC, the data plane | 41337 | UDP | no, published directly | yes |
| gRPC, the service API | 41337 | TCP | no, published directly | yes |
| HTTP, health check only | 41339 | TCP | yes, this is `httpPort` | no |

TCP and UDP share the number 41337 because they are different protocols. Both must stay on the
**same** number: a client is configured with one address and expects both transports there.

The internal replication endpoints (`quic_internal`, `grpc_internal`) require mutual TLS, are
disabled by default, and stay disabled here. Single-node has no use for them.

## TLS, and why this package needs the `tls` addon

The QUIC and gRPC listeners are published straight onto the host, so Cloudron's reverse proxy never
sees them and cannot terminate TLS on their behalf. Lore therefore has to present a certificate
itself. Left alone it self-signs an ephemeral one for `localhost`, regenerated on every restart,
which no ordinary client can trust.

This package declares the **`tls` addon**, which supplies the certificate Cloudron already manages
for the application's own domain. A client connects and trusts it with no configuration and no
manual trust step.

Two details that are not obvious, both recorded in `docs/decisions/`:

- The addon's material is root-owned and **not readable by the unprivileged application user**, so
  `start.sh` stages a copy into `/run` on every boot, owned by the app user with the key at mode
  `0640`. `/run` rather than the data directory, so private keys never enter a backup.
- Client-certificate verification is switched **off** explicitly on both public endpoints. The gRPC
  endpoint's compile-time default is on, which upstream defines as requiring mutual TLS, and an
  ordinary client has no certificate to present.

## Storage, and the trap this package exists to close

Lore keeps three stores: immutable content fragments, mutable branch pointers, and locks. **With no
configuration the local stores are derived under the system temporary directory, which upstream says
plainly a reboot can clear.**

The shipped `local.toml` pins them inside the application's data directory so they persist and are
captured by backups. `start.sh` re-checks this on every boot and logs a loud warning if an edited
configuration has dropped the pinned paths.

The lock store is held **in memory**. Locks do not survive a restart, and certificate renewal
restarts the application. Acceptable on a single node, but worth knowing.

## Authentication

**The data plane ships unauthenticated**, as upstream ships it. Lore supports optional JWT
verification against a JWKS endpoint; the client-side token flow is Lore's own, so this is not
Cloudron single sign-on and users do not log in through the dashboard.

`POSTINSTALL.md` documents the two hardening paths: configure JWT, or close the published ports.

## Configuration

`start.sh` seeds `local.toml` into the application's data directory on first boot and leaves it
alone afterwards, so an administrator can edit it through the dashboard file manager. Any scalar can
also be overridden with a `LORE__`-prefixed environment variable, for example
`LORE__IMMUTABLE_STORE__LOCAL__PATH`.

## Building

The binary is fetched from the pinned upstream release and checked against a recorded SHA-256, not
compiled. Upstream's own server Dockerfile compiles from source and wants several gigabytes of RAM;
the released binary links cleanly against `cloudron/base` with no additional packages.

```bash
cloudron build
```

`linux/amd64` only. Upstream's aarch64 Linux asset is built for Graviton3 with SVE and is not a
general arm64 build.

**The release tarball ships the binary without an execute bit.** The Dockerfile sets it. Removing
that step produces a `Permission denied` at start-up that reads like a mount or security fault and
is neither.

## Bumping the upstream version

1. Find the new release and its `loreserver-vX.Y.Z-x86_64-unknown-linux-gnu.tar.gz` asset. Pin the
   exact filename: the debug asset is over twenty times the size and sorts adjacent to it, as does
   the CLI asset.
2. Update `LORE_VERSION` and `LORE_SHA256` in the `Dockerfile`, and `upstreamVersion` in
   `CloudronManifest.json`.
3. Add a `CHANGELOG.md` entry and bump `version`.
4. Rebuild and run the gate ladder from gate 0. A rebuilt image is a different digest, and gates
   passed by a different digest prove nothing about this one.

A major upstream bump is a fresh packaging round, not an update.

## Documentation

- `docs/decisions/` numbered architecture decision records
- `docs/DEBUGGING.md` gate evidence and invariants
- `docs/PACKAGING-NOTES.md` the verified-versus-assumed log
- `docs/FOR-CLOUDRON.md` platform observations from packaging this
- `docs/FOR-UPSTREAM.md` what would make Lore easier to package

## Licence

MIT. See `LICENSE`. Lore itself is MIT by Epic Games, Inc.; its licence and third-party notices ship
inside the image at `/app/code/UPSTREAM-LICENSE.txt` and `/app/code/THIRD-PARTY-NOTICES.txt`.

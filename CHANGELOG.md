[0.2.2]

- Base image cloudron/base 5.1.0 to 6.0.0 (Ubuntu 26.04, glibc 2.43). The package installs no apt packages and ships no ffmpeg, so there is no application change from the OS move; the released binary links cleanly (checked with ldd at build time).
- Upstream EpicGames/lore 0.10.0 to 0.10.1.
- Auth, opt-in only: a `[server.auth]` without `[environment.endpoint] auth_url` (authorising from token claims) now refuses to start unless `[server.auth.oidc]` is present with the provider's public `client_id`. Tier 2 (`resource_claim` set) also needs `resource_template` or `scope_template` there, and Tier 1 must set neither. New optional `[server.auth] jwt_typ` accepts a string or array of JWT `typ` header values; when set, tokens without a matching `typ` are rejected. This package ships with auth off and its seeded configuration is unchanged, so nothing changes unless you enabled `[server.auth]` in your own `/app/data/config/local.toml`; if you did, add the `oidc` table before updating.
- Logs default to `warn` rather than `error`; `RUST_LOG=error` restores the old output.
- Documented: Lore flushes new pushes to disk about every 10 seconds, so a backup taken within a few
  seconds of a push can miss it (measured 2026-10-16: a push 4 s before a backup was not in it, one 35 s
  before was). Scheduled backups are unaffected; wait half a minute after a push before a manual backup.
- New low disk space warning for the local stores (`[server.local_store_monitor]`, 10 GiB threshold, checked every 30 seconds).
- Client-facing changes: the C API and `lore.thin_client.v1` diff messages changed shape (rebuild consumers against the new `lore.h`); several `lore sync`, `lore stage` and `lore push` fixes.

[0.2.1]

- Upstream EpicGames/lore 0.9.0 to 0.10.0.

- Client-facing breaking change: partial-hash revision identifiers are refused as `NotSupported`. Name revisions by their full 64-character hash, `[branch]@<number>`, `[branch]@LATEST` or `<branch>@<hash>`
- Renamed setting: `connection_message_limit` under `[server.quic]` and `[server.quic_internal]` is now `stream_message_limit` and applies per stream. This package does not set it; if you set it in your own configuration, rename it or it is silently ignored
- Auth: authorisation moves to OIDC and OAuth 2.0; `[server.auth]` gains new fields (permission_claim, resource_claim, identity_claim, resource_id_template, resource_wildcard, baseline_access) with `jwt_issuer` now accepting a list. Opt-in only, no action required if auth is not configured
- Config: `lock_service.max_encoding_message_size` moves under `[server.grpc_public_services.lock_service.general]`. No action needed as our local.toml does not customise this key
- Storage: Oodle is refused for new fragments; existing Oodle content still reads with lazy re-encoding to Zstd
- New settings with sensible defaults: `permit_timeout_ms` (default 100ms) under `[server.quic]` and `[server.quic_internal]`, and `connection_inflight_limit`
- Base image cloudron/base 5.0.0 to 5.1.0: the Ubuntu 24.04.4 point release, with its OS security
  updates. Same Ubuntu 24.04 release and glibc 2.39.

[0.2.0]

- Update lore-server 0.8.6 -> 0.9.0
- Security: fixes prevent silent authentication bypass from an unmigrated credential store, credential exposure via the process command line, arbitrary content-type injection and stored XSS on presigned-URL redeems, a JWT verification error oracle, directory traversal in repository path components, unauthorised repository metadata access, denial of service via oversized S3 payloads, and replay of caller-supplied identity-token authorisation results
- Breaking: auth tokens move to tokenstore.toml (re-run lore login); DynamoDB fragment metadata table replaced by fragment state table (full stop/start rollout required); timestamps in lore.model.v1 and lore.thin_client.v1 now Unix epoch milliseconds; C API error codes, enum discriminants and LoreSharedStoreMode updated; replication protocol ExistsBatch replaced by batch Query (peers must roll together); LORE_MAX_THREAD is now an absolute cap; should_cache_query_results renamed to cache_metadata; allow_partial_fragment removed; parent_entry renamed to parent_entry_index; presigned-URL content-type deny-by-default allowlist enforced; lore layer remove now requires --force; authoritative: true makes corrupt mutable-store buckets a hard error
- Other: routine features and fixes across two release chunks
- No packaging changes: auth topology, workspace layout and secrets handling unchanged; base and built images digest-pinned

[0.1.0]

- First release of the Lore Server package.
- Lore Server 0.8.6, fetched from the pinned upstream release and verified by checksum.
- QUIC over UDP 41337 and gRPC over TCP 41337, both presenting the Cloudron-managed certificate for this app's domain, so clients need no manual trust configuration.
- HTTP 41339 serves the health check.
- All three stores pinned inside the app's data directory, so they persist and are backed up. Left unconfigured, Lore writes them into the system temporary directory, which a reboot can clear.
- The data plane ships without authentication, as upstream does. Read the post-installation notes before exposing it.

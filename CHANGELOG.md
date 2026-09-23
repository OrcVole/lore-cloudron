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

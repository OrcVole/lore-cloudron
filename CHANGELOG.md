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

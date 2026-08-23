[0.1.0]

- First release of the Lore Server package.
- Lore Server 0.8.6, fetched from the pinned upstream release and verified by checksum.
- QUIC over UDP 41337 and gRPC over TCP 41337, both presenting the Cloudron-managed certificate for this app's domain, so clients need no manual trust configuration.
- HTTP 41339 serves the health check.
- All three stores pinned inside the app's data directory, so they persist and are backed up. Left unconfigured, Lore writes them into the system temporary directory, which a reboot can clear.
- The data plane ships without authentication, as upstream does. Read the post-installation notes before exposing it.

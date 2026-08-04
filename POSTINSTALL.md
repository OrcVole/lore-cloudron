## Read this before you push anything

### 1. The data plane is unauthenticated by default

Lore's authentication is optional JWT verification against a JWKS endpoint, and it is switched off in every configuration upstream ships. This package does not change that. **Anyone who can reach port 41337 can read and write every repository on this server.**

There are two ways to harden it, and you should pick one before putting real work here:

**Configure JWT authentication.** Edit `/app/data/config/local.toml` through the dashboard file manager, uncomment the `[server.auth]` block, and point it at your identity provider's issuer, audience and JWKS endpoint. Restart the application afterwards. Note that the client-side token flow is Lore's own, so this is not Cloudron single sign-on and your users will not log in through the Cloudron dashboard.

**Or close the ports.** If this server only needs to be reachable from inside your own network, turn off the TCP and UDP port forwarding for this app in the Cloudron dashboard and reach it another way, such as over your VPN.

### 2. Keep both port numbers the same

The gRPC (TCP) and QUIC (UDP) endpoints must be published on the **same** port number. Clients are configured with a single address and expect to find both transports there.

Cloudron lets you change each one independently in the dashboard, and nothing will warn you if they drift apart. If you move one, move the other.

### 3. Connecting a client

Install the `lore` CLI from the upstream release page, then point it at this server on the port you published, for example `myapp.example.com:41337`.

You do not need to configure certificate trust. The server presents the certificate Cloudron manages for this application's own domain, and it is renewed automatically.

### 4. Two behaviours worth knowing

**Certificate renewal restarts the application.** That is how Cloudron's TLS integration works, and it is what keeps the certificate valid. Lore's lock store is held in memory, so every lock is released at that moment and any push in flight has to be retried. On a single-node install this is a brief interruption rather than a correctness problem, but it is not nothing if you are mid-operation.

**Do not edit the store paths.** `/app/data/config/local.toml` pins the immutable and mutable stores inside the application's data directory. If those paths are removed, Lore falls back to writing into the system temporary directory, which a reboot can clear and which Cloudron does not back up. The application logs a loud warning at start-up if it detects this, but by then you have already changed it.

### 5. Backups

Everything Lore persists lives under the application's data directory, so ordinary Cloudron backups capture it. For an independent copy in a format that does not depend on Lore's on-disk layout, `lore repository clone` reconstructs a repository over the wire, and `lore repository verify state` and `lore repository verify fragment` check integrity.

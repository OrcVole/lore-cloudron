`<upstream>0.10.0</upstream>

Lore is a centralised, content-addressed version control system built by Epic Games for very large binary assets: the kind of files that make ordinary version control fall over. It is written in Rust, MIT licensed, and designed for teams working with game and entertainment content measured in gigabytes rather than kilobytes.

### This is a headless server

Lore has no web interface, and this package does not pretend otherwise. The server is driven entirely by the `lore` command-line client and the language SDKs. If you are looking for something to click around in, this is not it. What you get is a fast, authenticated-optional data plane that a machine can drive.

That is the correct shape for this kind of service rather than a shortcoming. Upstream's roadmap does list a web client as committed for 2027, with a VS Code plugin in progress before that, so a browser surface is coming; it simply is not here yet.

### How clients reach it

Two public endpoints share port 41337, one over TCP and one over UDP, because they are different protocols:

- **QUIC over UDP 41337** is the high-performance data plane, used for pushing and cloning content.
- **gRPC over TCP 41337** is the full service API: administration, storage, revisions, repositories, environments, locks and notifications.

Both terminate their own TLS using the certificate Cloudron manages for this application, so an ordinary `lore` client trusts the server with no manual configuration and no certificate wrangling.

A third port, HTTP 41339, serves only a health check and is what the Cloudron dashboard talks to.

### What it stores, and where

Content is addressed by BLAKE3 hash and compressed with Zstandard. The package pins all three stores (immutable content fragments, mutable branch pointers, and locks) inside the application's data directory, so everything is captured by Cloudron's backups. This matters more than it sounds: left unconfigured, Lore writes its stores into the system temporary directory, which a reboot can clear.

### Before you install

**The data plane ships without authentication.** Lore supports JWT verification against a JWKS endpoint, but it is disabled in every configuration upstream ships, and this package does not invent credentials for you. Anyone who can reach port 41337 can read and write your repositories. Read the post-installation notes before exposing this to an untrusted network.

Lore is pre-1.0. Upstream commits that content you commit now stays readable by every future release, so your history is not at risk, but APIs and protocols can still change before 1.0.
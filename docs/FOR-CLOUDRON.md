# Notes for the Cloudron team

Verified platform observations collected while packaging Lore Server, a headless version-control
server whose primary endpoints are raw TCP and UDP ports rather than HTTP. That shape is unusual
enough that it exercised parts of the platform most packages never touch, so these notes are mostly
about the `tls` addon and about multi-protocol port publishing.

Offered as observations, not complaints. The platform did everything this package needed.

## 1. The `tls` addon's private key is not readable by the application user

The addon documentation says:

> "The certificate and key are available as read-only files at `/etc/certs/tls_cert.pem` and
> `/etc/certs/tls_key.pem`."

What it does not say is who can read them. Measured: the material is owned by `root` with the key
restricted, and an application running unprivileged as `cloudron` cannot read the key.

For an app that terminates its own TLS, this is the whole point of the addon, and the failure mode is
poor. Lore starts, stages its listeners, and then dies with:

```
Endpoint returned error: Permission denied (os error 13), triggering shutdown
malformed private key: I/O error: Permission denied (os error 13)
```

Nothing in that message points at file ownership, and the app had already logged a successful
start-up. A packager who checks readability from `start.sh` before dropping privileges, which is the
natural thing to do, gets a **passing check**, because `start.sh` runs as root at that point.

The workaround is straightforward once understood: copy the material while still root, `chown` it to
the app user, and set the key to `0640`. Our Prosody package does this too, so it is an established
pattern rather than a one-off. We stage into `/run` rather than `/app/data`, specifically so private
key material never enters a backup.

**Two suggestions, either would help:**

- Make the addon's material group-readable by the app's group, so the documented "read-only files"
  are actually readable by the application that requested them.
- Or add one sentence to the addon documentation stating the ownership and mode, and noting that an
  unprivileged app must copy the material. That converts a debugging session into a paragraph.

## 2. `tls` addon manifest syntax is not documented

The addon documentation describes what the addon provides but shows no manifest declaration for it.
We used

```json
"addons": { "localstorage": {}, "tls": {} }
```

by analogy with every other addon, and it was accepted. Worth one code block in the docs, since
every other addon has one.

## 3. TCP and UDP may share a port number, and it would be good to say so

Lore listens on 41337 for both QUIC (UDP) and gRPC (TCP). The manifest reference documents
`tcpPorts` and `udpPorts` but does not state whether the same number may appear in both. It can, and
the CLI accepted it without complaint:

```
Port LORE_GRPC_PORT: 41337
Port LORE_QUIC_PORT: 41337
```

For any protocol that offers a QUIC and a TCP transport on one advertised address, and there will be
more of them, this is the natural shape. One sentence in the manifest reference would save the next
packager an experiment.

A related observation: `defaultValue` is described as a UI recommendation and an administrator can
change each port independently. For a package where the two ports must stay on the same number,
there is no way to express that constraint in the manifest, so it lives in the post-install message
and hopes to be read.

## 4. A content-addressed store did not disturb a live backup, measured

Platform facts records a failure class where an application's own background file churn makes the
filesystem backup abort, taking the whole server's backup run with it. That was the single largest
risk we identified for this package, because Lore keeps a content-addressed store of many small
fragment and index files and runs incremental garbage collection by default since 0.8.4.

We tested it rather than designing around it. An app-scoped backup was started while a client
`commit` was streaming 380 MB of new fragments into the store, and the overlap was verified by
sampling the store size during the backup rather than assumed:

```
store at backup start : 783,044 KiB   (writer confirmed alive)
store at backup end   : 1,171,800 KiB
growth DURING backup  : 388,756 KiB
BACKUP exit=0, 9,082 files, no error / vanished / changed complaints
```

The backup completed cleanly, and so did the concurrent write. A separate backup of a 259 MB store
walked 2,973 files without complaint.

The overlap check matters: two earlier attempts of ours reported a clean pass while overlapping the
backup with operations that write nothing server-side, and would have passed regardless. Anyone
repeating this measurement should assert that the store actually grew during the window.

**The consequence for packaging is real:** this app does not need `persistentDirs` and a
`backupCommand`, and plain `localstorage` is safe for it. We had been prepared to add both.

Two honest limits. This exercises the server's own write path, not the client-side
`lore repository gc` command, because the container ships only the server binary and has no CLI to
invoke it. And it is one application on one rig, so it is a data point rather than a general
clearance for content-addressed stores.

## 5. Things that worked exactly as documented

- Publishing raw TCP and UDP ports alongside an `httpPort` for the health check. The GitLab and
  Minetest pattern generalised cleanly to a package with no browser surface at all.
- On-server build from a source directory with no `dockerImage` in the manifest. The
  "No build detected. This package will be built on the server." line is a good, unambiguous success
  signal.
- `localstorage` giving a backed-up data directory with no ceremony.

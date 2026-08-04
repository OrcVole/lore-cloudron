# Notes for the Lore maintainers

Written while packaging Lore Server 0.8.6 for Cloudron, a self-hosting platform. Offered gratefully
and with evidence. Nothing here is a complaint: the server was pleasant to package, the configuration
reference is unusually good, and the forward-compatibility commitment on stored formats is exactly
the thing a packager needs to read before recommending an application to other people.

Everything below was measured on `loreserver-v0.8.6-x86_64-unknown-linux-gnu.tar.gz`
(SHA-256 `f0de84c6175a476f157754f57316be0346105be502c93fabb65bb908eab0e1e1`) running on Ubuntu 24.04
with glibc 2.39.

## 1. The release tarball ships `loreserver` without an execute bit

Extracting the archive produces:

```
-rw-r--r--  loreserver
```

so the obvious next step fails:

```
$ ./loreserver --version
bash: ./loreserver: Permission denied
```

`Permission denied` on a freshly extracted binary reads like a mount option, a security policy or a
container problem, and sends people looking in the wrong place. It cost us a debugging cycle even
though we were expecting trouble.

`install.sh --server` presumably chmods the binary, so anyone using the documented path never sees
this. It only bites people who consume the release asset directly, which is exactly what a packager
does.

**This is not specific to the server asset.** The CLI archive
(`lore-v0.8.6-x86_64-unknown-linux-gnu.tar.gz`, SHA-256
`a7aaeb32a15f6674a328e19096c48dcab5b29b283ba51d37abdadedd930812ad`) extracts `lore` as `rw-r--r--`
too, so anyone installing the client by hand rather than through `install.sh` hits the same thing.
It appears to be a property of the release packaging rather than of one target.

**Suggested fix:** set mode `0755` on the binaries inside the release archives. A one-line change in
the release packaging step, and it removes a papercut for every downstream packager and every user
who installs the CLI manually.

## 2. `verify_client_certs = true` on a public endpoint is a silent failure

The configuration reference says, of `verify_client_certs`:

> "Require client certificates (mutual TLS); `false` accepts unverified clients."

and of `cert_chain`:

> "Required on any endpoint with `verify_client_certs = true`; the internal endpoint enforces this at
> startup."

The qualifier "the internal endpoint" is doing a great deal of work, and it is easy to miss. The
**public** `[server.grpc]` endpoint defaults `verify_client_certs` to `true` and does **not** enforce
the `cert_chain` requirement at startup. We measured it: with `cert_file` and `pkey_file` set and no
`cert_chain`, the server starts normally, binds QUIC 41337, gRPC 41337 and HTTP 41339, creates its
store directories, and answers `/health_check` with 200.

For someone deploying this, that combination is invisible until a client fails to connect, and every
health check and monitoring probe stays green.

We also could not reproduce a client rejection with an `openssl s_client` probe against that
configuration: the TLS 1.3 handshake completed and the server requested no client-certificate CA
names. So we genuinely do not know whether `verify_client_certs = true` without a `cert_chain`
enforces mutual TLS, degrades to a no-op, or defers the check past the handshake. We ship `false`
explicitly and did not need to resolve it.

**Two suggestions, either of which would help:**

- Make the public endpoints enforce the `cert_chain` requirement at startup, exactly as the internal
  endpoint does. Failing loudly at boot is far kinder than failing at connection time.
- Or, if `true` without a `cert_chain` is genuinely a no-op, say so in the reference, because the
  current wording reads as a hard requirement.

## 3. A small documentation observation

`--help` describes `--env` as defaulting to `local`, which means `local.toml` is loaded with no flags
at all. That is convenient and we relied on it, but it took a run of `--help` to discover, because
the layering description in the configuration reference lists `<environment>.toml` generically
without noting which environment you get by default. Worth one sentence.

## 4. Things that made packaging easy, for balance

- **Static-ish linking.** The binary needs only `libgcc_s`, `libm` and `libc`. No runtime packages,
  no bundled interpreter, no surprises.
- **Config layering plus `LORE__` environment overrides.** Having both a file route and an
  environment route meant we could pick whichever suited the platform, rather than fighting the one
  we were given.
- **JSON logs to stdout.** Nothing to configure for a container platform.
- **The roadmap's forward-compatibility statement.** "Content you commit now stays readable by every
  future release" answered the single question that decides whether a pre-1.0 application can
  responsibly be offered to other people. We had initially deferred packaging Lore on the assumption
  that a `0.x` version number implied format instability. Reading the roadmap reversed that. Thank
  you for stating it plainly.

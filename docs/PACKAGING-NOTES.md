# Packaging notes

The verified-versus-assumed log, newest first. Every claim carries how it was established. A claim
that was inferred stays labelled inferred no matter how many documents repeat it.

---

## 2026-08-04 — initial packaging, Lore Server 0.8.6

### Verified by measurement

| Claim | How |
| --- | --- |
| Release asset SHA-256 is `f0de84c6175a476f157754f57316be0346105be502c93fabb65bb908eab0e1e1`, 15,908,281 bytes | `sha256sum`, `stat` |
| Tarball contains `loreserver`, `LICENSE.txt`, `THIRD-PARTY-NOTICES.txt` | `tar -tzf` |
| **The tarball ships the binary without an execute bit** (`rw-r--r--`) | `stat`, then `Permission denied` on execution |
| The binary needs only `libgcc_s`, `libm`, `libc`, all present on `cloudron/base:5.0.0` | `ldd` inside the base image |
| Binary reports `loreserver 0.8.6`, build `0.8.6+373` | ran `--version` |
| Upstream licence is MIT | GitHub API |
| QUIC binds UDP 41337, gRPC binds TCP 41337, HTTP binds TCP 41339 | `ss -lntup` in a running container |
| Port 41340 is **not** bound; internal endpoints are off by default | same |
| `GET /health_check` returns 200 | `curl` |
| Pinned store paths are honoured; the server appends a second directory level (`store/immutable/immutable/`) | `find` after boot |
| `--env` defaults to `local`, so `local.toml` loads with no flag | `--help` |
| There is no config-validate subcommand; booting is the only validator | `--help` |
| **The `tls` addon's key is root-owned and unreadable by the `cloudron` user** | server died with `malformed private key: I/O error: Permission denied` |
| Staging the material into `/run` with mode `0640` and app ownership fixes it | same fixture, re-run, server started and served |
| The gRPC endpoint presents the staged certificate over TLS 1.3 and requests **no** client-certificate CA names | `openssl s_client` |
| `test/secret-scan.sh` exits 1 on planted violations and 0 when clean | planted a box FQDN and a token name, observed both caught |
| Cloudron accepts a TCP and a UDP port on the same number (41337) | CLI echoed both at install |
| The rig runs Cloudron 9.2.0 | `/api/v1/cloudron/status` |

### Falsified

| Claim we held | Reality |
| --- | --- |
| `server.grpc` **refuses to start** without a `cert_chain` when `verify_client_certs = true` | **False.** It starts, binds all three ports and answers the health check. Upstream's reference says the *internal* endpoint enforces this at startup; our documents dropped the qualifier. Carried as "verified" in two files before being tested. |
| The logo to use is `Lore_TM_Black_V1.svg` (a wordmark) | `Lore_Icon_Black_V1.svg` exists and is the correct shape for a square tile |
| The pinned upstream version is 0.8.3 | 0.8.6 |

### Inferred, and still unresolved

| Claim | Why it is not verified |
| --- | --- |
| `verify_client_certs = true` on the public gRPC endpoint breaks ordinary clients | Still unverified, and now deliberately so. Gate 2 verified the **shipped** setting (`false`) end to end with a real client. Proving what `true` does would mean reconfiguring the live install to test a setting we do not ship. Left as an open question **for upstream**, asked in `FOR-UPSTREAM.md`, not as a package gap |
| The local lock store does not survive a restart | Documented as in-memory; not yet observed across a restart |
| `lore repository gc` may churn directories during a live backup | Not yet exercised. This is the ClickHouse `tmp_merge` failure class and can abort a whole server's backup run, so it is gate 3 work |

### Deliberate departures from doctrine, with reasons

| Departure | Reason |
| --- | --- |
| TLS material staged into `/run`, where our Prosody package uses `/app/data/certs` | `/run` keeps private key material out of every backup. Same technique otherwise |
| ~~Gates run against a lowered `minBoxVersion` while shipping `10.0.0`~~ | **WITHDRAWN.** There is no Cloudron 10.0.0; the current release is 9.2.0. `minBoxVersion` is now `9.2.0` on both, and the ladder tests the byte-identical shipping manifest. See the retraction in `DEBUGGING.md` |
| The store's recursive `chown` in `start.sh` is guarded by an ownership check rather than unconditional | Doctrine says re-assert on every boot. A content-addressed store of large binary assets can hold very many files, and an unconditional recursive pass would grow boot time without bound. The guard checks both store roots and re-asserts when either is wrong |

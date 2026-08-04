# Debugging and gate evidence

Invariants with a proof cell each. An inference is not evidence: a cell here holds a log line, a
hash, a status code, a socket listing or a counter, and enough of the recipe to repeat it at the next
version bump.

## Pre-gate evidence, established locally

These were measured against the locally built image before anything touched the rig, so they are not
gate results. They are recorded because each one caught or prevented a defect.

| Invariant | Proof | Recipe |
| --- | --- | --- |
| Binary matches the pinned release | `f0de84c6175a476f157754f57316be0346105be502c93fabb65bb908eab0e1e1`, 15,908,281 bytes | `sha256sum` the downloaded asset |
| Binary runs on the base with no added packages | `ldd` lists only `libgcc_s`, `libm`, `libc`, `ld-linux`; `--version` prints `loreserver 0.8.6` | `podman run --rm -v <dir>:/x cloudron/base:5.0.0 bash -c 'ldd /x/loreserver'` |
| Server binds all three endpoints | `udp 0.0.0.0:41337`, `tcp 0.0.0.0:41337`, `tcp 0.0.0.0:41339`; **41340 absent** | `ss -lntup` inside the running container |
| Health check answers | `http_code=200` | `curl -o /dev/null -w '%{http_code}' http://127.0.0.1:41339/health_check` |
| Store paths are honoured | `/app/data/store/immutable/immutable/{lock,index}`, `/app/data/store/mutable/mutable/{lock,version}` | `find /app/data/store -maxdepth 3` after boot |
| Server runs unprivileged | `ps -o user,comm -C loreserver` prints `cloudron loreserver` | as written |
| TLS is presented on the gRPC port | `subject=CN=<app domain>`, `Cipher is TLS_AES_256_GCM_SHA384` | `openssl s_client -connect <host>:41337` |
| No client certificate is demanded | zero occurrences of `Acceptable client certificate CA names` | same command, `grep -c` |
| Secret scan is a real gate | exit **1** with a planted box FQDN and a planted token name; exit **0** after removing them | `test/secret-scan.sh`, checking `$?` directly and not through a pipe |

### Failures deliberately observed

Per doctrine, an assertion is not trusted until its failure has been seen.

| Assertion | How it was broken | What was observed |
| --- | --- | --- |
| Secret scan catches box specifics | wrote a file containing the rig FQDN and the mirror host | `[anon] PLANTED-BOX.md:1:...`, exit 1 |
| Secret scan catches credential shapes | wrote a file containing a token variable name | `[anon] PLANTED-TOKEN.md:1:...`, exit 1 |
| TLS staging is required | ran with the addon's material in place, root-owned | `malformed private key: I/O error: Permission denied (os error 13)`, process shut down |
| The staging fix works | re-ran against the identical fixture | `-rw-r----- cloudron:cloudron /run/lore/certs/tls_key.pem`, server started, health 200 |

### A check that lied, and how it was caught

The first version of the TLS guard in `start.sh` tested `[[ -r "${PKEY_FILE}" ]]`. It **passed**, and
the server then died on that very file. `start.sh` runs as root at that point, so the check was
asking the wrong user. It now tests through `gosu cloudron:cloudron test -r`.

This is the canonical shape of the failure: a check that reports success without doing its work. It
was found only because the smoke test exercised the real start-up path rather than trusting the
guard.

## Gate ladder

Run against the throwaway install at `<app>-testing.<domain>`. Every gate runs against the same image
digest; a rebuild restarts the ladder at gate 0.

**The ladder runs against the byte-identical shipping manifest.** An earlier note here claimed
otherwise; that claim was withdrawn once `minBoxVersion` was corrected. See the retraction below.

| Gate | Status | Evidence |
| --- | --- | --- |
| 0 — install and first run | **PASS** | Installed to the throwaway subdomain, state `running`, `io.github.orcvole.lore@0.1.0`. Five consecutive external requests to `/health_check` returned 200 over 20 s. Start-up log shows `TLS material staged for the app user: -rw-r----- cloudron:cloudron /run/lore/certs/tls_key.pem`. Loaded config confirms `verify_client_certs: false` on both public endpoints and `cert_chain: None`. **Port 41337 reachable from off-rig, presenting a Let's Encrypt certificate with `Verify return code: 0 (ok)` over TLS 1.3, requesting no client certificate.** |
| 1 — auth | pending | Data plane is unauthenticated by design; the gate is that the documented posture matches observed behaviour |
| 2 — functional flows | pending | **Must connect a real `lore` client over gRPC/TCP.** No status-code check can see a broken data plane. Also settles whether `verify_client_certs = true` refuses a real client |
| 3 — update and restore | pending | Must use `lore repository verify state` and `verify fragment` as evidence, and must check whether `lore repository gc` churns directories during a live backup |
| 4 — memory | pending | `memoryLimit` is 1 GiB and untuned |

## Retraction: the `minBoxVersion` "limitation" was a self-inflicted bug

Recorded because the error was carried into four documents before it was caught, and because the
mechanism is more instructive than the mistake.

`OPERATING-DEFAULTS.md` §4 states that `minBoxVersion` must be **≥ 10.0.0** or the community store
rejects an app that installs perfectly for you. That was applied to this manifest without checking
whether such a version exists.

**It does not.** Cloudron's own releases API reports the current version as **9.2.0**, which is what
the rig runs. A `minBoxVersion` of `10.0.0` therefore declares a floor no box can satisfy, and the
package would have been uninstallable for everybody.

The first install attempt failed with `400 App version requires a new platform version`. That was the
platform telling the truth, and it was misread as a property of the rig rather than a defect in the
manifest. An elaborate "the shipping manifest cannot be tested on the available rig" limitation was
then written into `DEBUGGING.md`, `FOR-CLOUDRON.md`, `PACKAGING-NOTES.md` and `AGENTS.md` to
rationalise it, including a note addressed to the Cloudron team about an awkward position they had
not put anyone in.

It was caught only because the operator asked whether the rig should be updated, which prompted a
check of what the latest version actually is.

**The corrected value is `9.2.0`**, the version the package was tested on. Lower is not claimed
because lower is not tested.

**Two lessons worth carrying:**

- A rule in our own doctrine is an inherited claim like any other, and `OPERATING-DEFAULTS.md` §1
  already says to verify inherited claims before accepting a blocker. A rule that cites a version
  number should have that number checked against reality before it is obeyed.
- **A failing gate that gets explained rather than fixed is the dangerous case.** The install error
  was precise and correct. Writing a limitation section around it converted a five-second fix into
  four documents of confident, wrong prose.

`OPERATING-DEFAULTS.md` §4 needs correcting at round close. Either the 10.0.0 figure is simply wrong,
or it applies only to manifests using `packageUrl` (which this one does not) and the rule needs that
condition stated.

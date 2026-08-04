#!/bin/bash
# Generate CloudronVersions.json from CloudronManifest.json plus the repository's own files.
#
# Run at every version bump. Hand-editing this file is how the known failures happen.
#
# What the community/versions-url channel needs that a local build does not:
#   - file:// references cannot resolve remotely, so description, changelog and
#     postInstallMessage are INLINED as text rather than referenced.
#   - `icon` (a file:// path) becomes `iconUrl` (a real URL). iconUrl being non-empty is
#     what actually forces minBoxVersion >= 9.1.0.
#   - `mediaLinks` needs at least one entry, as real URLs.
#   - Each version entry needs all four of: manifest, creationDate (ISO-8601),
#     ts (Unix MILLISECONDS, as a JSON number not a string), publishState "published".
#     A file missing creationDate or publishState is rejected with "invalid ts in
#     <version>", an error that names the wrong field entirely.
#
# Usage: test/make-versions.sh [raw-base-url]

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
RAW="${1:-https://raw.githubusercontent.com/OrcVole/lore-cloudron/main}"

VER=$(jq -r '.version' CloudronManifest.json)
TS=$(date +%s000)
ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)

jq -n \
  --slurpfile m <(jq '.' CloudronManifest.json) \
  --rawfile desc DESCRIPTION.md \
  --rawfile chlog CHANGELOG.md \
  --rawfile post POSTINSTALL.md \
  --arg raw "$RAW" \
  --arg ver "$VER" \
  --arg iso "$ISO" \
  --argjson ts "$TS" '
  ($m[0]
    # KEEP .icon as file://logo.png. Deleting it produces
    # "Failed to get community app: 404 ... Could not resolve CloudronVersions.json
    # from URL", an error that points at the URL and says nothing about the missing
    # field. Verified against a published package of ours, which carries BOTH
    # icon (file://) and iconUrl (a real URL).
    | .description = $desc
    | .changelog = $chlog
    | .postInstallMessage = $post
    | .iconUrl = ($raw + "/logo.png")
    | .mediaLinks = [ ($raw + "/media-corpus.png"), ($raw + "/media-terminal.png") ]
  ) as $man
  | { versions: { ($ver): { manifest: $man, creationDate: $iso, ts: $ts, publishState: "published" } } }
' > CloudronVersions.json

echo "wrote CloudronVersions.json for $VER"

echo "== pre-flight: every entry must have all four fields, ts a NUMBER =="
jq -e '.versions | to_entries[]
       | select((.value.ts|type) != "number"
             or (.value.creationDate == null)
             or (.value.publishState != "published")
             or (.value.manifest == null))' CloudronVersions.json \
  && { echo "FAIL: entries above are malformed"; exit 1; } \
  || echo "  ok: all entries well-formed"

echo "== pre-flight: fields the community validator rejects when empty =="
for f in packagerName packagerUrl website contactEmail iconUrl httpPort healthCheckPath dockerImage; do
  v=$(jq -r --arg f "$f" ".versions[\"$VER\"].manifest[\$f] // empty" CloudronVersions.json)
  [ -n "$v" ] && printf '  ok   %-18s %s\n' "$f" "${v:0:64}" || { printf '  FAIL %s is empty\n' "$f"; exit 1; }
done
n=$(jq -r ".versions[\"$VER\"].manifest.mediaLinks | length" CloudronVersions.json)
[ "$n" -ge 1 ] && echo "  ok   mediaLinks         $n entr(y/ies)" || { echo "  FAIL mediaLinks empty"; exit 1; }

echo "== pre-flight: no file:// survived into the embedded manifest =="
jq -r ".versions[\"$VER\"].manifest | to_entries[] | select(.value|type==\"string\") | select(.value|startswith(\"file://\")) | .key" CloudronVersions.json \
  | grep . && { echo "  FAIL: file:// references cannot resolve remotely"; exit 1; } || echo "  ok: none"

echo "== pre-flight: changelog is in bracket format, not markdown headings =="
head -1 CHANGELOG.md | grep -qE '^\[' && echo "  ok: $(head -1 CHANGELOG.md)" || { echo "  FAIL: changelog must start [x.y.z]"; exit 1; }

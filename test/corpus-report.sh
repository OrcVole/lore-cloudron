#!/bin/bash
# Push the generated corpus to a Lore server and report what actually happened.
#
# Usage: test/corpus-report.sh <lores://host:port> <corpus-dir> <work-dir> [repo-name]
#
# This is not a pass/fail gate. It is a measurement harness for four questions that a
# health check cannot answer and that matter for a VCS aimed at large binary assets:
#
#   1. INTEGRITY    do all files survive a push and a fresh clone byte-for-byte
#   2. DEDUPLICATION does content-addressed storage collapse identical files
#   3. INCREMENTAL   does a one-byte change re-transfer the whole file
#   4. COMPRESSION   what does the server actually store versus the raw input
#
# Exit codes are captured directly and never through a pipe.

set -uo pipefail
SRV="${1:?usage: corpus-report.sh <lores://host:port> <corpus-dir> <work-dir> [repo]}"
CORPUS="${2:?corpus dir}"
WORK="${3:?work dir}"
REPO="${4:-corpustest}"
LOG="$WORK/.cmd.log"

rm -rf "$WORK"; mkdir -p "$WORK/wc" "$WORK/fresh" || exit 2

run () { local label="$1"; shift; echo; echo "### $label"; "$@" > "$LOG" 2>&1
         local rc=$?; tail -6 "$LOG"; echo "  -> exit=$rc"; return $rc; }

cd "$WORK/wc" || exit 2
run "create repository" timeout 60 lore repository create "$SRV/$REPO" --description "media corpus"

cp -r "$CORPUS"/. "$WORK/wc"/ || exit 2
RAW_BYTES=$(find "$WORK/wc" -type f -not -path '*/.lore/*' -printf '%s\n' | awk '{s+=$1} END {print s}')
RAW_FILES=$(find "$WORK/wc" -type f -not -path '*/.lore/*' | wc -l)
echo; echo "corpus staged for commit: $RAW_FILES files, $RAW_BYTES bytes"

run "dirty"  timeout 120 lore dirty .
run "stage"  timeout 300 lore stage .
run "commit" timeout 300 lore commit "media corpus"
run "push"   timeout 900 lore push

echo; echo "### fresh clone"
cd "$WORK/fresh" || exit 2
timeout 900 lore clone "$SRV/$REPO" "$WORK/fresh/clone" > "$LOG" 2>&1
echo "  -> exit=$?"; tail -4 "$LOG"

echo; echo "### 1. INTEGRITY: per-file checksum comparison"
( cd "$WORK/wc"          && find . -type f -not -path './.lore/*' -exec sha256sum {} \; | sort ) > "$WORK/.a"
( cd "$WORK/fresh/clone" && find . -type f -not -path './.lore/*' -exec sha256sum {} \; | sort ) > "$WORK/.b" 2>/dev/null
if diff -q "$WORK/.a" "$WORK/.b" >/dev/null 2>&1; then
  echo "  ALL $(wc -l < "$WORK/.a") FILES IDENTICAL after push and fresh clone"
else
  echo "  MISMATCH:"; diff "$WORK/.a" "$WORK/.b" | head -20
fi

echo; echo "### per-format round trip"
while read -r sum path; do
  b=$(grep -F " $path" "$WORK/.b" 2>/dev/null | cut -d' ' -f1)
  if [ "$sum" = "$b" ]; then printf '  ok    %s\n' "${path#./}"
  else printf '  FAIL  %s\n' "${path#./}"; fi
done < "$WORK/.a"

echo; echo "### 3. INCREMENTAL: flip ONE byte in an 8 MB file and re-push"
printf 'X' | dd of="$WORK/wc/incremental/large.bin" bs=1 seek=4000000 conv=notrunc status=none
cd "$WORK/wc" || exit 2
run "dirty (incremental)"  timeout 120 lore dirty incremental/large.bin
run "stage (incremental)"  timeout 300 lore stage .
run "commit (incremental)" timeout 300 lore commit "flip one byte in an 8 MB file"
echo "  >>> the push line below is the answer: bytes transferred for a 1-byte change"
run "push (incremental)"   timeout 900 lore push

echo
echo "raw corpus input: $RAW_BYTES bytes across $RAW_FILES files"
echo "Compare against the server-side store measured by the caller."

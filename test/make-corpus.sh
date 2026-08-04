#!/bin/bash
# Generate a media test corpus for exercising a Lore server.
#
# The corpus is GENERATED, not committed: it is several megabytes of binary that would
# bloat the package repository and date badly. This script is the artefact; run it to
# recreate the corpus byte-for-byte on any machine with the same ffmpeg build.
#
# Usage:  test/make-corpus.sh [output-dir]        (default: ./corpus, gitignored)
#
# Coverage is deliberately in two halves.
#
# 1. FORMAT COVERAGE, including formats that are current, production-standard, and
#    forthcoming. A version-control system for binary assets should be indifferent to
#    container and codec, but "should" is a claim.
#
# 2. CAPABILITY COVERAGE, which is the half that actually tests Lore rather than ffmpeg.
#    Lore is content-addressed with BLAKE3 and compresses with Zstandard, so the
#    interesting questions are about deduplication, incremental change, and how it copes
#    with data that cannot be compressed further. Those are set up here and asserted by
#    test/corpus-report.sh after a push.
#
# Everything is deliberately small. The point is coverage, not load.

set -uo pipefail
OUT="${1:-$(dirname "$0")/../corpus}"
mkdir -p "$OUT"/{image,video,audio,raw,dedup,incremental} || exit 2

have () { command -v "$1" >/dev/null 2>&1; }
note () { printf '  %-34s %s\n' "$1" "$2"; }
gen  () { # gen <label> <outfile> <command...>
  local label="$1" out="$2"; shift 2
  if "$@" >/dev/null 2>&1 && [ -s "$out" ]; then
    note "$label" "$(stat -c%s "$out") bytes"
  else
    note "$label" "SKIPPED (encoder unavailable or failed)"
    rm -f "$out"
  fi
}

if ! have ffmpeg; then echo "ffmpeg is required" >&2; exit 2; fi

# A deterministic source: the same synthetic pattern every run, so the corpus is
# reproducible and a checksum comparison across machines is meaningful.
SRC_V="-f lavfi -i testsrc2=size=320x240:rate=24:duration=2"
SRC_A="-f lavfi -i sine=frequency=440:duration=5:sample_rate=48000"
SRC_I="-f lavfi -i testsrc2=size=512x512:duration=1 -frames:v 1"

echo "== images =="
gen "PNG 8-bit"          "$OUT/image/still.png"      ffmpeg -y $SRC_I "$OUT/image/still.png"
gen "PNG 16-bit"         "$OUT/image/still16.png"    ffmpeg -y $SRC_I -pix_fmt rgb48be "$OUT/image/still16.png"
gen "JPEG (lossy)"       "$OUT/image/still.jpg"      ffmpeg -y $SRC_I -q:v 3 "$OUT/image/still.jpg"
gen "WebP"               "$OUT/image/still.webp"     ffmpeg -y $SRC_I -c:v libwebp "$OUT/image/still.webp"
gen "AVIF (AV1 image)"   "$OUT/image/still.avif"     ffmpeg -y $SRC_I -c:v libaom-av1 -still-picture 1 "$OUT/image/still.avif"
gen "JPEG XL (emerging)" "$OUT/image/still.jxl"      ffmpeg -y $SRC_I -c:v libjxl "$OUT/image/still.jxl"
gen "TIFF (print/VFX)"   "$OUT/image/still.tiff"     ffmpeg -y $SRC_I "$OUT/image/still.tiff"
gen "EXR (HDR/VFX)"      "$OUT/image/still.exr"      ffmpeg -y $SRC_I -pix_fmt gbrpf32le "$OUT/image/still.exr"
gen "TGA (game texture)" "$OUT/image/still.tga"      ffmpeg -y $SRC_I "$OUT/image/still.tga"
gen "DDS (GPU texture)"  "$OUT/image/still.dds"      ffmpeg -y $SRC_I -pix_fmt rgba "$OUT/image/still.dds"

echo "== video =="
gen "AV1 in MP4"         "$OUT/video/clip.av1.mp4"   ffmpeg -y $SRC_V -c:v libsvtav1 -preset 8 -crf 40 "$OUT/video/clip.av1.mp4"
gen "AV1 in WebM"        "$OUT/video/clip.av1.webm"  ffmpeg -y $SRC_V -c:v libsvtav1 -preset 8 -crf 40 "$OUT/video/clip.av1.webm"
gen "VVC/H.266 (emerging)" "$OUT/video/clip.vvc.mp4" ffmpeg -y $SRC_V -c:v libvvenc -preset faster "$OUT/video/clip.vvc.mp4"
gen "H.264 (baseline)"   "$OUT/video/clip.h264.mp4"  ffmpeg -y $SRC_V -c:v libx264 -preset veryfast -crf 30 "$OUT/video/clip.h264.mp4"
gen "ProRes (mastering)" "$OUT/video/clip.prores.mov" ffmpeg -y $SRC_V -c:v prores_ks -profile:v 0 "$OUT/video/clip.prores.mov"

echo "== audio =="
gen "Opus in Ogg"        "$OUT/audio/tone.opus"      ffmpeg -y $SRC_A -c:a libopus -b:a 96k "$OUT/audio/tone.opus"
gen "FLAC (lossless)"    "$OUT/audio/tone.flac"      ffmpeg -y $SRC_A -c:a flac "$OUT/audio/tone.flac"
gen "WAV (uncompressed)" "$OUT/audio/tone.wav"       ffmpeg -y $SRC_A -c:a pcm_s16le "$OUT/audio/tone.wav"

echo "== raw: the compressibility spread =="
# Zstandard is Lore's compressor. These three sit at the extremes and the middle.
head -c 4000000 /dev/zero > "$OUT/raw/zeros.bin"
note "highly compressible (zeros)" "$(stat -c%s "$OUT/raw/zeros.bin") bytes"
head -c 4000000 /dev/urandom > "$OUT/raw/random.bin"
note "incompressible (random)" "$(stat -c%s "$OUT/raw/random.bin") bytes"
head -c 4000000 /dev/zero | tr '\0' 'A' > "$OUT/raw/repetitive.txt"
note "repetitive text" "$(stat -c%s "$OUT/raw/repetitive.txt") bytes"

echo "== dedup: identical content under two names =="
# Content-addressed storage should keep ONE fragment for these two files.
cp "$OUT/raw/random.bin" "$OUT/dedup/copy-a.bin"
cp "$OUT/raw/random.bin" "$OUT/dedup/copy-b.bin"
note "copy-a.bin / copy-b.bin" "identical, $(sha256sum "$OUT/dedup/copy-a.bin" | cut -c1-16)..."

echo "== incremental: a large file that will be minimally modified =="
# Committed once as-is; test/corpus-report.sh flips a single byte and re-pushes to see
# whether Lore transfers the whole file again or only the changed region. This is the
# question that matters most for a VCS aimed at large binary assets.
head -c 8000000 /dev/urandom > "$OUT/incremental/large.bin"
note "large.bin" "$(stat -c%s "$OUT/incremental/large.bin") bytes"

echo
echo "corpus written to $OUT"
echo "total: $(du -sh "$OUT" | cut -f1), $(find "$OUT" -type f | wc -l) files"

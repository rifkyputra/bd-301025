#!/usr/bin/env bash
set -euo pipefail

# compress-assets.sh
# Finds common media types in the `assets/` folder and re-encodes them with ffmpeg
# - JPEG/JPG: re-encoded with constrained width (max 1280) and quality.
# - PNG: re-encoded with constrained width (max 1280) and moderate compression level.
# - MP4/MOV/WebM: re-encoded with H.264 (libx264) using CRF-based quality.
#
# This script writes to a temporary file first and then atomically replaces the
# original to avoid leaving broken files on failure. It requires `ffmpeg` to be
# installed and available on PATH.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS_DIR="$ROOT_DIR/assets"

if [ ! -d "$ASSETS_DIR" ]; then
  echo "No assets directory found at: $ASSETS_DIR"
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg is required but not found in PATH. Install ffmpeg and retry."
  exit 2
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Compressing media in: $ASSETS_DIR"

# Helper: process a file using ffmpeg and replace on success
_reencode() {
  local src="$1"; shift
  local out="$TMP_DIR/$(basename "$src")"
  echo " -> $src"
  if ffmpeg -hide_banner -loglevel error -y -i "$src" "$@" "$out"; then
    mv -f "$out" "$src"
  else
    echo "    [warn] ffmpeg failed for $src"
    [ -f "$out" ] && rm -f "$out"
  fi
}

export -f _reencode

# Images: JPG/JPEG
find "$ASSETS_DIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' \) -print0 |
  while IFS= read -r -d '' f; do
    # scale down if wider than 1280, keep aspect ratio; re-encode with quality
    _reencode "$f" -vf "scale='if(gt(iw,1280),1280,iw)':-2" -q:v 3
  done

# PNGs: use png encoder with compression_level and optional scaling
find "$ASSETS_DIR" -type f -iname '*.png' -print0 |
  while IFS= read -r -d '' f; do
    _reencode "$f" -vf "scale='if(gt(iw,1280),1280,iw)':-2" -compression_level 3
  done

# Videos: MP4 / MOV / WEBM
find "$ASSETS_DIR" -type f \( -iname '*.mp4' -o -iname '*.mov' -o -iname '*.webm' \) -print0 |
  while IFS= read -r -d '' f; do
    # re-encode to H.264 (libx264) with reasonable quality (CRF). Keep audio at 96kbps.
    _reencode "$f" -c:v libx264 -preset slow -crf 28 -c:a aac -b:a 96k -movflags +faststart
  done

echo "Done. Temporary files cleaned up."

echo "Tip: run 'npm run compress:assets' to invoke this script from the project root."

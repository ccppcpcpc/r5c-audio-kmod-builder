#!/bin/sh
set -eu

archive="${1:-/tmp/r5c-audio-kmods-6.1.84-close-match.tar.gz}"
test_root=/tmp/r5c-audio-test

if [ ! -f "$archive" ]; then
  echo "ERROR: archive not found: $archive" >&2
  exit 1
fi

rm -rf "$test_root"
mkdir -p "$test_root"
tar -xzf "$archive" -C "$test_root"

runner="$(find "$test_root" -type f -name test-r5c-audio.sh -print | head -n 1)"
if [ -z "$runner" ]; then
  echo 'ERROR: test-r5c-audio.sh is missing from the archive' >&2
  exit 1
fi

chmod +x "$runner"
exec "$runner" usb

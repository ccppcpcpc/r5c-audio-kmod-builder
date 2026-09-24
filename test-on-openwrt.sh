#!/bin/sh
set -eu

archive="${1:-/tmp/audio-kmods-6.1.84-aarch64.tar.gz}"
test_root=/tmp/r5c-audio-test
expected='6.1.84 SMP preempt mod_unload aarch64'

if [ "$(uname -r)" != '6.1.84' ] || [ "$(uname -m)" != 'aarch64' ]; then
  echo "ERROR: expected Linux 6.1.84/aarch64, got $(uname -r)/$(uname -m)" >&2
  exit 1
fi

rm -rf "$test_root"
mkdir -p "$test_root"
tar -xzf "$archive" -C "$test_root"

find_module() {
  find "$test_root" -type f -name "$1.ko" -print -quit
}

check_module() {
  module="$1"
  actual="$(modinfo "$module" 2>/dev/null | sed -n 's/^vermagic:[[:space:]]*//p')"
  if [ "$actual" != "$expected" ]; then
    echo "ERROR: vermagic mismatch: $module" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    exit 1
  fi
}

load_one() {
  name="$1"
  module="$(find_module "$name")"
  if [ -z "$module" ]; then
    echo "ERROR: missing $name.ko" >&2
    exit 1
  fi
  check_module "$module"
  if grep -q "^${name//-/_} " /proc/modules 2>/dev/null; then
    echo "already loaded: $name"
    return 0
  fi
  echo "loading: $name"
  if ! insmod "$module"; then
    echo "ERROR: failed to load $name" >&2
    dmesg | tail -n 80 >&2
    exit 1
  fi
}

# The installed kmod-input-core already belongs to the running firmware.
for name in \
  soundcore \
  snd \
  snd-hwdep \
  snd-seq-device \
  snd-rawmidi \
  snd-timer \
  snd-pcm \
  mc \
  snd-usbmidi-lib \
  snd-usb-audio
do
  load_one "$name"
done

sleep 2
echo
cat /proc/asound/cards 2>/dev/null || true
aplay -l 2>/dev/null || true

if [ -e /proc/asound/cards ] && ! grep -q 'no soundcards' /proc/asound/cards; then
  echo 'READY: USB audio device detected'
else
  echo 'Modules loaded, but ALSA has not registered a sound card.' >&2
  dmesg | tail -n 80 >&2
  exit 2
fi

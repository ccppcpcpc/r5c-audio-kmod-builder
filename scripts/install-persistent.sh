#!/bin/sh
set -eu

BUNDLE_DIR="${1:-$(CDPATH= cd "$(dirname "$0")" && pwd)}"
MODULE_DIR="$BUNDLE_DIR/modules"
DEST=/opt/r5c-audio

if [ "$(id -u)" != 0 ]; then
  echo 'ERROR: run this script as root' >&2
  exit 1
fi

if [ "$(uname -r)" != '6.1.84' ]; then
  echo "ERROR: expected Linux 6.1.84, found $(uname -r)" >&2
  exit 1
fi

if [ ! -d "$MODULE_DIR" ]; then
  echo "ERROR: module directory not found: $MODULE_DIR" >&2
  exit 1
fi

if [ -f "$BUNDLE_DIR/test-r5c-audio.sh" ]; then
  sh "$BUNDLE_DIR/test-r5c-audio.sh" check
fi

mkdir -p "$DEST/modules"
cp "$MODULE_DIR"/*.ko "$DEST/modules/"
chmod 644 "$DEST/modules"/*.ko

cat > /etc/init.d/r5c-usb-audio <<'EOF'
#!/bin/sh /etc/rc.common
START=18
STOP=89

MODULE_DIR="/opt/r5c-audio/modules"

load_one() {
  module="$1"
  file="$2"
  [ -d "/sys/module/$module" ] && return 0
  insmod "$MODULE_DIR/$file"
}

start() {
  if [ "$(uname -r)" != "6.1.84" ]; then
    logger -t r5c-usb-audio "kernel mismatch: $(uname -r), refusing to load"
    return 1
  fi
  load_one soundcore soundcore.ko || return 1
  load_one snd snd.ko || return 1
  load_one snd_timer snd-timer.ko || return 1
  load_one snd_pcm snd-pcm.ko || return 1
  load_one snd_hwdep snd-hwdep.ko || return 1
  load_one snd_seq_device snd-seq-device.ko || return 1
  load_one snd_rawmidi snd-rawmidi.ko || return 1
  load_one mc mc.ko || return 1
  load_one snd_usbmidi_lib snd-usbmidi-lib.ko || return 1
  load_one snd_usb_audio snd-usb-audio.ko || return 1
  logger -t r5c-usb-audio "USB audio modules loaded"
}

stop() {
  return 0
}
EOF

chmod 755 /etc/init.d/r5c-usb-audio
/etc/init.d/r5c-usb-audio enable
/etc/init.d/r5c-usb-audio start

echo 'Persistent USB audio module loading is enabled.'
echo 'Verify with: aplay -l'

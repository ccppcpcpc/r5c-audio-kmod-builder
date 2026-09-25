#!/bin/sh
set -eu

PACKAGES_BASE="${OPENWRT_PACKAGES_BASE:-https://downloads.openwrt.org/releases/packages-24.10/aarch64_generic/packages}"
BASE_BASE="${OPENWRT_BASE_BASE:-https://downloads.openwrt.org/releases/packages-24.10/aarch64_generic/base}"
ROOT=/opt/shairport-ap2
WORK="/tmp/r5c-airplay2-install.$$"
PACKAGES_INDEX="$WORK/Packages.packages"
BASE_INDEX="$WORK/Packages.base"
AIRPLAY_NAME="${AIRPLAY_NAME:-R5C Xiaomi Speaker}"

cleanup() {
  rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

if [ "$(id -u)" != 0 ]; then
  echo 'ERROR: run this script as root' >&2
  exit 1
fi

if [ "$(uname -m)" != 'aarch64' ]; then
  echo "ERROR: expected aarch64, found $(uname -m)" >&2
  exit 1
fi

case "$AIRPLAY_NAME" in
  *\"*|*\\*)
    echo 'ERROR: AIRPLAY_NAME must not contain a quote or backslash' >&2
    exit 1
    ;;
esac

if ! grep -q 'Pro9835' /proc/asound/cards 2>/dev/null; then
  echo 'ERROR: Pro9835 is not present in /proc/asound/cards' >&2
  exit 1
fi

mkdir -p "$WORK/pkgs" "$ROOT"
wget -q "$PACKAGES_BASE/Packages.gz" -O "$WORK/Packages.packages.gz"
wget -q "$BASE_BASE/Packages.gz" -O "$WORK/Packages.base.gz"
gzip -dc "$WORK/Packages.packages.gz" > "$PACKAGES_INDEX"
gzip -dc "$WORK/Packages.base.gz" > "$BASE_INDEX"

extract_package() {
  package="$1"
  index="$PACKAGES_INDEX"
  source_base="$PACKAGES_BASE"
  filename="$(sed -n "/^Package: $package\$/,/^\$/s/^Filename: //p" "$index" | head -n 1)"
  if [ -z "$filename" ]; then
    index="$BASE_INDEX"
    source_base="$BASE_BASE"
    filename="$(sed -n "/^Package: $package\$/,/^\$/s/^Filename: //p" "$index" | head -n 1)"
  fi
  expected="$(sed -n "/^Package: $package\$/,/^\$/s/^SHA256sum: //p" "$index" | head -n 1)"
  if [ -z "$filename" ] || [ -z "$expected" ]; then
    echo "ERROR: package not found in index: $package" >&2
    exit 1
  fi
  ipk="$WORK/pkgs/$filename"
  echo "Downloading $package ($filename)"
  wget -q "$source_base/$filename" -O "$ipk"
  actual="$(sha256sum "$ipk" | awk '{print $1}')"
  if [ "$actual" != "$expected" ]; then
    echo "ERROR: SHA-256 mismatch for $filename" >&2
    exit 1
  fi
  tar -xOzf "$ipk" ./data.tar.gz | tar -xzf - -C "$ROOT"
}

for package in \
  libconfig11 \
  libxml2-16 \
  libplist \
  libsodium \
  libsoxr \
  libcares \
  libmosquitto-nossl \
  fdk-aac \
  lame-lib \
  libopus \
  libffmpeg-full \
  nqptp \
  shairport-sync-openssl
do
  extract_package "$package"
done

mkdir -p "$ROOT/bin" "$ROOT/etc"

cat > "$ROOT/etc/shairport-sync.conf" <<EOF
general = {
  name = "$AIRPLAY_NAME";
  service_type = "airplay2";
  output_backend = "alsa";
  mdns_backend = "avahi";
  interpolation = "soxr";
};
alsa = {
  output_device = "plughw:Pro9835,0";
  mixer_control_name = "Playback Volume";
  mixer_device = "hw:Pro9835";
  output_format = "S16_LE";
  output_channels = 2;
};
diagnostics = {
  log_output_to = "stderr";
  log_verbosity = 1;
};
EOF

cat > "$ROOT/bin/nqptp-run" <<'EOF'
#!/bin/sh
export LD_LIBRARY_PATH=/opt/shairport-ap2/usr/lib
exec /opt/shairport-ap2/usr/bin/nqptp
EOF

cat > "$ROOT/bin/shairport-sync-run" <<'EOF'
#!/bin/sh
export LD_LIBRARY_PATH=/opt/shairport-ap2/usr/lib
i=0
while [ "$i" -lt 30 ]; do
  grep -q 'Pro9835' /proc/asound/cards 2>/dev/null && break
  sleep 1
  i=$((i + 1))
done
exec /opt/shairport-ap2/usr/bin/shairport-sync -c /opt/shairport-ap2/etc/shairport-sync.conf
EOF

chmod 755 "$ROOT/bin/nqptp-run" "$ROOT/bin/shairport-sync-run"

missing="$(LD_LIBRARY_PATH="$ROOT/usr/lib" ldd "$ROOT/usr/bin/shairport-sync" 2>&1 | grep 'not found' || true)"
if [ -n "$missing" ]; then
  echo 'ERROR: unresolved Shairport Sync libraries:' >&2
  echo "$missing" >&2
  exit 1
fi

LD_LIBRARY_PATH="$ROOT/usr/lib" "$ROOT/usr/bin/shairport-sync" -V
LD_LIBRARY_PATH="$ROOT/usr/lib" "$ROOT/usr/bin/nqptp" -V

cat > /etc/init.d/nqptp-ap2 <<'EOF'
#!/bin/sh /etc/rc.common
START=97
STOP=03
USE_PROCD=1

start_service() {
  procd_open_instance
  procd_set_param command /opt/shairport-ap2/bin/nqptp-run
  procd_set_param respawn
  procd_set_param stdout 1
  procd_set_param stderr 1
  procd_close_instance
}
EOF

cat > /etc/init.d/shairport-ap2 <<'EOF'
#!/bin/sh /etc/rc.common
START=98
STOP=02
USE_PROCD=1

start_service() {
  procd_open_instance
  procd_set_param command /opt/shairport-ap2/bin/shairport-sync-run
  procd_set_param respawn
  procd_set_param stdout 1
  procd_set_param stderr 1
  procd_close_instance
}
EOF

chmod 755 /etc/init.d/nqptp-ap2 /etc/init.d/shairport-ap2

/etc/init.d/shairport-ap2 stop 2>/dev/null || true
/etc/init.d/nqptp-ap2 stop 2>/dev/null || true
/etc/init.d/nqptp-ap2 enable
/etc/init.d/shairport-ap2 enable
/etc/init.d/nqptp-ap2 start
/etc/init.d/shairport-ap2 start

sleep 3
if ! ps w | grep -q '[s]hairport-sync'; then
  echo 'ERROR: Shairport Sync did not stay running' >&2
  logread | grep -E 'shairport|nqptp' | tail -n 100 >&2
  exit 1
fi

echo "AirPlay 2 is ready as: $AIRPLAY_NAME"
echo "Configuration: $ROOT/etc/shairport-sync.conf"

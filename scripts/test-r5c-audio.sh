#!/bin/sh
set -eu

EXPECTED_RELEASE='6.1.84'
EXPECTED_VERMAGIC='6.1.84 SMP preempt mod_unload aarch64'
SELF_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
MOD_DIR="$SELF_DIR/modules"

module_loaded() {
    module_name=$(echo "$1" | tr '-' '_')
    grep -q "^${module_name} " /proc/modules
}

check_one() {
    file="$MOD_DIR/$1.ko"
    if [ ! -f "$file" ]; then
        echo "ERROR: missing $file" >&2
        exit 1
    fi
    actual=$(modinfo "$file" 2>/dev/null | sed -n 's/^vermagic:[[:space:]]*//p' | head -n 1)
    if [ -z "$actual" ] && command -v strings >/dev/null 2>&1; then
        actual=$(strings "$file" | sed -n 's/^vermagic=//p' | head -n 1)
    fi
    if [ "$actual" != "$EXPECTED_VERMAGIC" ]; then
        echo "ERROR: vermagic mismatch for $1.ko" >&2
        echo " expected: $EXPECTED_VERMAGIC" >&2
        echo " actual:   $actual" >&2
        exit 1
    fi
}

check_all() {
    if [ "$(uname -r)" != "$EXPECTED_RELEASE" ]; then
        echo "ERROR: expected kernel $EXPECTED_RELEASE, found $(uname -r)" >&2
        exit 1
    fi
    if [ "$(cat /proc/sys/kernel/tainted)" != "0" ]; then
        echo "ERROR: kernel is already tainted; reboot before testing" >&2
        exit 1
    fi
    for name in soundcore snd snd-timer snd-pcm snd-hwdep snd-seq-device snd-rawmidi mc snd-usbmidi-lib snd-usb-audio; do
        check_one "$name"
    done
    if command -v sha256sum >/dev/null 2>&1; then
        (cd "$SELF_DIR" && sha256sum -c SHA256SUMS)
    fi
    echo "CHECK_OK: kernel, taint state, files, hashes and vermagic"
}

load_one() {
    name="$1"
    if module_loaded "$name"; then
        echo "SKIP: $name already loaded"
        return
    fi
    echo "LOAD: $name"
    insmod "$MOD_DIR/$name.ko"
    if ! module_loaded "$name"; then
        echo "ERROR: $name did not appear in /proc/modules" >&2
        exit 1
    fi
    echo "OK: $name"
}

load_core() {
    load_one soundcore
    load_one snd
    load_one snd-timer
}

load_support() {
    load_core
    load_one snd-pcm
    load_one snd-hwdep
    load_one snd-seq-device
    load_one snd-rawmidi
    load_one mc
    load_one snd-usbmidi-lib
}

show_status() {
    echo '--- loaded audio modules ---'
    grep -E '^(snd|soundcore|mc) ' /proc/modules || true
    echo '--- USB tree ---'
    lsusb -t || true
    echo '--- ALSA cards ---'
    aplay -l || true
    echo '--- recent kernel messages ---'
    dmesg | tail -n 100
}

unload_all() {
    for name in snd-usb-audio snd-usbmidi-lib mc snd-rawmidi snd-seq-device snd-hwdep snd-pcm snd-timer snd soundcore; do
        if module_loaded "$name"; then
            module_name=$(echo "$name" | tr '-' '_')
            echo "UNLOAD: $module_name"
            rmmod "$module_name" || true
        fi
    done
    show_status
}

case "${1:-check}" in
    check)
        check_all
        ;;
    core)
        check_all
        load_core
        show_status
        ;;
    support)
        check_all
        load_support
        show_status
        ;;
    usb)
        check_all
        load_support
        load_one snd-usb-audio
        show_status
        ;;
    status)
        show_status
        ;;
    unload)
        unload_all
        ;;
    *)
        echo "Usage: $0 {check|core|support|usb|status|unload}" >&2
        exit 2
        ;;
esac

#!/bin/sh

echo '--- system ---'
uname -a
uptime

echo '--- audio modules ---'
lsmod | grep -E '^(snd|soundcore|mc)' || true

echo '--- ALSA cards ---'
aplay -l 2>/dev/null || true

echo '--- AirPlay services ---'
ps w | grep -E '[n]qptp|[s]hairport-sync' || true
netstat -lntup 2>/dev/null | grep -E ':(319|320|7000) ' || true

echo '--- kernel taint ---'
cat /proc/sys/kernel/tainted

echo '--- recent logs ---'
logread | grep -E 'r5c-usb-audio|shairport|nqptp' | tail -n 100

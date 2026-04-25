#!/usr/bin/env bash
# One-time post-install: sendkey `#include "B:/Setup.ZC";` so Setup.ZC
# writes ~/MakeHome.ZC on the installed disk. From then on, every boot
# auto-runs B:/Boot.ZC.
#
# Pre-req: make dev is running and is at the home> prompt.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"

if [ ! -S "$REPO/build/qemu.sock" ]; then
  echo "error: VM not running. Start 'make dev' first." >&2
  exit 1
fi

echo "==> sending Setup.ZC include"
"$REPO/scripts/send.py" '#include "B:/Setup.ZC";' --enter --delay 0.05

# Give the FileWrite a beat, then snap so we can verify SETUP_OK.
sleep 3
"$REPO/scripts/screenshot.sh" >/dev/null
echo "==> screenshot at build/screen.png"
echo "==> tail of serial.log:"
tail -5 "$REPO/build/serial.log" || true

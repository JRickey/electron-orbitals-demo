#!/usr/bin/env bash
# zpush — send a HolyC source file (or stdin) to the running ZealOS REPL via
# COM1 (Unix socket). Appends EOT (0x04) to mark end-of-command, then waits
# briefly so the daemon has time to print response back via CommPrint.
#
#   scripts/zpush.sh tests/T_Hello.ZC
#   echo '"hi\n";' | scripts/zpush.sh
#
# All daemon output (DAEMON_RECV, prints, DAEMON_DONE) lands in
# build/serial.log via QEMU's chardev logfile=.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SOCK="$REPO/build/com1.sock"

[ -S "$SOCK" ] || { echo "error: $SOCK not found — is the dev VM running?" >&2; exit 1; }

if [ $# -gt 0 ]; then
  { cat "$1"; printf '\x04'; } | nc -w 2 -U "$SOCK"
else
  { cat; printf '\x04'; } | nc -w 2 -U "$SOCK"
fi

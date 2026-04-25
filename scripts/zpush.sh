#!/usr/bin/env bash
# zpush — send a HolyC source file (or stdin) to the running ZealOS REPL
# daemon via COM2 (Unix socket). Appends EOT (0x04) to mark end-of-command;
# the daemon writes the bytes to C:/Tmp/Cmd.HC and ExeFile()s it.
#
#   scripts/zpush.sh tests/T_Hello.ZC
#   echo 'Print("hi\n");' | scripts/zpush.sh
#
# Daemon output (DAEMON_RECV, prints, DAEMON_DONE) lands in serial.log via
# COM1's file backend.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SOCK="$REPO/build/com2.sock"

[ -S "$SOCK" ] || { echo "error: $SOCK not found — is 'make dev' running?" >&2; exit 1; }

if [ $# -gt 0 ]; then
  { cat "$1"; printf '\x04'; } | nc -w 2 -U "$SOCK"
else
  { cat; printf '\x04'; } | nc -w 2 -U "$SOCK"
fi

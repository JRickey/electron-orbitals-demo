#!/usr/bin/env bash
# Run the autonomous test loop.
#
# 1. Build shuttle (already done by `make test`'s dependency).
# 2. Boot the installed disk + shuttle (`make dev` mode).
# 3. Send `1\n` to the ZealOS Boot Loader to pick Drive C.
# 4. ZealOS boots; ~/MakeHome.ZC auto-mounts the shuttle (E:) and
#    `#include`s E:/Boot.ZC, which runs the test suite.
# 5. Boot.ZC prints PASS/FAIL/SUMMARY/TEST_RUN_END to COM1 → serial.log.
# 6. The watcher sees TEST_RUN_END and quits qemu via the monitor socket.
# 7. Hard timeout if neither happens.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$REPO/build/serial.log"
SOCK="$REPO/build/qemu.sock"
TIMEOUT="${TEST_TIMEOUT:-180}"

: > "$LOG"
rm -f "$SOCK"

# Boot dev mode (CD + disk + shuttle) in background.
bash "$REPO/scripts/boot.sh" dev &
QEMU_PID=$!

# Wait for monitor socket.
i=0
while [ ! -S "$SOCK" ] && [ $i -lt 10 ]; do sleep 1; i=$((i+1)); done
[ -S "$SOCK" ] || { echo "error: monitor socket never appeared"; kill $QEMU_PID 2>/dev/null; exit 1; }

# Wait for the ZealOS Boot Loader menu (~10-15s on TCG), then send `1`.
echo "==> waiting 12s for boot loader menu"
sleep 12
echo "==> sending '1' to pick Drive C"
"$REPO/scripts/send.py" '1' --enter --delay 0.1 >/dev/null

# Watcher: when TEST_RUN_END appears, quit qemu via monitor.
(
  i=0
  while [ $i -lt "$TIMEOUT" ]; do
    if grep -q "^TEST_RUN_END" "$LOG" 2>/dev/null; then
      sleep 1
      echo "==> TEST_RUN_END seen, quitting qemu"
      echo "quit" | nc -U "$SOCK" >/dev/null 2>&1 || true
      exit 0
    fi
    sleep 1
    i=$((i + 1))
  done
  echo "==> watchdog timeout (${TIMEOUT}s), killing qemu"
  echo "quit" | nc -U "$SOCK" >/dev/null 2>&1 || true
  sleep 2
  kill -9 "$QEMU_PID" 2>/dev/null || true
) &
WATCHER_PID=$!

wait "$QEMU_PID" 2>/dev/null || true
kill "$WATCHER_PID" 2>/dev/null || true
exit 0

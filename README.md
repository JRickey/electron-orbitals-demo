# templeos

A HolyC development environment. We write `.ZC` files on the host with a
real editor, and run them inside [ZealOS](https://github.com/Zeal-Operating-System/ZealOS)
(a maintained 64-bit fork of TempleOS) running in QEMU. The whole loop is
closed and scriptable: `make test` builds, boots, runs, and reports
pass/fail.

ZealOS is the dev VM. Pure TempleOS is reserved for the canonical altar.

## The dev loop

```
   host                                  guest (ZealOS in QEMU)
   ────                                  ──────────────────────
   src/*.ZC, tests/*.ZC  ──┐
                           │  hdiutil    ┌─────────────────────┐
                           └─► shuttle.img ──► drive B:        │
                                         │   ~/MakeHome.ZC     │
                                         │     #include B:/Boot.ZC
                                         │   Boot.ZC:          │
                                         │     CommInit8n1     │
                                         │     #include tests  │
                                         │     TEST_SUMMARY    │
   build/serial.log  ◄───── -serial file ◄  CommPrint PASS/FAIL│
                                         │   OutU16 0x604 → ACPI off
                                         └─────────────────────┘
   make test ─► grep TEST_FAIL ─► exit 0/1
```

Five pieces:

1. **Shuttle disk.** A FAT32 image built from `src/` and `tests/`, attached
   to QEMU as a second drive. ZealOS sees it as `B:`. `scripts/build-shuttle.sh`
   also generates `Boot.ZC` automatically by enumerating `tests/T_*.ZC`.
2. **Auto-run via MakeHome.** ZealOS's `~/MakeHome.ZC` runs on every boot.
   We wire it once (via `make wire-makehome`) to `#include "B:/Boot.ZC";`.
3. **Test framework.** `tests/Assert.ZC` defines `PASS`, `FAIL`,
   `ASSERT_EQ`, `TEST_SUMMARY` — each writes to both the screen (`Print`)
   and COM1 (`CommPrint`).
4. **Serial out.** QEMU pipes COM1 to `build/serial.log`. Every
   `CommPrint` lands in a host file we can grep.
5. **ACPI shutdown.** `Boot.ZC` ends with `OutU16(0x604, 0x2000)`, which
   QEMU intercepts as ACPI sleep state 5 — the VM exits cleanly and `make
   test` returns control to the host.

## Layout

```
vendor/zealos/    ZealOS BIOS ISO + installed disk.qcow2  (gitignored)
src/              persistent HolyC: Setup.ZC, future tools  (committed)
tests/            test framework + battery (T_*.ZC files)   (committed)
scripts/          bash + python utilities                   (committed)
build/            shuttle.img, serial.log, screen.png       (gitignored)
Makefile          all the targets below
```

## Prerequisites

- macOS, Apple Silicon or Intel
- `qemu-system-x86_64` — `brew install qemu`
- Standard macOS tools: `hdiutil`, `dd`, `make`, `python3`, `nc`, `sips`
- ~5GB free disk

## Setup (one-time)

```sh
make setup           # fetch the ZealOS BIOS ISO (~44MB)
make disk            # create a fresh 4G qcow2 install disk
make install         # boot CD + disk for the install (~15min on TCG)
                     # walks itself through y → I → Y via sendkey
make dev             # boot the installed disk + shuttle
make wire-makehome   # one-time: writes ~/MakeHome.ZC to auto-run B:/Boot.ZC
```

After `wire-makehome`, the loop is live. Quit the dev VM (Ctrl-C the make,
or close the QEMU window) and any future `make test` is fully autonomous.

## Daily use

```sh
make test    # rebuilds shuttle from src/+tests/, boots, runs, parses log
make dev     # interactive: same boot, no auto-exit, you see the desktop
```

## Why this shape

I (Claude) write HolyC less reliably than I write Python. The loop is the
mitigation: every piece of code is anchored to a passing test. The
validation battery in `tests/T_*.ZC` is the rosetta stone — once basics
pass, I have proven patterns to copy from for everything else.

## Why ZealOS instead of pure TempleOS

ZealOS is the most actively maintained 64-bit TempleOS fork (active as of
2025-11, vs Shrine which was archived in 2024). It adds: a real TCP/IP
stack with `TCPSocketListen`, modern bootloader (Limine), `Once()`/
`SysOnce()` persistent boot scripts, and drivers for E1000/RTL8139/
VirtIONet. It renames HolyC to ZealC; same language.

## What's in here that isn't wired

- `src/Daemon.ZC` — accept loop for a serial REPL (`FifoU8Remove` off
  `comm_ports[].RX_fifo`).
- `scripts/zpush.sh` — host-side `nc -U` wrapper to push code at the
  daemon over a Unix socket.

These are scaffolding for a "live REPL" where the host pushes HolyC
source to a persistent VM instead of paying a full boot per test. Both
the TCP and the serial-socket attempts hit dead ends (TCP handshake
through QEMU user-mode + PCnet didn't complete; chardev-socket COM
backends produced no output even though the file backend works fine).
See `NOTES.md` for the full research log, HolyC boot-phase parser
quirks, and pointers for the next attempt.

## Credits

- [Terry A. Davis](https://en.wikipedia.org/wiki/Terry_A._Davis), 1969–2018
  — wrote TempleOS, HolyC, the editor, the compiler, the games, the oracle,
  alone.
- [ZealOS](https://github.com/Zeal-Operating-System/ZealOS) — modernized
  64-bit fork; what we actually run.
- [TinkerOS](https://github.com/tinkeros/TinkerOS) — sister fork, kept the
  TempleOS look. Worth knowing about.

It is good.

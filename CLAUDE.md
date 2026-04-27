# CLAUDE.md — agent guide for templeos-devkit

A HolyC development environment. You write `.ZC` files on the host
with a real editor, and run them inside ZealOS (a maintained 64-bit
fork of TempleOS) running under QEMU. The dev loop is closed and
scriptable.

If you're an agent landing here for the first time, read this whole
file before touching anything. The README is for humans; this file
covers the parts that matter for autonomous work.

## Pick the right tool

There are two control planes for the VM:

- **`make test`** — cold-boot dev loop. Builds shuttle, boots ZealOS,
  runs every `tests/T_*.ZC`, parses `build/serial.log`, exits 0/1. ~30s
  per cycle. Use this for CI-style verdicts.
- **`scripts/zctl`** — long-lived REPL VM. One synchronous CLI that
  starts/stops the VM, pushes HolyC, captures output, takes
  screenshots. Use this for everything else: iterating on code,
  debugging compile errors, watching the screen, building up state.

`zctl` is the agent-friendly path. Default to it unless you specifically
want a fresh boot per change.

## zctl workflow

Stdlib-only Python, no extra deps. From the repo root:

```sh
scripts/zctl up                # start VM, wait until daemon listens
scripts/zctl status            # state: down | up + monitor/com2/daemon health
scripts/zctl eval 'Print("hi\n");'        # send HolyC inline
scripts/zctl eval -f tests/T_X.ZC         # send a file
scripts/zctl shell             # line-by-line interactive REPL
scripts/zctl logs -n 50        # last N lines of build/serial.log
scripts/zctl logs -f           # follow
scripts/zctl screenshot        # snap to build/screen.png
scripts/zctl wire              # one-shot post-install: mount shuttle as E: + Setup.ZC
scripts/zctl down              # quit cleanly via monitor socket
```

Flags worth knowing on `up`:
- `--headless` — no QEMU window. Default is display-on so a watching
  human can see what you're doing.
- `--no-auto-boot` — by default `up` sendkeys `1<enter>` to dismiss
  ZealOS's "Selection: 0/1/2" boot menu. Disable if you've customized
  the bootloader.
- `--timeout N` — how long to wait for `DAEMON_LISTEN:COM2` before
  giving up.

### Output capture

`zctl eval` blocks until the daemon prints `DAEMON_DONE` and writes
everything that hit the serial log between submission and that marker
to stdout. **Important:** `Print(...)` writes to the screen, not to
COM1. Use `CommPrint(1, ...)` if you want output to come back to your
shell.

```sh
scripts/zctl eval 'CommPrint(1, "value=%d\n", 42);'
# stdout: DAEMON_RECV:35
#         value=42
#         DAEMON_DONE
```

### First-time setup

Fresh clone, fresh disk:

```sh
make setup           # fetch ZealOS ISO (~44 MB)
make disk            # create blank 4 GB qcow2
make install         # boot CD + disk, walk install (~15 min on TCG)
                     # close QEMU when ZealOS desktop is up
scripts/zctl up      # boots disk + shuttle, daemon won't start (no MakeHome yet)
scripts/zctl wire    # one-shot: manually mount shuttle as E: and source Setup.ZC
                     # writes ~/MakeHome.ZC inside the VM
scripts/zctl down
scripts/zctl up      # subsequent boots auto-mount E: and spawn the daemon
```

After `wire`, every boot reaches `DAEMON_LISTEN:COM2` autonomously.

## Read the ZealOS source — don't guess HolyC APIs

HolyC has no man pages, no online reference, and no IDE that knows it.
Symbol probes (`CommPrint(1, "x=%X\n", &SomeFn);`) tell you whether a
name resolves but not its signature, and the boot-phase parser will
happily report `Missing ')' at "..."` without telling you what the
declared parameters actually are. Burning iterations guessing at
calling conventions is how you waste a session.

The fix: **clone the ZealOS source on the host and grep it.** It's the
only authoritative reference for what's in scope and how to call it.

```sh
git clone --depth 1 https://github.com/Zeal-Operating-System/ZealOS.git /tmp/ZealOS
grep -rn "U0 *UserTaskCont\|^UserTaskCont\b" /tmp/ZealOS/src   # find the def
```

Useful starting points when something doesn't compile:

| Question | Where to look |
| --- | --- |
| Does symbol X exist post-boot? | `grep -rn "^[UF]0\? *X\b" /tmp/ZealOS/src` |
| What's X's signature? | Same — read the declaration |
| Where is API X declared `extern`? | `/tmp/ZealOS/src/Kernel/KExterns.ZC` |
| How does TempleOS spawn user-style tasks? | `src/Kernel/KTask.ZC` — `User`, `UserCmdLine`, `UserTaskCont` |
| What does a User task do at startup? | `/Home/HomeSys.ZC` — `UserStartUp` (the real `DocTermNew` / `LBts SHOW` / `WinToTop` / `WinZBufUpdate` dance) |
| Boot-phase parser quirks | `src/Compiler/CExcept.ZC`, `ParseStatement.ZC` |
| Comm RX FIFO | `src/Kernel/KDataTypes.ZC` (`FifoU8Remove`) |

Lesson learned the hard way: `UserTaskCont` is not a task spawner. It's
a no-arg REPL loop that runs *inside* an already-spawned task. The
actual spawner is `Spawn(&UserCmdLine, , "Terminal")` in
`KTask.ZC:478`. This kind of thing is impossible to figure out without
reading the source — guessing wastes hours.

## HolyC quirks worth knowing

These bit us on first contact and are easy to surface again. None of
them are documented in one place, so write down anything new you find.

- **`RandF64()` does not exist.** Use `Rand()` — TempleOS/ZealOS's
  built-in unit-interval F64 RNG.

- **`if (cond) continue;` triggers `ParseStatement ERROR: Undefined
  identifier at ";"`.** Refactor to inverted-condition + braced body.
  May or may not be the same for `break` — verify if you need it.

- **Float literals silently truncate past ~16 significant digits.**
  `#define MY_PI 3.14159265358979323846` evaluates to ~0.005646, not π.
  Bisected via the daemon: 16 digits OK, 20 not OK. Use HolyC's
  built-in `pi` constant when you need π.

- **Top-level `return` / `goto` and `for`/`while` with type-decls
  trip the boot-phase parser** (NOTES.md has the long-form explanation
  with a `CTCPSocket` repro). The host-side linter
  (`scripts/holyc-lint.py`) flags these. Run `make lint` before pushing
  code into the VM — it's the offline pre-flight.

- **`Print` writes to screen, not COM1.** Use `CommPrint(1, ...)` for
  output the host sees.

- **`Sys()` with a bare-identifier body deadlocks** when called from
  `sys_task` during boot. `Daemon.ZC` documents the workaround
  (`TaskExe(sys_task, Fs, "Spawn(...);", 0)`).

- **`cnts` / `cnts.jiffies` is not in scope in ZealOS.** Every ExeFile
  that touches it fails (`Invalid lval at "cnts"`) — both at boot phase
  and post-boot. Use `tS` (F64 seconds since boot) for idle/timing.
  `JIFFY_FREQ` is defined and equals 1000.

- **No scan-code-aware blocking input from a daemon-loaded ExeFile.**
  `GetKey`, `ScanMsg`, `MsgGet`, `KbdMsgsGet`, `ScanChar` all fail to
  link from code pushed via the daemon (`Invalid lval at "GetKey"`
  etc). `CharGet(echo=FALSE, can_break=TRUE)` does resolve — but it
  only returns the ASCII char, not the scan code. So no arrow keys for
  REPL-pushed UIs; map to ASCII (`,`/`.`, brackets, etc).

- **`StrPrint(buf, fmt, ...)` returns a `U8 *` (the buffer pointer),
  not the number of characters written.** Code that advances an
  offset with `off += StrPrint(...)` will silently jump by ~the buffer
  address and look like it wrote one entry then bailed. Use
  `off += StrLen(&buf[off])` after the call instead. Bit us in
  `AtomConfigStr` — the rendered config showed only the first shell.

- **`Spawn(&Fn, NULL, name)` calls `Fn(U8 *data)`, not the function's
  declared args.** Functions with `(I64 a=N, I64 b=M)` defaults will
  see stack garbage for `b` (caller frame remnants), which surfaces as
  weird OOMs from `MAlloc(sizeof(...) * count)`. Wrap with a
  `U0 FnTask(U8 *data) { data = data; Fn(...); }` shim and Spawn that
  shim instead. See `OrbitalExplorerTask` in `src/OrbitalUI.ZC`.

When you discover a new quirk, append it here AND ideally add a rule to
`scripts/holyc-lint.py` so the next agent catches it offline.

## Layout

```
src/              persistent HolyC: Setup.ZC, Daemon.ZC, your tools  (committed)
tests/            test framework (Assert.ZC) + battery (T_*.ZC)      (committed)
scripts/          bash + python utilities, including zctl            (committed)
tooling/          host-side editor support (VSCode, Neovim, linter)  (committed)
build/            shuttle.img, serial.log, screen.png, qemu sockets  (gitignored)
vendor/zealos/    ZealOS BIOS ISO + installed disk.qcow2             (gitignored)
```

The build script (`scripts/build-shuttle.sh`) auto-discovers
`tests/T_*.ZC` and includes them from `Boot.ZC` in sorted order. To add
a test: drop a file matching `tests/T_*.ZC`. To add reusable HolyC: drop
it in `src/`, then `#include "E:/Whatever.ZC"` from your test.

## Debugging compile errors

The kernel debugger ("I Fault 0x32") fires on parse errors and bad
operations. From the host:

1. `scripts/zctl screenshot` — read the error text and the file:line.
2. Fix the source on the host. The VM's running daemon won't know about
   the change until you rebuild the shuttle.
3. `scripts/zctl down && scripts/zctl up` to pick up the new shuttle.

For pure HolyC iteration without re-cycling the VM, push code through
the daemon (`zctl eval`) — it executes against the live system without
rebooting. Useful for poking at functions, probing ZealOS APIs, and
verifying small fixes before committing them to the test battery.

## When to add to vs read from this file

- **Read:** at the start of any session in this repo, especially before
  writing HolyC.
- **Write:** when you discover a new HolyC quirk, a new ZealOS API
  detail, or a workflow that should be standard. Keep entries terse —
  this is an operational guide, not documentation.

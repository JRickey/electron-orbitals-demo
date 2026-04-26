# HolyC for VSCode

Syntax highlighting and inline lint diagnostics for HolyC / ZealC
(`.ZC`, `.HC`, `.HH`).

Local extension — no marketplace publish step. Two install paths:

## Quick install (symlink)

```sh
# from the repo root:
ln -s "$(pwd)/tooling/holyc-vscode" ~/.vscode/extensions/local.holyc-0.2.0
```

Restart VSCode. Open any `.ZC` file. The mode line should show "HolyC"
and any lint findings appear as inline squiggles.

## Install via VSIX

```sh
cd tooling/holyc-vscode
npx @vscode/vsce package        # produces holyc-0.2.0.vsix
code --install-extension holyc-0.2.0.vsix
```

## What it highlights

- Primitive types: `U0`, `U8`..`U64`, `I0`..`I64`, `F64`, `Bool`
- ZealOS class types: any `C[A-Z]…` identifier (`CFifoU8`, `CBlkDev`, `CTCPSocket`)
- Control flow: `if`, `else`, `while`, `for`, `do`, `switch`, `case`,
  `default`, `break`, `continue`, `goto`, `return`, `try`, `catch`,
  `throw`, plus HolyC's sub-switch `start` / `end`
- Storage modifiers: `extern`, `public`, `static`, `interrupt`,
  `haserrcode`, `argpop`/`noargpop`, `reg`/`noreg`, `no_warn`,
  `lastclass`, `lock`
- Other keywords: `class`, `union`, `sizeof`, `offset`, `asm`
- Constants: `TRUE`, `FALSE`, `NULL`, `ON`, `OFF`
- Standard library / kernel functions used in this repo: `Print`,
  `Sleep`, `Spawn`, `Sys`, `MAlloc`, `Free`, `CommInit8n1`, `CommPrint`,
  `FifoU8Remove`, `BlkDevAdd`, `AHCIPortInit`, `TCPSocketListen`,
  `ExeFile`, `TaskExe`, etc.
- Strings with `\X` C escapes and `$$` DolDoc literal-`$` escape
- Char literals (HolyC allows multi-char: `'ABC'`)
- Hex / decimal / float numbers
- `#include`, `#define`, `#ifdef`, etc. preprocessor directives
- `asm { … }` blocks with label recognition

## Lint diagnostics

The extension activates on the `holyc` language and runs
`scripts/holyc-lint.py` from the workspace root on document open and on
save. Findings appear as inline squiggles (errors red, warnings yellow)
with the rule code visible in the Problems panel.

Rules currently shipped (see `scripts/holyc-lint.py` for source):

- `balance` — unbalanced braces / parens / brackets
- `lex` — unterminated string / char / block comment
- `boot-phase-return` — top-level `return` (boot-phase parser rejects it)
- `boot-phase-goto` — top-level `goto` (no global labels at boot phase)
- `boot-phase-loop` — top-level `for`/`while` whose body declares a type
- `sys-deadlock` — `Sys("Identifier;")` heuristic; queueing an
  infinite-loop function via `Sys()` deadlocks the caller (see
  `src/Daemon.ZC` for why we use `Spawn()` instead)
- `no-tabs`, `trailing-whitespace`, `max-line-length`

If `scripts/holyc-lint.py` is missing from the workspace, the linter
silently no-ops — the extension still highlights.

### Configuration

Settings (workspace or user scope):

- `holyc.pythonPath` — Python interpreter (default `python3`).
- `holyc.lintScript` — path to the linter, relative to workspace root
  unless absolute (default `scripts/holyc-lint.py`).

## What it does NOT do

- Type-aware semantic highlighting. The grammar is regex, not a parser.
- Ground-truth diagnostics. The static linter is approximate. For real
  parser verdicts push the file through the live REPL: `make repl` then
  `scripts/zpush.sh path/to/File.ZC`, and watch `build/serial.log`.
- Auto-fix. Diagnostics only.

## Theming

The grammar only assigns scope names; colors come from your theme. The
grammar uses standard scopes (`storage.type.holyc`,
`keyword.control.holyc`, `support.function.builtin.holyc`, etc.) so any
mainstream theme will paint sensibly.

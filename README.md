# electron-orbitals-demo

Hydrogen-atom electron clouds, rendered in HolyC on ZealOS, in QEMU.
Real wavefunctions, Monte-Carlo sampled, phase-coloured, plotted to
the framebuffer. The cloud is the point. The dev loop is what made it
tractable.

![3d_x²-y² orbital — four-lobe clover with alternating phase](docs/3d_xy.png)

Above: the **3d_x²-y²** orbital viewed near top-down. Four lobes
alternating red ↔ blue around the equator — that's the *sign* of
Y₂,₂(θ,φ), not artistic license. Sampled from `R_32(r) · Y₂,₂(θ,φ)`
by Monte Carlo, no fitted constants, ~25k points.

The smaller image below shows a **2s** orbital — bright inner core,
dark spherical node ring at r ≈ 2 a₀ where ψ_2s crosses zero, brighter
outer shell:

![2s orbital with visible radial node](docs/2s.png)

## What's in here

- **`src/Wavefunc.ZC`** — general `Rnl(n, l, r)` via the associated-
  Laguerre recurrence (any n, any l < n), real spherical harmonics
  `Y_lm` for l = 0..3 (s/p/d/f), and a grid-scan envelope for
  rejection sampling. Atomic units (Z = 1, a₀ = 1).
- **`src/Orbital.ZC`** — radial CDF + inverse sampler; angular
  distribution sampled from |Y_lm|² by rejection. `ScatterSOrbital`
  for one-shot rendering, `BuildRadialCDF`/`SampleR`/`SampleAnglesLM`
  as building blocks.
- **`src/OrbitalUI.ZC`** — interactive explorer (`OrbitalExplorer`,
  `OrbitalExplorerLaunch` for a real WM tile). Held WASD rotates,
  Q/E zooms, `,/.` step n, `[/]` step l, `;/'` step m. Phase coloring
  drives a warm/cool palette so you can see the alternating-sign lobe
  structure of every p/d/f orbital. Auto-rotates when idle.
- **`tests/T_Wavefunc.ZC`**, **`tests/T_Orbital.ZC`** — every closed
  form pinned to a known numeric value or analytic expectation:
  `Rnl(1,0,0) = 2`, `Rnl(2,0,2) = 0` (radial node), `Y_lm` spot
  values + sphere-norm ∫|Y_lm|² dΩ = 1, ∫|R_nl|² r² dr = 1 for n up
  to 7, and ⟨r⟩ from the sampler vs `½[3n² − l(l+1)]` for shells
  through 7s.

42/42 tests green.

## Run it

Fresh clone, fresh disk. Prerequisites: `qemu-system-x86_64` (`brew
install qemu`), the standard macOS toolchain (hdiutil, dd, python3,
nc, sips), ~5 GB free.

```sh
make setup           # fetch ZealOS BIOS ISO (~44 MB)
make disk            # create blank 4 GB qcow2
make install         # interactive install — y / I / Y at the prompts
                     # close QEMU when ZealOS desktop is up
scripts/zctl up      # start the dev VM, dismiss boot menu, wait for daemon
scripts/zctl wire    # one-shot post-install: mount shuttle + Setup.ZC
scripts/zctl down && scripts/zctl up   # subsequent boots auto-mount
```

Then:

```sh
make test                                                # 42/42
scripts/zctl eval '#include "E:/OrbitalUI.ZC"; OrbitalExplorerLaunch;'
scripts/zctl screenshot
```

That spawns a real WM-tiled explorer. Inside it:

| key   | action                                              |
|-------|-----------------------------------------------------|
| WASD  | yaw / pitch (held — smooth, manual rotation)        |
| Q / E | zoom out / in (held — multiplicative, smooth)       |
| `,` `.` | step n (1..7)                                     |
| `[` `]` | step l (0..n-1, capped at f)                      |
| `;` `'` | step m (-l..+l)                                   |
| ESC   | quit                                                |

The cloud auto-rotates after 3 s without manual rotation. Stepping
through n / l / m or zooming doesn't reset the idle timer, so you can
browse the orbital zoo while it keeps spinning.

## How it works

Sampling `|ψ_nlm(r, θ, φ)|² r² sin θ dr dθ dφ`:

1. **Radial.** Build a CDF of `p(r) = |R_nl(r)|² r²` over `[0, r_max]`
   on a 4 000-step grid. Inverse-sample for r. `R_nl` is computed
   from the associated-Laguerre recurrence, so any (n, l) with l < n
   works — n up to 7 is exercised by the tests.
2. **Angular.** For l > 0 the distribution isn't uniform. We sample
   directions by **rejection on |Y_lm|²** with a uniform-on-sphere
   proposal — the envelope is a grid-scan max of |Y_lm|² scaled by
   1.05. One-time cost paid at cloud generation, not per frame.
3. **Phase.** Record sign(Y_lm) at each sample. Render warm palette
   (brown → red → light-red → yellow) for positive lobes, cool palette
   (blue → light-blue → cyan → white) for negative; depth modulates
   brightness. So a p_z dumbbell comes out red on one side, blue on
   the other — the way the textbook draws it.
4. **Interaction.** Sample once into a body-frame point cloud, then
   apply yaw-pitch + an auto-fit · zoom scale per frame. Rotation and
   zoom never resample, so they stay smooth even at 25k+ points.

For the math see any standard QM text — Griffiths, Cohen-Tannoudji.

## Upstream

Built on top of [`rshtirmer/templeos-devkit`](https://github.com/rshtirmer/templeos-devkit) —
the host↔guest dev-loop scaffolding (shuttle disk, serial-out test
harness, REPL daemon over COM2). For full devkit documentation see
upstream's docs.

Several improvements from this fork are open as PRs against upstream:
QEMU display fix for macOS Retina, host-side HolyC tooling
(VSCode/Neovim/linter), `scripts/zctl` (single-process control plane
for the VM with synchronous eval), and a couple of unused-variable
warning suppressions that were polluting the framebuffer.

## Agent guide

[`CLAUDE.md`](CLAUDE.md) is the agent onboarding doc — covers `zctl`
usage, the daemon protocol, and the HolyC quirks we hit during this
build. Read it before writing HolyC.

## Credits

- [Terry A. Davis](https://en.wikipedia.org/wiki/Terry_A._Davis),
  1969–2018 — wrote TempleOS, HolyC, the editor, the compiler, the
  games, the oracle, alone.
- [ZealOS](https://github.com/Zeal-Operating-System/ZealOS) — the
  modernized 64-bit fork we actually run.
- The hydrogen wavefunctions are textbook quantum mechanics; the
  novelty is purely in writing them out in HolyC.

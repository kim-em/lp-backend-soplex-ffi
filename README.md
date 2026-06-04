# LPBackendSoplexFFI

[![Lean](https://img.shields.io/badge/Lean-4.31.0--rc1-blue.svg)](./lean-toolchain)
[![License](https://img.shields.io/github/license/kim-em/lp-backend-soplex-ffi.svg)](./LICENSE)

`LPBackend` adapter for the SoPlex FFI binding. Wraps the
synchronous `Soplex.solveExact` from
[`kim-em/soplex-ffi`](https://github.com/kim-em/soplex-ffi) into
the abstract `LPBackend` record defined in
[`kim-em/lp-core`](https://github.com/kim-em/lp-core), and
self-registers with the
[`kim-em/lp-tactic`](https://github.com/kim-em/lp-tactic) registry
under priority 10 ("FFI band") on import.

This is the production-grade native backend for the `by lp` tactic
— what the meta-package
[`kim-em/soplex`](https://github.com/kim-em/soplex) defaults to when
no `set_option lp.backend` or per-call argument overrides it.
Depend on this repo directly only when you want the SoPlex FFI
specifically without the full `kim-em/soplex` tactic surface (e.g.
to register the backend in your own Lake project that wires the
verifier and tactic differently).

This is the only package in the `kim-em/soplex` family besides
`soplex-ffi` itself that carries `moreLinkArgs`: the SoPlex C++
runtime link args propagate to anything that links this library.

## Quickstart

```lean
require LPBackendSoplexFFI from git
  "https://github.com/kim-em/lp-backend-soplex-ffi" @ "main"
```

```lean
import LPBackendSoplexFFI  -- self-registers "soplex-ffi" at priority 10
import LPTactic            -- the `by lp` tactic

example (a b : Rat) (_ : 2 * a + b ≤ 5) (_ : a - b ≤ 1) :
    3 * a ≤ 6 := by lp
```

## Build

System dependencies (same as `kim-em/soplex-ffi`):

| Platform | Packages |
|----------|----------|
| Linux    | `build-essential cmake libgmp-dev libgmpxx4ldbl libboost-dev` |
| macOS    | `brew install gmp boost cmake` (plus Xcode Command Line Tools) |
| Windows  | MSYS2 `mingw-w64-x86_64-{gcc,cmake,ninja,make,gmp,boost}` |

## Layout

```
LPBackendSoplexFFI.lean        # top-level import
LPBackendSoplexFFI/Adapter.lean
                               # def backend : LPBackend + initialize registerBackend
```

The adapter lives under `namespace Soplex.Backend.SoplexFFI`,
matching the namespace used before the split. Consumers writing
`Soplex.Backend.SoplexFFI.backend` resolve to the same value
regardless of which package owns it.

## Licence

[Apache License 2.0](./LICENSE).

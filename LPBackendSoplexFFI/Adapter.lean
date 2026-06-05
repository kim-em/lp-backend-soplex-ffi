/-
  `LPBackend` adapter for the SoPlex FFI binding.

  Wraps the synchronous `SoplexFFI.solveExact` into the abstract
  `LPBackend` interface defined in `leanprover/lp-core`, and registers
  itself with the process-global registry from `leanprover/lp-tactic`
  under priority 10 (FFI band) on import.
-/
module

public import LPCore.Backend
public import LPTactic.Registry
public import SoplexFFI.Basic

@[expose] public section

namespace LP.Backend.SoplexFFI

open LP

/-- The FFI-backed backend. Synchronous `Except` lifted into `IO` via
    `pure`; the wrapped call already runs the FFI on the calling
    thread. Registered under priority `10` (FFI band). -/
def backend : LPBackend where
  name := "soplex-ffi"
  defaultPriority := 10
  solveExact opts p := pure (LP.solveExact opts p)
  -- Linking succeeded at build time and dynamic loading is exercised
  -- elsewhere (`ffi-check`); if either fails the user sees a load-time
  -- error long before the probe runs. The probe stays trivially `.ok`.
  probe := pure (.ok ())

/-- Self-register on import. Throws on duplicate registration, which
    only happens if a caller already manually registered a backend
    under the name `"soplex-ffi"` before this module loaded. -/
initialize registerBackend backend

end LP.Backend.SoplexFFI

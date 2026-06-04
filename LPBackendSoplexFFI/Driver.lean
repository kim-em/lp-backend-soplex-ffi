/-
  FFI-specific verified-solve driver.

  `LP.solveVerified` is the synchronous, `Except`-typed companion
  to `LPTactic.solveVerifiedWith`. It hard-codes `SoplexFFI.solveExact`
  as its solver because that call is synchronous (the GMP-backed
  binding returns immediately) — so the driver itself can stay out of
  `IO`. The pluggable, `IO`-typed entry point for any registered
  backend is `solveVerifiedWith` in `leanprover/lp-tactic`.

  This file lives in `leanprover/lp-backend-soplex-ffi` (not `lp-tactic`)
  so that `lp-tactic` has no FFI dependency in its build graph: a
  verifier-only-without-SoPlex consumer can depend on `lp-verify` and
  `lp-tactic` and never link the SoPlex runtime.
-/

import LPCore.Validate
import LPVerify
import SoplexFFI.Basic
import LPTactic.Basic

namespace LP

/-- Drive `validate`, `SoplexFFI.solveExact`, then the checker,
    packaged as a `VerifiedSolve` carrying a real soundness-lemma
    proof.

    The semantics match `solveVerifiedWith LP.Backend.SoplexFFI.backend`
    exactly, except the result type is `Except SolveError ...` rather
    than `IO (Except SolveError ...)`. -/
def solveVerified {m n : Nat} (opts : Options) (p : Problem m n)
    (denomBudget : Option Nat := defaultDenomBudget) :
    Except SolveError (Verify.VerifiedSolve (m := m) (n := n) opts.sense) := do
  let _ ← validateOptions opts |>.mapError SolveError.invalidOptions
  let normalized ← validate p |>.mapError SolveError.invalidProblem
  let opts' := { opts with presolve := false }
  let sol ← solveExact opts' normalized
  pure { normalized
         verified := Verify.verifyOutcome opts denomBudget normalized sol }

end LP

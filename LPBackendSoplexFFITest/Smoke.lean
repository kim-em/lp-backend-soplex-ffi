/-
  Smoke + parity tests for the FFI backend adapter.

  Exercises the probe, then solves the same problems through both
  verified drivers:

  * `LP.solveVerified` — the synchronous, `Except`-typed driver owned
    by this package (`Driver.lean`);
  * `solveVerifiedWith LP.Backend.SoplexFFI.backend` — the pluggable
    `IO`-typed driver in `leanprover/lp-tactic`.

  The two intentionally share semantics but not code (one is pure,
  one is `IO`), so this suite is what pins them together: if the glue
  in either driver drifts (e.g. one stops forcing `presolve := false`),
  the parity cases fail.

  Run via `lake test` (the `smoke-tests` executable).
-/

import LPBackendSoplexFFI

open LP LP.Verify

namespace LPBackendSoplexFFITest.Smoke

private def assertM (cond : Bool) (msg : String) : IO Unit := do
  unless cond do throw (IO.userError msg)

/-- Observable summary of a `VerifiedSolve`, for parity comparison. -/
private def summary {m n : Nat} {sense : ObjSense}
    (vs : VerifiedSolve (m := m) (n := n) sense) : String :=
  match vs.verified with
  | .optimal x _     => s!"optimal {repr x.toArray}"
  | .infeasible _    => "infeasible"
  | .unbounded x r _ => s!"unbounded {repr x.toArray} ray {repr r.toArray}"
  | .unchecked s     => s!"unchecked {repr s}"

/-- Run a problem through both drivers and require identical outcomes. -/
private def assertParity {m n : Nat} (label : String) (opts : Options)
    (p : Problem m n) (expected : Option String := none) : IO Unit := do
  let viaSync ← match LP.solveVerified opts p with
    | .ok vs => pure (summary vs)
    | .error e => pure s!"error {repr e}"
  let viaWith ← match ← solveVerifiedWith Backend.SoplexFFI.backend opts p with
    | .ok vs => pure (summary vs)
    | .error e => pure s!"error {repr e}"
  assertM (viaSync == viaWith)
    s!"[{label}] drivers disagree: solveVerified => {viaSync}, solveVerifiedWith => {viaWith}"
  if let some want := expected then
    assertM (viaSync == want) s!"[{label}] got {viaSync}, want {want}"

def case_probe : IO Unit := do
  match ← Backend.SoplexFFI.backend.probe with
  | .ok () => pure ()
  | .error e => throw (IO.userError s!"probe failed: {e}")

/-- The quickstart LP: maximize 3x₀ + 5x₁ subject to x₀ ≤ 4, 2x₁ ≤ 12,
    3x₀ + 2x₁ ≤ 18, x ≥ 0; optimum x = (2, 6). -/
def case_optimal : IO Unit := do
  let p : Problem 3 2 :=
    { c         := #v[3, 5]
      a         := #[(0, 0, 1), (1, 1, 2), (2, 0, 3), (2, 1, 2)]
      rowBounds := #v[(none, some 4), (none, some 12), (none, some 18)]
      colBounds := #v[(some 0, none), (some 0, none)] }
  assertParity "optimal" { sense := .maximize } p
    (expected := some s!"optimal {repr (#[(2 : Rat), 6])}")

/-- Infeasible: the row says x ≥ 1, the column bound says x ≤ 0. -/
def case_infeasible : IO Unit := do
  let p : Problem 1 1 :=
    { c := #v[0], a := #[(0, 0, 1)]
      rowBounds := #v[(some 1, none)], colBounds := #v[(none, some 0)] }
  assertParity "infeasible" {} p (expected := some "infeasible")

/-- Unbounded below: minimize -x with x ≥ 0 and no rows. -/
def case_unbounded : IO Unit := do
  let p : Problem 0 1 :=
    { c := #v[-1], a := #[], rowBounds := #v[], colBounds := #v[(some 0, none)] }
  let r ← match LP.solveVerified {} p with
    | .ok vs => pure (summary vs)
    | .error e => throw (IO.userError s!"[unbounded] solve error: {repr e}")
  assertM (r.startsWith "unbounded") s!"[unbounded] got {r}"

def main : IO UInt32 := do
  case_probe
  case_optimal
  case_infeasible
  case_unbounded
  IO.println "lp-backend-soplex-ffi smoke tests: all passed"
  return 0

end LPBackendSoplexFFITest.Smoke

def main : IO UInt32 := LPBackendSoplexFFITest.Smoke.main

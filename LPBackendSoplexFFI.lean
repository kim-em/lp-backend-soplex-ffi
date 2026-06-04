/-
  Top-level entry point for `LPBackendSoplexFFI`.

  Re-exported by `leanprover/lp` through `LP.Backend.SoplexFFI`
  so existing callers keep working unchanged. Self-registers the
  FFI backend with the `lp-tactic` registry on import.
-/
module

public import LPBackendSoplexFFI.Adapter
public import LPBackendSoplexFFI.Driver

@[expose] public section

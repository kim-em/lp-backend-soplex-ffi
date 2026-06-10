import Lake
open System Lake DSL

/-! # `LPBackendSoplexFFI` build configuration

  The `LPBackend` adapter for `leanprover/soplex-ffi`. This is the only
  package besides `soplex-ffi` itself that carries `moreLinkArgs`.

  Self-registers under priority 10 ("FFI band") on import via an
  `initialize` block that calls `LPTactic.registerBackend`.
-/

require LPCore from git "https://github.com/leanprover/lp-core" @ "96d003f40ada9c730ae9fe100716214273be651b"

require LPTactic from git "https://github.com/leanprover/lp-tactic" @ "008252423f29f152cdd3bc4224897dadfab23be7"

require SoplexFFI from git "https://github.com/leanprover/soplex-ffi" @ "18a2f366482fcb4f3c6418f60f1558493c5148a8"

def sanitizerEnabled : Bool :=
  match get_config? sanitize with
  | some s => s != "0" && s != "false"
  | none => false

def sanitizerArgs : Array String :=
  if sanitizerEnabled then
    #["-fsanitize=address", "-fsanitize=undefined",
      "-fno-sanitize=vptr,function",
      "-fno-omit-frame-pointer", "-g"]
  else
    #[]

/-! ## Locating the `SoplexFFI` package directory

The Windows link step names absolute paths to MinGW archives that
`SoplexFFI` stages under its own `vendor/mingw-libs/`. `moreLinkArgs`
is plain `Array String` evaluated at config-eval time, so we need the
directory of the resolved `SoplexFFI` dependency before any build
target runs. Lake exposes no config-eval API for that, so we infer it
from `__dir__`.

Two supported layouts, discriminated by `__dir__`'s tail: fetched
into `<workspace>/.lake/packages/<us>` (transitive git dependency,
e.g. under `leanprover/lp` — `SoplexFFI` is then our sibling), or
building as the workspace root (`SoplexFFI` is under our own
`.lake/packages/`). Not covered: local path dependencies and a
custom `WorkspaceConfig.packagesDir`. The long-term fix is for
`SoplexFFI` to carry the MinGW archives in its `extern_lib`s so
consumers never need its directory; see
https://github.com/leanprover/lp-backend-soplex-ffi/issues/1. -/
def soplexFFIRoot : FilePath :=
  let here : FilePath := __dir__
  let parent? : Option FilePath := FilePath.parent here
  let grandparent? : Option FilePath := parent?.bind FilePath.parent
  let isTransitive : Bool :=
    parent?.bind FilePath.fileName == some "packages" &&
    grandparent?.bind FilePath.fileName == some ".lake"
  if isTransitive then
    here / ".." / "SoplexFFI"
  else
    here / defaultPackagesDir / "SoplexFFI"

def soplexFFIRuntimeLinkArgs : Array String :=
  if System.Platform.isOSX then
    #[]
  else if System.Platform.isWindows then
    let mingwLibDir := soplexFFIRoot / "vendor" / "mingw-libs"
    #["-Wl,--allow-multiple-definition",
      (mingwLibDir / "libstdc++.a").toString,
      (mingwLibDir / "libgmpxx.a").toString,
      (mingwLibDir / "libgmp.a").toString,
      s!"-L{mingwLibDir}",
      "-lgcc_s",
      "-lmingwex",
      "-lmsvcrt"]
  else
    #["-L/usr/lib/x86_64-linux-gnu",
      "-L/usr/lib/aarch64-linux-gnu",
      "-L/usr/lib64",
      "-L/usr/lib"] ++ sanitizerArgs

package LPBackendSoplexFFI where
  moreLinkArgs := soplexFFIRuntimeLinkArgs

@[default_target]
lean_lib LPBackendSoplexFFI where
  roots := #[`LPBackendSoplexFFI]
  globs := #[`LPBackendSoplexFFI, `LPBackendSoplexFFI.Adapter, `LPBackendSoplexFFI.Driver]
  precompileModules := !sanitizerEnabled
  moreLinkArgs := soplexFFIRuntimeLinkArgs
  -- Force `SoplexFFI`'s native build before this library's modules
  -- link; matches the same edge the meta-package carried pre-split.
  needs := #[BuildKey.packageTarget `SoplexFFI `soplexffi]

/-- Behavioral smoke tests: probe + real solves through both
    `LP.solveVerified` and `solveVerifiedWith backend`, asserting the
    two drivers agree (they intentionally share semantics but not
    code — `solveVerified` stays synchronous / `Except`-typed). -/
@[test_driver]
lean_exe «smoke-tests» where
  root := `LPBackendSoplexFFITest.Smoke

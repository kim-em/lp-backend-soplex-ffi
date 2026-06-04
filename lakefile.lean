import Lake
open System Lake DSL

/-! # `LPBackendSoplexFFI` build configuration

  The `LPBackend` adapter for `leanprover/soplex-ffi`. This is the only
  package besides `soplex-ffi` itself that carries `moreLinkArgs`.

  Self-registers under priority 10 ("FFI band") on import via an
  `initialize` block that calls `LPTactic.registerBackend`.
-/

require LPCore from git "https://github.com/leanprover/lp-core" @
  "70ca150585f8439a830374b5bec602d391addbc9"

require LPTactic from git "https://github.com/leanprover/lp-tactic" @
  "3f1309f8f3cda3c1f67a0af70eb68eb5836f38fa"

require SoplexFFI from git "https://github.com/leanprover/soplex-ffi" @
  "0849137dd4d7ad68edb9c616a6e9f9a7625be529"

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

The previous lakefile assumed exactly one layout — that `SoplexFFI`
was always our sibling at `__dir__/../SoplexFFI`. That holds when this
package is a transitive git-dependency under another workspace (e.g.
`leanprover/lp`), where Lake checks both packages out under the
meta-workspace root's `.lake/packages/`. It does **not** hold when
this package builds as its own workspace root (the standalone CI
added in 47d8258), where `SoplexFFI` is instead fetched under our
own `.lake/packages/`. The original code broke Windows CI in the
standalone case.

We discriminate the two layouts by inspecting `__dir__`'s tail: if
our parent dir is named `packages` and our grandparent is `.lake`,
this package was fetched into `<workspace>/.lake/packages/<us>` and
we're transitive; otherwise we treat ourselves as the workspace root.

Known limitations (Lake configurations not covered):

* **Local path dependencies.** If a meta-workspace requires this
  checkout via `from "/some/local/path"`, `__dir__` is `/some/local/path`
  and the heuristic falls through to the standalone branch — but
  `SoplexFFI` lives at the meta-workspace's `.lake/packages/SoplexFFI`,
  not under our local checkout.
* **Custom `packagesDir`.** A workspace can override Lake's default
  `.lake/packages` via `WorkspaceConfig.packagesDir`. With a non-default
  name, the parent-component check no longer fires.

Neither case is exercised by the CI jobs this PR is targeting
(standalone build of this repo on Windows; consumption from
`leanprover/lp` via a git `require`). A more robust long-term fix is
to push the MinGW archives into `SoplexFFI`'s `extern_lib`s and let
Lake's `LeanExe.recBuildExe` propagate them via `transDeps.externLibs`
to consuming executables, which would eliminate the need for this
package to know `SoplexFFI`'s directory at all. See issue #1 for
discussion. -/
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

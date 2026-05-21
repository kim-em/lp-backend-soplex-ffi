import Lake
open System Lake DSL

/-! # `LPBackendSoplexFFI` build configuration

  The `LPBackend` adapter for `kim-em/soplex-ffi`. This is the only
  package besides `soplex-ffi` itself that carries `moreLinkArgs`.

  Self-registers under priority 10 ("FFI band") on import via an
  `initialize` block that calls `LPTactic.registerBackend`.
-/

require LPCore from git "https://github.com/kim-em/lp-core" @
  "60fca2313ea3be14f578258dc6390f2fa07b26e7"

require LPTactic from git "https://github.com/kim-em/lp-tactic" @
  "6190fbde9547d314157da5badcbf77493bd4e454"

require SoplexFFI from git "https://github.com/kim-em/soplex-ffi" @
  "a1389a99c2345f9d72ffdc2941be350ad0f97fd7"

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

-- Lake dedupes packages at the workspace root, so when `LPBackendSoplexFFI`
-- is consumed as a transitive dependency, `SoplexFFI` is checked out as a
-- sibling under `<workspace>/.lake/packages/SoplexFFI`, *not* nested under
-- this package's own `.lake/packages/`. Reach it via `..`.
def soplexFFIRoot : FilePath := __dir__ / ".." / "SoplexFFI"

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

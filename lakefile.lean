import Lake
open System Lake DSL

/-! # `LPBackendSoplexFFI` build configuration

  The `LPBackend` adapter for `leanprover/soplex-ffi`. This is the only
  package besides `soplex-ffi` itself that carries `moreLinkArgs`.

  Self-registers under priority 10 ("FFI band") on import via an
  `initialize` block that calls `LPTactic.registerBackend`.
-/

require LPCore from git "https://github.com/leanprover/lp-core" @ "f5a81cfad47fce9cb6b8d99484bb5da3ad27b645"

require LPTactic from git "https://github.com/leanprover/lp-tactic" @ "ca3b958b4ace7f03191e2efa4ec101eb16765c0c"

require SoplexFFI from git "https://github.com/leanprover/soplex-ffi" @ "ad55436c1ecde020f163124fa900cbbc56914582"

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

/-- The Lean toolchain's own `lib` directory, passed by CI as
    `-KleanLibDir=...` (`$(lean --print-prefix)/lib`). Used by the
    sanitizer lane to put the toolchain libc++ ahead of the
    `-L/usr/lib*` dirs that lane needs. -/
def leanLibDirArgs : Array String :=
  match get_config? leanLibDir with
  | some d => #[s!"-L{d}"]
  | none => #[]

def soplexFFIRuntimeLinkArgs : Array String :=
  if System.Platform.isOSX then
    #[]
  else if System.Platform.isWindows then
    let mingwLibDir := soplexFFIRoot / "vendor" / "mingw-libs"
    -- The Lean toolchain's `crt2.o` references `_gnu_exception_handler` and
    -- `__mingw_oldexcpt_handler` — mingw-w64 CRT compatibility symbols that
    -- recent MSYS2 packages (mid-2026) stopped exporting from `libmingw32.a`,
    -- so `ld.lld` reports them as undefined when linking any Lean executable
    -- on Windows. `SoplexFFI`'s `stageMingwLibs` compiles a tiny pass-through
    -- stub (`mingw_crt_handler_stub.o`) next to the staged MSYS2 archives;
    -- naming it here resolves the link. See
    -- https://github.com/leanprover/lp/issues/170.
    #["-Wl,--allow-multiple-definition",
      s!"-L{mingwLibDir}",
      (mingwLibDir / "mingw_crt_handler_stub.o").toString,
      "-Wl,--start-group",
      (mingwLibDir / "libstdc++.a").toString,
      (mingwLibDir / "libgmpxx.a").toString,
      (mingwLibDir / "libgmp.a").toString,
      "-lmingw32",
      "-lgcc_s",
      "-lmingwex",
      "-lmsvcrt",
      "-Wl,--end-group"]
  else if sanitizerEnabled then
    -- Sanitizer lane: the ASan runtime link needs the `-L/usr/lib*`
    -- dirs, but those also hold Ubuntu's `libc++.so`; keep the
    -- toolchain lib dir FIRST so `-lc++` binds to the toolchain's.
    leanLibDirArgs ++
    #["-L/usr/lib/x86_64-linux-gnu",
      "-L/usr/lib/aarch64-linux-gnu",
      "-L/usr/lib64",
      "-L/usr/lib"] ++ sanitizerArgs
  else
    -- Default Linux lane: do NOT add `-L/usr/lib*`. Those dirs hold
    -- Ubuntu's libc++, and a command-line `-L` is searched before the
    -- toolchain's own lib dir, shadowing the toolchain libc++ for
    -- `-lc++`. Ubuntu's libc++ 18 lacks the C++20 symbols
    -- (`std::__1::__hash_memory`, `__atomic_wait_native`) that
    -- toolchain-built `libleanrt.a`/`libleancpp.a` reference, which
    -- breaks executable links (dynlibs tolerate the unresolved
    -- symbols; exes do not). GMP resolves via the toolchain clang's
    -- default search dirs. Mirrors `leanprover/lp`'s lakefile.
    #[]

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

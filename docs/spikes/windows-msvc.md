# Spike: an MSVC build of Dawn for the `mingwX64` target

**Verdict: `feasible`.** Measured end to end: MSVC builds Dawn into a DLL plus
its import library, and a real `mingwX64` Kotlin/Native cinterop project links
that import library and runs against the DLL. Two constraints come with it: the
Windows archives need the VC++ runtime, and the pipeline needs the changes listed
at the end of this document.

Context: the `mingwX64` target is `dropped` because building Dawn for it with
MinGW-w64 is infeasible (see `docs/spikes/mingw-x64.md`). The documented fallback
is to build Dawn with MSVC on a Windows runner and consume the resulting DLL
from Kotlin/Native's `mingwX64` target through its import library. Kotlin/Native's
Windows target stays `mingwX64` (`x86_64-pc-windows-gnu`) either way: only the
*builder* changes, and the C API boundary is what makes that possible.

## Environment

Measured on `windows-2022` with the spike workflow (`.github/workflows/spike-windows-msvc.yml`).

| Item | Value |
| --- | --- |
| MSVC | 19.44.35229.0 (VS 2022 Enterprise, tools 14.44.35207) |
| Windows SDK | 10.0.26100.0, `d3dcompiler_47.dll` present under `Windows Kits\10\bin` |
| CMake / Ninja | 3.31.6 / preinstalled |
| Python | 3.12.10 |
| MinGW-w64 | `C:\mingw64\bin` (`gcc`, `x86_64-w64-mingw32-gcc`) |
| `dumpbin` | `VC\Tools\MSVC\14.44.35207\bin\HostX64\x64\dumpbin.exe` |
| Dawn pin | `chromium/8077` @ `531028367c60ce07251ec0231c1b95bedb4495bc` |

Two notes that cost a round: MinGW is **not** under `C:\msys64` on this image, and
`C:\mingw64\bin` is already on `PATH` even outside the MSVC environment.

## Commands and results

### 1. Configure and build, MSVC 19.44 + Ninja

```powershell
cmake -S . -B build/spike-static -G Ninja `
  -DCMAKE_BUILD_TYPE=Release -DDAWN_PACKER_LINKAGE=STATIC -DDAWN_EMIT_COVERAGE=OFF `
  -DCMAKE_INSTALL_PREFIX=dist/spike-static `
  -DDAWN_ENABLE_D3D12=ON -DDAWN_ENABLE_NULL=ON
cmake --build build/spike-static --target dawn_packer
cmake --install build/spike-static --prefix dist/spike-static
```

Result: **succeeded**, 1122 build steps, no errors. The same for
`-DDAWN_PACKER_LINKAGE=SHARED`.

Install trees:

* static: `lib/webgpu_dawn.lib`, plus the headers and `lib/cmake/Dawn/*.cmake`;
* shared: **`bin/webgpu_dawn.dll`** and `lib/webgpu_dawn.lib` (the import
  library), plus the same headers and CMake package files.

Two configuration facts worth recording:

* Dawn does not build `protoc` here as a cross tool: host == target, so
  `CMAKE_CROSSCOMPILING` is false and the wrapper's `-DPROTOC_EXECUTABLE` path is
  not needed. The MSVC route actually *simplifies* the `mingwX64` matrix entry,
  whose `toolchain` field would become empty.
* Dawn's CMake forces `ENABLE_D3D11`, `ENABLE_D3D12`, `ENABLE_VULKAN` and
  `USE_WINDOWS_UI` ON whenever `WIN32` is set (`dawn/CMakeLists.txt:96-104`), so
  the matrix's `d3d12` + `null` list is not what gets built: the Windows archives
  also carry Vulkan (SPIRV-Tools objects are visible in the build log) and
  D3D11. That is an accepted constraint, not an accident.

Unlike the Linux build, the C++20 module target (`dawncpp_module`) needs no
special handling here: CMake 3.31 with MSVC 19.44 provides import-graph scanning,
so no Clang is required on Windows.

### 2. Export control on the DLL

The root `CMakeLists.txt` restricts exported symbols with an ELF version script
on every non-Apple platform. Generated link flags for the shared build:

```
LINK_FLAGS = /machine:x64 /INCREMENTAL:NO  -Wl,--version-script=.../webgpu_dawn_exports.map
```

So the ELF-only option *is* handed to MSVC's linker. The DLL links anyway, and the
resulting export table is exactly what the public-API promise requires:

```
export count: 387
exports outside wgpu/dawn: 0
```

`__declspec(dllexport)`, which Dawn's headers already use, restricts the export
table on its own: no leak, and no export option was needed. Two consequences:

* the version script is dead weight on Windows and should be guarded by a `WIN32`
  branch, because a GNU-side Windows linker would try to honour it (a version
  script is an ELF concept, and the target is PE);
* on Linux the same guarantee needed an explicit version script (276 symbols,
  0 leaks, measured in CI); on Windows it comes for free.

Whether `link.exe` reports `LNK4044` (unrecognised option) for the flag: it does
not. A grep of the build log for `LNK4044`, `unrecognized option` and
`version-script` finds nothing, so the linker swallowed the option silently
rather than warning about it.

### 3. MinGW consumes the MSVC import library

The whole point of the fallback: a GNU-ABI consumer, which is what Kotlin/Native's
`mingwX64` target uses, compiling the same C source as the Linux smoke test and
linking the MSVC import library.

```powershell
& "C:\mingw64\bin\gcc.exe" -I dist/spike-shared/include -c scripts/smoke-test/link-test.c -o probe/link-test.o
& "C:\mingw64\bin\gcc.exe" probe/link-test.o dist/spike-shared/lib/webgpu_dawn.lib -o probe/link-test.exe
Copy-Item dist/spike-shared/bin/webgpu_dawn.dll probe/
./probe/link-test.exe
```

Result:

```
gcc.exe (x86_64-posix-seh-rev2, Built by MinGW-Builds project) 14.2.0
compile exit: 0
link exit: 0
dawn-packer smoke test OK
run exit: 0
```

So the pair works: MSVC builds the DLL, GNU ld links against the MSVC import
library, and the executable loads the DLL and calls into it. The C API boundary
is what makes the mismatch harmless, and the consumer's triple stays
`x86_64-pc-windows-gnu`.

### 4. Runtime dependencies of the DLL

```
MSVCP140.dll
MSVCP140_ATOMIC_WAIT.dll
VCRUNTIME140.dll
VCRUNTIME140_1.dll
USER32.dll
api-ms-win-core-*.dll
```

The `api-ms-win-core-*` and `USER32` entries are Windows system libraries, but
the four `MSVC*`/`VCRUNTIME*` ones are the Visual C++ redistributable. Shipping
the DLL as-is therefore makes the VC++ redistributable a requirement for
consumers. Building with the static CRT
(`-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded`) is the obvious way out and is
being measured; if it works, the archives stay self-contained like the other
targets.

## Not yet managed by the pipeline

Measured locally by running `scripts/package.sh` over a tree shaped like the MSVC
shared install (`bin/webgpu_dawn.dll`, `lib/webgpu_dawn.lib`, `include/...`):

* `scripts/package.sh` stages and archives only `include` and `lib`, so **the DLL
  is dropped**: the archive ships the import library without the library it
  imports.
* `packaging/make-manifest.py` globs `lib/*.dll` but not `bin/*.dll`, so the DLL
  does not even appear in the manifest.
* Nothing fails: `packaging/validate-manifest.py` passes and the manifest's own
  comment claims an inventory exhaustive over what `package.sh` stages. The
  omission is silent.

Other gaps found by reading, all on the Windows path:

* `build.yml` derives the host target with `case "$(uname -s)/$(uname -m)"` and
  errors on anything but Darwin/Linux; there is no Windows arm, so the job would
  fail before building.
* `scripts/run-smoke-test.sh` handles Darwin and Linux and exits with
  "unsupported OS" elsewhere. A Windows smoke test needs MinGW gcc, the import
  library, and the DLL next to the executable.
* `targets/matrix.json` allows `os: windows` with `status: v1` and an empty
  `toolchain`, so no schema change is needed; `d3d11` is however missing from
  `ALLOWED_BACKENDS` in `packaging/validate-matrix.py`, and from the backend
  mapping in `scripts/build-target.sh`.

### 5. The static CRT is a dead end

Setting `-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded` to drop the VC++ runtime
dependency fails at link:

```
time_zone_libc.cc.obj : error LNK2019: unresolved external symbol __imp__mktime64
  referenced in function ... absl::time_internal::cctz::TimeZoneLibC::MakeTime...
dawn\webgpu_dawn.dll : fatal error LNK1120: 4 unresolved externals
```

Abseil's cctz expects `mktime64` through the UCRT import library, which the
static CRT does not provide. Working around it means patching Abseil, which is the
same kind of out-of-scope patch that rules out the MinGW route. The DLL therefore
keeps its `MSVCP140`/`VCRUNTIME140` dependency; see the distribution note in the
verdict.

### 6. A real `mingwX64` Kotlin/Native consumer

The acceptance criterion: a Kotlin/Native project whose bindings come from
`webgpu.h`, linked against the MSVC import library and executed.

```
headers = webgpu/webgpu.h
package = webgpu
compilerOpts = -I<install>/include
linkerOpts = <install>/lib/webgpu_dawn.lib
```

```
cinterop -def webgpu.def -o webgpu -target mingw_x64 -compiler-option -I<install>/include
  -> webgpu.klib                                    (cinterop exit: 0)
kotlinc-native main.kt -library <path>/webgpu.klib -target mingw_x64 -o app \
  -linker-option <install>/lib/webgpu_dawn.lib
  -> app.exe                                        (kotlinc-native exit: 0)
./app.exe
  -> kotlin/native mingwX64 webgpu smoke test OK    (run exit: 0)
```

Three details cost a round each and are worth recording, because they are probe
requirements rather than toolchain limits:

* `cinterop` needs the include directory passed on the command line
  (`-compiler-option -I...`) as well as in the `.def`; with only the `.def`'s
  `compilerOpts` it fails with `fatal error: 'webgpu/webgpu.h' file not found`;
* `-library` takes a **path**, not a name (`-library <path>/webgpu.klib`); `-repo`
  does not exist in Kotlin/Native 2.4.20, and a klib passed as a positional input
  is rejected with `source entry is not a Kotlin file`;
* consuming cinterop declarations requires
  `@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)`.

### 7. The static linkage links, and is still not shippable

The answer was not the expected one. An MSVC static library does link from MinGW,
with three extra import libraries:

```powershell
& gcc.exe probe/link-test.o dist/spike-static/lib/webgpu_dawn.lib `
    "<VC Tools>\lib\x64\vcruntime.lib" `
    "<VC Tools>\lib\x64\oldnames.lib" `
    "<Windows Kits>\Lib\10.0.26100.0\ucrt\x64\ucrt.lib" `
    -o probe/link-test.exe
```

```
=== attempt 1: dynamic CRT import libraries only (3 libraries) ===
link exit: 0
STATIC LINK (dynamic CRT): OK
```

So the static question is not settled by link failure. It is settled by four
observations, none of which is about the link itself:

* the three libraries that make it work are `vcruntime.lib` and `oldnames.lib`
  from the MSVC toolset and `ucrt.lib` from the Windows SDK. None of them can
  travel in the archive: an archive ships headers and a built library, not an SDK,
  and the Visual C++ redistribution terms cover the runtime DLLs for app-local
  deployment, not the toolset's import libraries. A consumer would therefore have
  to supply an MSVC and Windows SDK installation, which breaks the property every
  other target has -- copy the archive, link, run, no system prerequisite;
* GNU ld only half understands the objects it was given: the link emits a stream of
  `Warning: corrupt .drectve at end of def file`, one per object carrying MSVC
  linker directives. It works, by tolerating what it does not parse;
* the executable produced in attempt 1 was deliberately not run, so runtime
  behaviour with a mixed MSVC/MinGW CRT is unmeasured. Attempt 2, which added the
  static CRT libraries, failed outright
  (`libcmt.lib: error adding symbols: file format not recognized`), so the one
  configuration that could have made the runtime self-contained is not reachable
  either;
* the design's own success criterion is that a `mingwX64` consumer needs no system
  prerequisite beyond Windows itself.

Verdict for the static linkage: **not shipped**, and `linkages` stays `["shared"]`.
This is a decision on the archive's contract rather than on the link, and it is
reversible: the command above is the whole of what a future static archive would
require its consumers to reproduce.

## Verdict

`feasible`, for the `d3d12` + `null` entry the matrix declares. Unlike the MinGW
route, nothing needs patching: Dawn builds under MSVC as it is, and the C API
boundary makes the MSVC-built DLL usable from a GNU-ABI consumer. The consumer
triple stays `x86_64-pc-windows-gnu`.

The route is:

* a `windows-2022` runner, MSVC entered through `vcvars64.bat`, CMake with Ninja
  and no toolchain file (host == target, so `protoc` builds natively and the
  matrix entry's `toolchain` becomes empty);
* `DAWN_BUILD_MONOLITHIC_LIBRARY=SHARED` yielding `bin/webgpu_dawn.dll` and
  `lib/webgpu_dawn.lib`. The static linkage is deliberately not shipped: it links
  from MinGW, but only with MSVC and Windows SDK import libraries that no archive
  can carry (section 7);
* export control left to `__declspec(dllexport)`: 387 exported symbols, none
  outside `wgpu*`/`dawn*`.

Constraints accepted or to be decided:

* the archives also carry D3D11 and Vulkan, because Dawn forces the Win32
  defaults on; this is accepted;
* the DLL needs the VC++ runtime DLLs. Either document the requirement or deploy
  them app-local next to `webgpu_dawn.dll`, which the redistributable licence
  allows.

## What the pipeline needs before this can ship

* `CMakeLists.txt`: guard the ELF version script with `WIN32`. MSVC ignores the
  option silently today, but a GNU linker on Windows would try to honour it.
* `scripts/package.sh`: stage `bin/` as well as `include/` and `lib/`, otherwise
  the DLL is dropped **silently** (reproduced).
* `packaging/make-manifest.py`: cover `bin/*.dll`. The manifest claims an
  inventory exhaustive over what `package.sh` stages, and today it would miss the
  DLL without failing.
* `scripts/build-target.sh`: the Windows path needs no toolchain file, and its
  compiler setup comes from the MSVC environment rather than from the script.
* `.github/workflows/build.yml`: derive a Windows host target; today the
  `uname -s`-based derivation errors out on anything but Darwin/Linux.
* `scripts/run-smoke-test.sh`: a Windows branch linking with MinGW gcc, the MSVC
  import library, and the DLL beside the executable.
* `packaging/validate-matrix.py` and `scripts/build-target.sh`: `d3d11` is missing
  from the backend vocabulary, which the honest Windows backend list needs.
* `targets/matrix.json`: move `mingwX64` from `dropped` to `v1` with an empty
  `toolchain` and the real backend set.
* `cmake/toolchains/mingw-x64.cmake`: becomes the record of the abandoned GNU
  route.

# Spike: MinGW x64 (`x86_64-pc-windows-gnu`)

**Verdict: `infeasible`** (for the target's `d3d12` + `null` backend set).

Kotlin/Native's Windows target is MinGW-based, but Dawn's D3D12 backend depends
on Windows-SDK-only headers and MinGW-hostile include assumptions. A **null-only**
library does build, so the failure is specifically the D3D12 backend, not the
whole of Dawn.

## Environment

| Item | Value |
| --- | --- |
| Host | macOS 26.6.2 (25G83), Apple Silicon (arm64) |
| C/C++ compiler | Homebrew LLVM clang 23.1.2 (`/opt/homebrew/opt/llvm/bin/clang++`) |
| MinGW-w64 | Homebrew `mingw-w64` 14.0.0_3 (bundled GCC 16.2.0) |
| MinGW sysroot | `/opt/homebrew/opt/mingw-w64/toolchain-x86_64` |
| MinGW linker | `/opt/homebrew/opt/mingw-w64/bin/x86_64-w64-mingw32-ld` (GNU ld, **lld is not used**) |
| CMake / Ninja | 4.4.3 / 1.13.2 |
| Host `protoc` | Homebrew protobuf 36.2 (Dawn pins runtime 36.0 → **incompatible**) |
| Disk (`/Volumes/Cache`) | 11.22 GiB free before, 11.05 GiB at peak (build trees), 11.21 GiB after cleanup |

The toolchain file is `cmake/toolchains/mingw-x64.cmake`. The stock content from
the brief (`clang`/`clang++` + triple only) is not enough on macOS: the host
`/usr/bin/clang` uses Apple's `ld`, which cannot link PE/GNU objects. The
committed file:

* prefers a full LLVM clang (`MINGW_CLANG_DIR`, default `/opt/homebrew/opt/llvm/bin`),
* points at the MinGW-w64 sysroot (`MINGW_SYSROOT`, auto-detected),
* passes `--ld-path` to MinGW's GNU `ld` (`MINGW_LD`, auto-detected),
* sets `CMAKE_RC_COMPILER` to `x86_64-w64-mingw32-windres`,
* restricts `find_*` to the sysroot.

All inputs are overridable with `-D`/environment variables, so the file is not
tied to this machine.

## Commands and results

### 1. Configure only, d3d12 + null (via the wrapper)

```bash
bash scripts/build-target.sh mingwX64 static
```

Result: **failure at configure**, before any compilation. First blocking error:

```
CMake Error at dawn/third_party/protobuf.cmake:190 (message):
  When cross-compiling, you must specify a host protoc via
  -DPROTOC_EXECUTABLE=...  or provide a CMAKE_CROSSCOMPILING_EMULATOR.
Call Stack (most recent call first):
  dawn/third_party/CMakeLists.txt:84 (include)
```

This is a **cross-compilation harness** issue, not a MinGW issue: Dawn always
builds `protobuf` (default `DAWN_BUILD_PROTOBUF=ON`) and, when
`CMAKE_CROSSCOMPILING` is true, insists on a host `protoc`. On a real
Windows/MinGW build (host == target) Dawn would build `protoc` natively. The
Homebrew `protoc` 36.2 cannot be used because the pinned runtime is 36.0 and the
generated code fails the runtime version check.

Note: the wrapper passes `-DDAWN_ENABLE_D3D12=ON -DDAWN_ENABLE_NULL=ON`, but
`dawn/CMakeLists.txt:96-104` forces `ENABLE_D3D11`, `ENABLE_D3D12`,
`ENABLE_VULKAN` and `USE_WINDOWS_UI` ON whenever `WIN32` is set. The resulting
configure still reported `D3D11: ON, D3D12: ON, Vulkan: ON`. So the matrix's
backend list does **not** restrict the Windows build without explicitly passing
`-DDAWN_ENABLE_D3D11=OFF -DDAWN_ENABLE_VULKAN=OFF`.

### 2. Null-only configure + build

The exact command from the controller (no compile):

```bash
cmake -S . -B build/mingwX64/null-only -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DDAWN_PACKER_LINKAGE=STATIC \
  -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/mingw-x64.cmake \
  -DDAWN_ENABLE_NULL=ON -DDAWN_ENABLE_D3D12=OFF -DDAWN_ENABLE_VULKAN=OFF
```

Result: **fails at the same `protobuf.cmake:190` error** — confirming the
blocker is backend-independent.

Adjusted configuration used to reach compilation (adds Win32 default overrides
and disables protobuf, which is unrelated to the backend question):

```bash
cmake -S . -B build/mingwX64/null-only -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DDAWN_PACKER_LINKAGE=STATIC \
  -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/mingw-x64.cmake \
  -DDAWN_ENABLE_NULL=ON -DDAWN_ENABLE_D3D12=OFF -DDAWN_ENABLE_D3D11=OFF \
  -DDAWN_ENABLE_VULKAN=OFF -DDAWN_USE_WINDOWS_UI=OFF \
  -DDAWN_BUILD_PROTOBUF=OFF -DTINT_BUILD_IR_BINARY=OFF
cmake --build build/mingwX64/null-only --target dawn_packer
```

Result: **BUILD SUCCEEDED** (exit 0, 694 steps). Produced
`build/mingwX64/null-only/dawn/src/dawn/native/libwebgpu_dawn.a` (20 MB) whose
members are `pe-x86-64` objects — a valid MinGW/GNU-ABI static library.
Conclusion: the portability core of Dawn (Abseil, Tint, dawn_native, null
backend) compiles and archives cleanly under MinGW-w64.

### 3. d3d12 + null configure + build

```bash
cmake -S . -B build/mingwX64/d3d12 -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DDAWN_PACKER_LINKAGE=STATIC \
  -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/mingw-x64.cmake \
  -DDAWN_ENABLE_NULL=ON -DDAWN_ENABLE_D3D12=ON -DDAWN_ENABLE_D3D11=OFF \
  -DDAWN_ENABLE_VULKAN=OFF -DDAWN_USE_WINDOWS_UI=OFF \
  -DDAWN_BUILD_PROTOBUF=OFF -DTINT_BUILD_IR_BINARY=OFF
cmake --build build/mingwX64/d3d12 --target dawn_packer
```

Configure succeeds; the build **fails** at the first D3D12 translation unit:

```
FAILED: .../dawn_native_objects.dir/Instance.cpp.obj
In file included from .../src/dawn/native/Instance.cpp:59:
In file included from .../src/dawn/native/d3d/BackendD3D.h:37:
In file included from .../src/dawn/native/d3d12/d3d12_platform.h:32:
.../src/dawn/native/d3d/d3d_platform.h:44:10: fatal error: 'DXProgrammableCapture.h' file not found
   44 | #include <DXProgrammableCapture.h>
      |          ^~~~~~~~~~~~~~~~~~~~~~~~~
1 error generated.
```

**Blocker A — `dawn/src/dawn/native/d3d/d3d_platform.h:44`.** `DXProgrammableCapture.h`
is a Windows SDK "Graphics Tools / Graphics Diagnostics" header. MinGW-w64 does
not ship it (`find` returns 0 copies), and the `#include` is unconditional and
unguarded. Dawn does not call any API from it (grep finds only the include and
its comment), so the dependency is gratuitous, but removing it means patching
`dawn/`, which this spike is not allowed to do.

**Blocker B — `dawn/src/dawn/native/d3d/D3DError.h:38`.** After stubbing out
`DXProgrammableCapture.h` (in a temporary `-I` overlay, without touching
`dawn/`), the next failure is:

```
.../src/dawn/native/d3d/D3DError.h:38:29: error: unknown type name 'HRESULT'
.../src/dawn/native/d3d/D3DError.h:40:11: error: unknown type name 'HRESULT'
```

`D3DError.h` includes only `<winerror.h>` and uses `HRESULT`. Under MinGW-w64,
`<winerror.h>` does not pull in `<winnt.h>`/`<windows.h>`, so `HRESULT` is
undefined. Verified standalone:

```
$ printf '#include <winerror.h>\nHRESULT f(void);\n' > hr1.cpp
$ clang++ --target=x86_64-w64-mingw32 --sysroot=... -std=c++20 -c hr1.cpp
hr1.cpp:2:1: error: unknown type name 'HRESULT'
$ printf '#include <windows.h>\n#include <winerror.h>\nHRESULT f(void);\n' > hr2.cpp
$ clang++ --target=x86_64-w64-mingw32 --sysroot=... -std=c++20 -c hr2.cpp
# compiles
```

**Further (not reached) blockers.** Even if A and B were patched, the D3D12 link
step uses MSVC-style library names that GNU ld cannot resolve —
`dawn/src/dawn/native/CMakeLists.txt:310-311` (`user32.lib`,
`onecore_apiset.lib`; also `dxguid.lib` at :363) — and
`dawn/src/dawn/native/CMakeLists.txt:1097-1099` invokes
`AddCopyWindowsSDKDLLTarget` (`dawn/third_party/CopyWindowsSDKDLL.cmake:47`)
which reads the Windows SDK location from the registry and copies
`d3dcompiler_47.dll` from `$WIN10_SDK_PATH/bin/<ver>/x64/`. MSVC/MinGW has no
such SDK.

## Verdict

`infeasible`.

Dawn's **D3D12** backend cannot be built with MinGW-w64 on this host because it
unconditionally includes the Windows-SDK-only `DXProgrammableCapture.h`
(`d3d_platform.h:44`) and assumes MSVC/Windows-SDK include and link conventions
(`HRESULT` from `<winerror.h>`, `*.lib` link inputs, Windows SDK DLL copy). The
**null** backend alone does build, but the matrix entry for `mingwX64` requires
`d3d12` + `null`; a null-only Windows library has no GPU backend and is not
useful, so `mingwX64` is dropped.

## Fallback plan (chosen)

Build Dawn for Windows with **MSVC** (real `windows-2022` runner, no
cross-compilation and no MinGW), produce a `webgpu_dawn.dll` plus its import
library (`webgpu_dawn.lib`), and consume the import library from Kotlin/Native's
`mingwX64` target via cinterop/`linkerOpts`. This avoids the GNU-vs-MSVC C++
ABI and Windows-SDK-header problems entirely. `mingwX64` builds Dawn from source
only if someone later ports the D3D12 backend to MinGW; the `dropped` status
records the current decision.

Alternatively, drop `mingwX64` entirely if the MSVC-DLL shim is out of scope.

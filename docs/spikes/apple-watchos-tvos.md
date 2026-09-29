# Spike: Apple tvOS and watchOS

**Verdicts:** `tvosArm64` = **`faisable`**, `tvosSimulatorArm64` = **`faisable`**,
`watchosSimulatorArm64` = **`infeasible`**, `watchosDeviceArm64` = **`infeasible`**,
`watchosArm64` = **`infeasible`** (twice over: platform frameworks *and* ILP32).

Dawn's Metal + null backends cross-compile and archive cleanly for **tvOS**
(device arm64 and simulator arm64), verified end-to-end with `cmake --build` and
`cmake --install` against the Xcode 26.5 tvOS SDKs.

**watchOS is not a viable Dawn target.** watchOS is the only Apple platform whose
SDK ships neither `Metal.framework` nor `IOSurface.framework`, and Dawn requires
both unconditionally for `APPLE`: `dawn/src/dawn/common/CMakeLists.txt:127`
adds `IOSurfaceUtils.cpp` (+ `-framework IOSurface`) for every Apple platform,
and Tint's MSL-validation target calls
`find_library(MetalFramework Metal REQUIRED)`
(`dawn/src/tint/CMakeLists.txt:571`). Beyond the missing frameworks,
the 32-bit-pointer watchOS ABI (`arm64_32`, ILP32, `watchosArm64`) is
**independently rejected by Dawn's own source**: `dawn/src/utils/platform.h:189`
hard-asserts `sizeof(size_t) == 8`, which is always false for ILP32. This is not
a CMake or toolchain artifact; Dawn has no ILP32 code path.

## Environment

| Item | Value |
| --- | --- |
| Host | macOS 26.6.2 (25G83), Apple Silicon (arm64) |
| Xcode | 26.6 (17F113), `/Applications/Xcode.app` |
| SDKs | tvOS 26.5 (`appletvos` / `appletvsimulator`), watchOS 26.5 (`watchos` / `watchsimulator`) |
| Compiler | Apple clang 21.0.0.21000101 (host `/usr/bin/cc` selected by CMake's platform modules) |
| CMake / Ninja | 4.4.3 / 1.13.2 |
| Host `protoc` | built from Dawn's pinned protobuf → `protoc-36.0.0` (see harness note) |
| Disk (`/Volumes/Cache`) | 11 GiB free before, 11 GiB after (build trees are reference-linked, ~75 MB each) |

CMake's `Platform/tvOS.cmake` and `Platform/watchOS.cmake` are present in CMake
4.4.3, so `CMAKE_SYSTEM_NAME tvOS` / `watchOS` is a supported cross platform.

## Toolchain files

All five were created and all are referenced by `targets/matrix.json` exactly
where the matrix already pointed (Ruling P3: two watchOS device toolchains).

`cmake/toolchains/apple-tvos.cmake` (device arm64):

```cmake
set(CMAKE_SYSTEM_NAME tvOS)
set(CMAKE_OSX_SYSROOT appletvos)
set(CMAKE_OSX_DEPLOYMENT_TARGET 15.0)
set(CMAKE_OSX_ARCHITECTURES arm64)
```

`cmake/toolchains/apple-tvos-simulator.cmake` (simulator arm64): same as above
with `CMAKE_OSX_SYSROOT appletvsimulator`.

`cmake/toolchains/apple-watchos.cmake` (device `arm64_32`, ILP32):

```cmake
set(CMAKE_SYSTEM_NAME watchOS)
set(CMAKE_OSX_SYSROOT watchos)
set(CMAKE_OSX_DEPLOYMENT_TARGET 8.0)
set(CMAKE_OSX_ARCHITECTURES arm64_32)
```

`cmake/toolchains/apple-watchos-device.cmake` (device arm64): `watchos` sysroot,
`CMAKE_OSX_ARCHITECTURES arm64`.
`cmake/toolchains/apple-watchos-simulator.cmake` (simulator arm64):
`watchsimulator` sysroot, `CMAKE_OSX_ARCHITECTURES arm64`.

The Xcode 26.5 SDKs accepted the brief's deployment floors unchanged (tvOS 15.0,
watchOS 8.0); no floor was raised. tvOS objects carry `minos 15.0` and
`-mwatchos-version-min=8.0` was accepted at configure for watchOS.

## Harness note: host `protoc` (applies to all five)

The matrix backends for these targets are `metal` + `null`, and the wrapper
(`scripts/build-target.sh`) invokes them as written. Every one of the five
wrapper runs stops at the **same** configure gate, before any platform-specific
work:

```
CMake Error at dawn/third_party/protobuf.cmake:190 (message):
  When cross-compiling, you must specify a host protoc via
  -DPROTOC_EXECUTABLE=...  or provide a CMAKE_CROSSCOMPILING_EMULATOR.
Call Stack (most recent call first):
  dawn/third_party/CMakeLists.txt:84 (include)
```

This is the documented cross-compilation contract (Dawn's own CI builds a host
`protoc` first and passes `-DPROTOC_EXECUTABLE`; see
`dawn/.github/workflows/ci.yml:316-351`), not a tvOS/watchOS defect. It is
identical to the MinGW x64 spike and would affect the existing cross-compiled
iOS entries too.

**Follow-up (out of scope here):** `scripts/build-target.sh` does not yet build
or pass a host `protoc`, so the `tvosArm64`/`tvosSimulatorArm64` (and `ios*`)
matrix entries cannot actually be built by the current wrapper/CI. The fix is
the Dawn-CI pattern: build `out/host/protoc` once, then pass
`-DPROTOC_EXECUTABLE`. This spike proves tvOS is otherwise buildable; wiring
the host protoc into the harness is a separate task.

To reach the actual per-platform work, the spike built a host
`protoc` from Dawn's pinned protobuf (36.0, matching the 36.0 runtime) and
re-ran each target with `-DPROTOC_EXECUTABLE=$PWD/build/host-protoc/protoc` and
otherwise identical flags (`static`, `metal`+`null`).

## Per-target results

`file` and `otool -l` were run on an extracted archive member; `platform`
numbers are Mach-O `LC_BUILD_VERSION`: 3 = tvOS, 8 = tvOS Simulator.

| Target | Toolchain | Command (after host protoc) | Result | First blocking error (truncated) | Verdict |
| --- | --- | --- | --- | --- | --- |
| `tvosArm64` | `apple-tvos.cmake` | `cmake … -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/apple-tvos.cmake -DPROTOC_EXECUTABLE=… ; cmake --build … --target dawn_packer ; cmake --install …` | **success** (755 steps; `libwebgpu_dawn.a`, 21,085,328 B; arm64, platform 3, minos 15.0) | — | `faisable` |
| `tvosSimulatorArm64` | `apple-tvos-simulator.cmake` | same, tvOS-simulator toolchain | **success** (installed `libwebgpu_dawn.a`, 21,143,272 B; arm64, platform 8, minos 15.0) | — | `faisable` |
| `watchosSimulatorArm64` | `apple-watchos-simulator.cmake` | same, watch-simulator toolchain | **failure at configure** | `CMake Error at dawn/src/tint/CMakeLists.txt:571 (find_library): Could not find MetalFramework using the following names: Metal` | `infeasible` |
| `watchosDeviceArm64` | `apple-watchos-device.cmake` | same, watch-device (arm64) toolchain | **failure at configure** | same `find_library(MetalFramework)` error | `infeasible` |
| `watchosArm64` | `apple-watchos.cmake` | same, watch-device (`arm64_32`) toolchain | **failure at configure** | same `find_library(MetalFramework)` error (ILP32 blocker found in the null-only probe below) | `infeasible` |

All five also fail the unmodified `scripts/build-target.sh <target> static`
wrapper command at the `protobuf.cmake:190` host-protoc gate above.

The three watchOS SDKs contain `Foundation`, `CoreFoundation`, `CoreGraphics`
and `QuartzCore`, but **no `Metal.framework` and no `IOSurface.framework`** —
unlike tvOS/iOS/macOS. `find_library(... REQUIRED)` therefore aborts configure.

## Supplementary probes: why watchOS fails

Because the missing Metal framework aborts configure before compilation, two
out-of-matrix **null-only** probes were run (same toolchains,
`-DDAWN_ENABLE_METAL=OFF -DDAWN_ENABLE_NULL=ON`) to separate the platform
frameworks from the ABI. These are diagnostic only; the matrix backend set for
watchOS remains `metal`+`null`.

### `watchosDeviceArm64` (arm64), null-only

Dawn core, Tint and Abseil compile for watchOS arm64 until the first
`dawn_common` translation unit that needs IOSurface:

```
FAILED: dawn/src/dawn/common/CMakeFiles/dawn_common.dir/IOSurfaceUtils.cpp.o
/Volumes/Cache/dawn-packer-wt/dawn/src/dawn/common/IOSurfaceUtils.h:31:10: fatal error: 'IOSurface/IOSurfaceRef.h' file not found
```

`dawn/src/dawn/common/CMakeLists.txt:127-138` adds `IOSurfaceUtils.cpp` and
`-framework IOSurface` for **all** `APPLE` platforms, with no watchOS exclusion.
watchOS ships no IOSurface, so this cannot work without patching Dawn.

### `watchosArm64` (`arm64_32`, ILP32), null-only — decisive for the ILP32 question

Even with Metal and IOSurface out of the picture, the very first Dawn
translation unit fails:

```
FAILED: dawn/src/dawn/utils/CMakeFiles/dawn_shared_utils.dir/assert.cc.o
/Volumes/Cache/dawn-packer-wt/dawn/src/utils/platform.h:189:15: error: static assertion failed due to requirement 'sizeof (sizeof(char)) == 8': Expect sizeof(size_t) == 8
   189 | static_assert(sizeof(sizeof(char)) == 8, "Expect sizeof(size_t) == 8");
       |               ^~~~~~~~~~~~~~~~~~~~~~~~~
note: expression evaluates to '4 == 8'
```

So **yes — `watchosArm64` (`arm64_32`, ILP32) fails**, and it fails
independently of Metal/IOSurface: Dawn's `platform.h` selects the 64-bit branch
for `DAWN_PLATFORM_IS_ARM64` and then statically asserts 8-byte `size_t`. ILP32
`arm64_32` is not a supported Dawn ABI.

## Verdict

- **tvOS (`tvosArm64`, `tvosSimulatorArm64`) — `faisable`.** Metal + null build,
  archive and install with unchanged toolchains and the brief's deployment
  floors. The only wrapper-level obstacle is the generic cross-compile host
  `protoc` requirement, which any iOS/tvOS CI job must satisfy anyway (Dawn CI
  does). Matrix status stays `v1`.
- **watchOS (`watchosArm64`, `watchosDeviceArm64`, `watchosSimulatorArm64`) —
  `infeasible`.** Three independent blockers, any one of which is fatal:
  1. `watchos`/`watchsimulator` SDKs ship no `Metal.framework`
     (`dawn/src/tint/CMakeLists.txt:571`, configure-time `REQUIRED`);
  2. they ship no `IOSurface.framework`
     (`dawn/src/dawn/common/IOSurfaceUtils.h:31`, compile-time, all `APPLE`);
  3. ILP32 `arm64_32` is rejected by `dawn/src/utils/platform.h:189`
     (`sizeof(size_t) == 8` static assertion, arm64-only for `watchosArm64`).
  This is specific to the Dawn pin (`chromium/8077`) and to the current Xcode
  26.5 watchOS SDKs; re-spike if upstream ever guards IOSurface/Metal by
  sub-platform and gains an ILP32 path.

Matrix changes: `watchosArm64`, `watchosDeviceArm64`, `watchosSimulatorArm64`
`spike` → `dropped`; `tvosArm64`/`tvosSimulatorArm64` unchanged (`v1`).
`python3 packaging/validate-matrix.py targets/matrix.json` prints `matrix OK`.

## Disk

| Point | Free on `/Volumes/Cache` |
| --- | --- |
| Before | 11 GiB |
| Peak (build + host protoc trees) | 11 GiB |
| After cleanup of `build/*` and failed `dist/watchos*` | 11 GiB |

Build trees were reference-linked (no dependency copies): each target tree was
~75 MB, and the host-protoc tree was removed after the runs. `dist/tvosArm64`
and `dist/tvosSimulatorArm64` are retained (successful install trees) and were
never below the 3 GiB floor. The null-only probe trees and the host-protoc tree
were removed after use.

## Files changed

- `cmake/toolchains/apple-tvos.cmake` (new)
- `cmake/toolchains/apple-tvos-simulator.cmake` (new)
- `cmake/toolchains/apple-watchos.cmake` (new, `arm64_32`)
- `cmake/toolchains/apple-watchos-device.cmake` (new, `arm64`; Ruling P3)
- `cmake/toolchains/apple-watchos-simulator.cmake` (new)
- `docs/spikes/apple-watchos-tvos.md` (new, this file)
- `targets/matrix.json` — three watchOS entries `spike` → `dropped`
- `dawn/` and existing scripts untouched.

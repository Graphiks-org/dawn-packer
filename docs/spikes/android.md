# Spike: Android (`androidNativeArm64`, `androidNativeArm32`, `androidNativeX64`, `androidNativeX86`)

**Verdict: `feasible`** for all four ABIs. `bash scripts/build-target.sh <target> static`
configures and builds Dawn's Vulkan + OpenGL ES + null backends against NDK
**27.3.13750724** and installs a valid Android static archive for each ABI. There is
no build-side blocker.

There is one **consumer-side constraint** (see "Consumer constraint" below): the
pinned NDK must also be the source of the app's `libc++_shared.so`, because
Kotlin/Native 2.4.20's bundled C++ runtime predates symbols that Dawn built with
NDK 27 references.

## Environment

| Item | Value |
| --- | --- |
| Host | macOS 26.6.2, Apple Silicon (arm64); NDK prebuilt is a universal `darwin-x86_64` binary |
| CMake / Ninja | 4.4.3 / 1.13.2 |
| NDK pinned and used | **27.3.13750724** (`Pkg.Revision = 27.3.13750724`), clang 18.0.4 (r522817d) |
| `ANDROID_NDK_HOME` at start | `/Users/chaos/Library/Android/sdk/ndk/27.0.12077973` — **this directory does not exist** |
| NDK versions actually installed | 27.3.13750724, 28.2.13676358, 29.0.14206865, 30.0.15729638-beta2 |
| API level / STL | `android-26`, `c++_static` |
| Disk (`/Volumes/Cache`) | 11 GiB free before, 9.9 GiB at peak, 10 GiB after cleanup |

`ANDROID_NDK_HOME` pointed at a revision that is not installed, so every build in
this spike exported the pinned path explicitly:

```bash
export ANDROID_NDK_HOME=/Users/chaos/Library/Android/sdk/ndk/27.3.13750724
```

The toolchain file falls back to `$ANDROID_HOME/ndk/27.3.13750724` when
`ANDROID_NDK_HOME` is unset, so the default `ANDROID_HOME` on this machine also
resolves once the stale `ANDROID_NDK_HOME` is cleared.

## Toolchain file

`cmake/toolchains/android.cmake` (created by this task):

```cmake
set(CMAKE_SYSTEM_NAME Android)
set(CMAKE_SYSTEM_VERSION 26)
set(CMAKE_ANDROID_API 26)
# CMAKE_ANDROID_NDK from $ENV{ANDROID_NDK_HOME}, falling back to
# $ANDROID_HOME/ndk/27.3.13750724, then FATAL_ERROR.
set(CMAKE_ANDROID_STL_TYPE c++_static)
```

It deliberately does **not** set an ABI. Ruling P14: one toolchain file cannot
serve four ABIs, so `scripts/build-target.sh` forwards the matrix entry's new
`androidAbi` field as `-DCMAKE_ANDROID_ARCH_ABI`. The file relies on CMake's
built-in Android/NDK support and the NDK's own hooks rather than re-deriving
compiler paths.

Two corrections to the brief's snippet, both applied and required:

* The STL variable is **`CMAKE_ANDROID_STL_TYPE`** (CMake's built-in Android
  support). The brief's `CMAKE_ANDROID_STL` is the NDK toolchain-file spelling
  and is a silent no-op here.
* `CMAKE_SYSTEM_VERSION` and `CMAKE_ANDROID_API` must agree; both are `26`.

`android-26` matches Dawn's own upstream CI
(`dawn/.github/workflows/ci.yml`: `-DANDROID_PLATFORM=android-26`) and is present
in Kotlin/Native's bundled sysroot (see below).

## Kotlin/Native 2.4.20 and the NDK

Kotlin/Native 2.4.20 does **not** consume `ANDROID_NDK_HOME`. Its
`konan.properties` for every Android target points at the bundled artifacts
`target-toolchain-2-*-android_ndk` and `target-sysroot-1-android_ndk`. On this
machine those are already materialized in `~/.konan/dependencies/`:

| Kotlin/Native bundled artifact | Value |
| --- | --- |
| Android compiler | clang **8.0.7**, "based on r346389c" (NDK **r19c** era) |
| Android sysroot | API levels 16–29 (`android-26` present, with `libvulkan.so`) |
| Link flags (`linkerKonanFlags.android_*`) | `-lm -lc++_static -lc++abi -landroid -llog -latomic` |
| C++ ABI namespace | `std::__ndk1` (same inline namespace as NDK 27) |

So the NDK Kotlin/Native 2.4.20 effectively compiles/links with is the
**r19c-era toolchain it bundles itself**; the local NDK is only relevant to the
Dawn build. This spike pins the build NDK to **27.3.13750724** and records the
compatibility consequence below.

### Consumer constraint (explicit)

The Dawn archive is compiled with **NDK 27.3.13750724**. Kotlin/Native's bundled
`libc++_static.a` is r19c-era and does **not** define several C++ runtime symbols
that Dawn references. Verified against `libwebgpu_dawn.a` (arm64):

| Symbol (mangled, `std::__ndk1`) | Kotlin bundled `libc++_static.a` | NDK 27 `libc++_shared.so` |
| --- | --- | --- |
| `__libcpp_verbose_abort(char const*, ...)` | missing | present |
| `__libcpp_atomic_wait(void const volatile*, int)` | missing | present |
| `__cxx_atomic_notify_all(void const volatile*)` | missing | present |
| `__libcpp_atomic_monitor(void const volatile*)` | missing | present |
| `basic_filebuf<...>::basic_filebuf()` / `~basic_filebuf()` / `open(char const*, unsigned)` | missing | present |
| `basic_stringbuf<...>::operator=(basic_stringbuf&&)` | missing | present |
| `__fs::filesystem::path::__filename() const` | missing | present |

Because a shared library may carry undefined symbols, a Kotlin/Native
`android_arm64` link of the archive **succeeds**, but those symbols stay
undefined against Kotlin's bundled libc++. They must be resolved at runtime by a
`libc++_shared.so` that contains them. NDK 27's `libc++_shared.so` does, and it
uses the same SONAME (`libc++_shared.so`) as Kotlin's r19c copy — so the two are
interchangeable by name and it is easy to pick the wrong one. A Kotlin/Native
link that adds NDK 27's `libc++_shared.so` records the dependency correctly
(`NEEDED libc++_shared.so`).

**Rule for consumers: build Dawn with NDK 27.3.13750724 *and* ship the same
NDK's `libc++_shared.so` with the app.** Do not rely on the `libc++` bundled in
the Kotlin/Native toolchain; with it, Dawn's `.so` fails to load with unresolved
`std::__ndk1` symbols. A full end-to-end KMP consumer link/run is still the
authoritative check and was not part of this spike.

## Commands and results

All four ran through the wrapper with the pinned NDK exported:

```bash
export ANDROID_NDK_HOME=/Users/chaos/Library/Android/sdk/ndk/27.3.13750724
bash scripts/build-target.sh androidNativeArm64 static
bash scripts/build-target.sh androidNativeX64 static
bash scripts/build-target.sh androidNativeArm32 static
bash scripts/build-target.sh androidNativeX86 static
```

| Target | ABI | Configure line (abridged) | Exit | Installed archive | Member ELF |
| --- | --- | --- | --- | --- | --- |
| `androidNativeArm64` | `arm64-v8a` | `Targeting API '26' ... ABI 'arm64-v8a' ... 'aarch64'` | 0 | 58 322 800 B | `ELF 64-bit ARM aarch64` |
| `androidNativeX64` | `x86_64` | `Targeting API '26' ... ABI 'x86_64' ... 'x86_64'` | 0 | 58 095 702 B | `ELF 64-bit x86-64` |
| `androidNativeArm32` | `armeabi-v7a` | `Targeting API '26' ... ABI 'armeabi-v7a' ... 'armv7-a'` | 0 | 57 204 316 B | `ELF 32-bit ARM EABI5` |
| `androidNativeX86` | `x86` | `Targeting API '26' ... ABI 'x86' ... 'i686'` | 0 | 49 208 046 B | `ELF 32-bit Intel 80386` |

All four configured with the NDK's unified Clang toolchain and produced
`dist/<target>/static/install/lib/libwebgpu_dawn.a` plus the Dawn CMake package
and headers. **No ABI failed**, so there is no first-error transcript to record
and no matrix status was dropped.

The only build diagnostic worth noting is a benign one from the bundled
protobuf, present on every Android configure:

```
CMake Warning (deprecated) at third_party/protobuf/CMakeLists.txt:7 (cmake_policy):
  The OLD behavior for policy CMP0141 will be removed from a future version of CMake.
```

Dawn's protobuf gate was not hit: `build-target.sh` supplies the host `protoc`
(Task 9b), and the first cross build spent ~100 s rebuilding it before the arm64
build.

Dry run stays side-effect free and now shows the forwarded ABI:

```
cmake -S ... -B .../build/androidNativeArm64/static -G Ninja ... \
  -DCMAKE_ANDROID_ARCH_ABI=arm64-v8a \
  -DCMAKE_TOOLCHAIN_FILE=.../cmake/toolchains/android.cmake \
  -DPROTOC_EXECUTABLE=.../build/host-protoc/bin/protoc ...
```

`python3 packaging/validate-matrix.py targets/matrix.json` prints `matrix OK`.

## Matrix changes

* Added `"androidAbi"` to each `androidNative*` entry:
  `androidNativeArm64` → `arm64-v8a`, `androidNativeArm32` → `armeabi-v7a`,
  `androidNativeX64` → `x86_64`, `androidNativeX86` → `x86`.
* `scripts/build-target.sh` reads `androidAbi` (defaulting to `""`) and appends
  `-DCMAKE_ANDROID_ARCH_ABI=<value>` only when non-empty.
* No status changed to `dropped`: all four ABIs are buildable and remain `v1`.

## Disk

| Point | Free |
| --- | --- |
| Before | 11 GiB |
| Peak (four Android trees + host `protoc`) | 9.9 GiB |
| After `rm -rf build/androidNative{Arm64,Arm32,X64,X86}` | 10 GiB |

`dist/` was kept for all four successful targets; the disposable build trees were
removed.

## Caveats / re-spike conditions

* The **consumer constraint above is the main risk**. The build-side verdict is
  clean, but ship-readiness depends on the consuming app linking the pinned NDK's
  `libc++_shared.so`. If a future Kotlin/Native release updates its bundled
  Android toolchain (or if the consumer link is validated against the pinned
  NDK), this note can be retired.
* `ANDROID_NDK_HOME` is misconfigured on this machine (points at an uninstalled
  revision). Builds here override it explicitly; CI must set it to
  `27.3.13750724`.
* All four ABIs were validated at the **build** level only. A Kotlin/Native
  cinterop link/run smoke test is the next step to confirm the runtime constraint
  in practice.

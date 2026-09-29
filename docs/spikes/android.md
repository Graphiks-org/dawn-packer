# Spike: Android (`androidNativeArm64`, `androidNativeArm32`, `androidNativeX64`, `androidNativeX86`)

**Verdict: `feasible` at the build level** for all four ABIs.
`bash scripts/build-target.sh <target> static` configures and builds Dawn's
Vulkan + OpenGL ES + null backends against NDK **27.3.13750724** and installs a
valid Android static archive for each ABI. There is no build-side blocker.

**Consumability is not established.** There is an **unresolved consumer-side
risk** (see "Open risk: consumer C++ runtime" below): Dawn built with NDK 27
references C++ runtime symbols that are absent from the r19c-era libc++ that
Kotlin/Native 2.4.20 bundles and *always* links. The matrix entries below stay
`v1` on build-side evidence only; an end-to-end Kotlin/Native link + on-device
run has **not** been performed.

## Environment

| Item | Value |
| --- | --- |
| Host | macOS 26.6.2, Apple Silicon (arm64); NDK prebuilt is a universal `darwin-x86_64` binary |
| CMake / Ninja | 4.4.3 / 1.13.2 |
| NDK pinned and used | **27.3.13750724** (`Pkg.Revision = 27.3.13750724`), clang 18.0.4 (r522817d) |
| `ANDROID_NDK_HOME` at start | `/Users/chaos/Library/Android/sdk/ndk/27.0.12077973` -- **this directory does not exist** |
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

`cmake/toolchains/android.cmake`:

```cmake
set(CMAKE_SYSTEM_NAME Android)
set(CMAKE_SYSTEM_VERSION 26)
set(CMAKE_ANDROID_API 26)
# CMAKE_ANDROID_NDK from $ENV{ANDROID_NDK_HOME}, falling back to
# $ANDROID_HOME/ndk/27.3.13750724, then FATAL_ERROR.
set(CMAKE_ANDROID_STL_TYPE c++_static)
```

It deliberately does **not** set an ABI. One toolchain file cannot serve four
ABIs, so `scripts/build-target.sh` forwards the matrix entry's new
`androidAbi` field as `-DCMAKE_ANDROID_ARCH_ABI`. The file relies on CMake's
built-in Android/NDK support and the NDK's own hooks rather than re-deriving
compiler paths.

Two corrections to the first draft, both applied and required:

* The STL variable is **`CMAKE_ANDROID_STL_TYPE`** (CMake's built-in Android
  support). The older `CMAKE_ANDROID_STL` is the NDK toolchain-file spelling
  and is a silent no-op here.
* `CMAKE_SYSTEM_VERSION` and `CMAKE_ANDROID_API` must agree; both are `26`.

`CMAKE_ANDROID_STL_TYPE c++_static` is kept to match Kotlin/Native's Android
flag set and CMake's Android default. Note it only affects the target **compile**
flags: no STL runtime is linked into a static archive, so the shipped archive is
**not** self-contained -- the consumer chooses the runtime at final link (see
"Open risk: consumer C++ runtime").

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
| Android sysroot | API levels 16-29 (`android-26` present, with `libvulkan.so`) |
| Link flags (`linkerKonanFlags.android_*`) | `-lm -lc++_static -lc++abi -landroid -llog -latomic` |
| C++ ABI namespace | `std::__ndk1` (same inline namespace as NDK 27) |

So the NDK Kotlin/Native 2.4.20 effectively compiles/links with is the
**r19c-era toolchain it bundles itself**; the local NDK is only relevant to the
Dawn build. This spike pins the build NDK to **27.3.13750724** and records the
compatibility consequence below.

### Open risk: consumer C++ runtime (unresolved)

The Dawn archive is compiled with **NDK 27.3.13750724**. Kotlin/Native 2.4.20
**always** links its bundled **r19c-era static libc++**
(`linkerKonanFlags.android_arm64 = -lm -lc++_static -lc++abi -landroid -llog
-latomic` in `konan.properties`), and there is no documented switch to stop it.
Dawn references C++ runtime symbols that the bundled r19c libc++ does **not**
define (verified with `llvm-nm` against `libwebgpu_dawn.a`, arm64):

| Symbol (mangled, `std::__ndk1`) | Kotlin bundled r19c `libc++_static.a` | NDK 27 `libc++_shared.so` |
| --- | --- | --- |
| `__libcpp_verbose_abort(char const*, ...)` | missing | present |
| `__libcpp_atomic_wait(void const volatile*, int)` | missing | present |
| `__cxx_atomic_notify_all(void const volatile*)` | missing | present |
| `__libcpp_atomic_monitor(void const volatile*)` | missing | present |
| `basic_filebuf<...>::basic_filebuf()` / `~basic_filebuf()` / `open(char const*, unsigned)` | missing | present |
| `basic_stringbuf<...>::operator=(basic_stringbuf&&)` | missing | present |
| `__fs::filesystem::path::__filename() const` | missing | present |

**This is a risk, not a solved constraint.** A shared library may carry undefined
symbols, so a Kotlin/Native `android_arm64` link of the archive *succeeds* while
leaving those symbols undefined against the bundled libc++ -- the failure appears
on device at load time, not at build time. Simply making NDK 27's
`libc++_shared.so` available does **not** replace the r19c static runtime that
Kotlin/Native also links: the app would carry two libc++ implementations sharing
the `std::__ndk1` namespace. A test link that added NDK 27's `libc++_shared.so`
recorded `NEEDED libc++_shared.so` but the references still showed as undefined
against the bundled static runtime. "Ship the `.so`" therefore conflates *linking*
it with *packaging* it into `jniLibs`, and neither variant has been proven.

Two candidate mechanisms. **Both are unverified**, and each must be proven by an
end-to-end KMP cinterop link **plus an on-device run** before any `androidNative*`
target is declared consumable:

1. **Remediate at the consumer link.** Have the consumer link NDK 27's
   `libc++_shared.so` explicitly -- e.g. `linkerOpts` requesting `-lc++_shared`
   with the ordering / `-Wl,--no-as-needed` needed to keep it -- and package
   `libc++_shared.so` taken from NDK 27 into `jniLibs/<abi>/`. The r19c static
   libc++ that Kotlin/Native also links must be accounted for
   (`pickFirst` / symbol precedence), and the consumer must show that the NDK 27
   implementation is the one resolving `std::__ndk1`.
2. **Remediate at the Dawn build.** Rebuild Dawn against an NDK whose libc++ is
   the same vintage as Kotlin/Native's bundled one (r19c). Record that Dawn's
   sources/CMake may not build against r19c and that no such NDK is installed on
   this machine; this is the fallback if mechanism 1 cannot be made to work.

The Dawn build pin remains **NDK 27.3.13750724**.

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
(the host protoc bootstrap step), and the first cross build spent ~100 s
rebuilding it before the arm64 build.

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
  `androidNativeArm64` -> `arm64-v8a`, `androidNativeArm32` -> `armeabi-v7a`,
  `androidNativeX64` -> `x86_64`, `androidNativeX86` -> `x86`.
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

## Open risk / follow-up

* **No end-to-end Kotlin/Native link test has been performed for the Android
  targets.** All four ABIs are validated at the **build** level only. The
  consumer C++ runtime risk above is unresolved; until a KMP cinterop link **and
  an on-device run** succeed via mechanism 1 or 2, these targets are
  build-feasible but **not** proven consumable.
* The risk may be retired if a future Kotlin/Native release updates its bundled
  Android toolchain, or once mechanism 1 or 2 is proven against the pinned NDK.
* `ANDROID_NDK_HOME` is misconfigured on this machine (points at an uninstalled
  revision). Builds here override it explicitly; CI must set it to
  `27.3.13750724`.

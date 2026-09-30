# Consuming dawn-packer from Kotlin

`dawn-packer` publishes prebuilt [Dawn](https://dawn.googlesource.com/dawn)
(WebGPU) native libraries, one archive per Kotlin/Native target and per linkage
(`static` or `shared`; `mingwX64` ships `shared` only). This page describes
downloading, verification, the cinterop declaration and the system dependencies
to link on the consumer side.

The reference Dawn pin is `chromium/8077` (see `dawn-pin.env`); the slug used in
file names replaces `/` with `-`, i.e. `chromium-8077`.

## 1. Download and verify an archive

Archives are attached to GitHub Releases. URL pattern:

```
https://github.com/Graphiks-org/dawn-packer/releases/download/<release>/dawn-<dawnTagSlug>-<kotlinTarget>-<linkage>.tar.gz
```

Concrete examples for release `v0.1.0`:

```
https://github.com/Graphiks-org/dawn-packer/releases/download/v0.1.0/dawn-chromium-8077-linuxX64-static.tar.gz
https://github.com/Graphiks-org/dawn-packer/releases/download/v0.1.0/dawn-chromium-8077-macosArm64-shared.tar.gz
```

Each release also contains:

- `SHA256SUMS` -- one line `<sha256>  <file>` per archive;
- `index.json` -- aggregate of the `manifest.json` of every archive.

Verify the downloaded archive (`SHA256SUMS` lists every archive, hence the
filtering on the wanted file):

```bash
# macOS
grep 'dawn-chromium-8077-macosArm64-static.tar.gz' SHA256SUMS | shasum -a 256 -c -

# Linux
grep 'dawn-chromium-8077-linuxX64-static.tar.gz' SHA256SUMS | sha256sum -c -
```

Then extract into a local directory, for example
`third_party/dawn/<kotlinTarget>/<linkage>`:

```bash
mkdir -p third_party/dawn/linuxX64/static
tar xzf dawn-chromium-8077-linuxX64-static.tar.gz -C third_party/dawn/linuxX64/static
```

### Archive contents

```text
include/webgpu/webgpu.h                    # shim: #include "dawn/webgpu.h"
include/webgpu/webgpu_cpp.h                # C++ shim (unused for C cinterop)
include/dawn/webgpu.h                      # WebGPU C API (the real header)
include/dawn/...                           # additional Dawn headers
lib/libwebgpu_dawn.a                       # static variant
lib/libwebgpu_dawn.so | .dylib             # shared variant (instead of the .a)
bin/webgpu_dawn.dll                        # Windows shared variant, alongside its runtime
bin/msvcp140.dll | vcruntime140*.dll
lib/webgpu_dawn.lib                        # Windows import library instead of the .a
manifest.json
```

`manifest.json` describes the archive precisely: Dawn tag and **revision**
(`dawn.tag`, `dawn.revision`), target (`target.kotlinTarget`, `triple`, `os`,
`arch`), `linkage`, `backends` and the `sha256`/`size` of every file. It is the
source of truth for verifying what was actually built.

## 2. Declaring the cinterop

`src/nativeInterop/cinterop/webgpu.def`, **static** variant (Apple example):

```def
headers = dawn/webgpu.h
headerFilter = dawn/webgpu.h
compilerOpts = -Ithird_party/dawn/macosArm64/static/include
staticLibraries = libwebgpu_dawn.a
libraryPaths = third_party/dawn/macosArm64/static/lib
```

Points to watch:

- **The C API lives in `dawn/webgpu.h`**, not in `webgpu/webgpu.h`: the latter
  is only a shim that does `#include "dawn/webgpu.h"`. `headers` and
  `headerFilter` must therefore target `dawn/webgpu.h`. If you prefer to point
  `headers = webgpu/webgpu.h`, the filter must still allow the real
  header (`headerFilter = webgpu/** dawn/**` or simply `dawn/webgpu.h`),
  otherwise cinterop excludes all declarations and the klib is empty.
- One `.def` file per platform: `staticLibraries` and `libraryPaths`
  differ per target and linkage.

**shared** variant (the `.a` does not exist, the dynamic library is linked):

```def
headers = dawn/webgpu.h
headerFilter = dawn/webgpu.h
compilerOpts = -Ithird_party/dawn/macosArm64/shared/include
linkerOpts = -Lthird_party/dawn/macosArm64/shared/lib -lwebgpu_dawn
```

## 3. Wiring the Gradle target

```kotlin
kotlin {
    macosArm64 {
        compilations.getByName("main").cinterops.create("webgpu") {
            defFile(project.file("src/nativeInterop/cinterop/webgpu.def"))
        }

        // Apple static variant: the consumer must link the frameworks.
        binaries.all {
            linkerOpts(
                "-framework", "Metal",
                "-framework", "Foundation",
                "-framework", "CoreGraphics",
                "-framework", "QuartzCore",
                "-framework", "IOKit",
                "-framework", "IOSurface",
            )
        }
    }
}
```

On Linux, same structure with `linuxX64 { ... }` and the link options from the
next section. The same cinterop declaration applies to `iosArm64`,
`iosSimulatorArm64`, `iosX64`, `tvosArm64` and `tvosSimulatorArm64` (frameworks and
toolchain identical to the Apple variant above).

## 4. System dependencies to link (static variant)

The monolithic Dawn library **does not embed** the system dependencies:
the consumer provides them at final link. These lists are exactly those
used by `scripts/run-smoke-test.sh`, which links each real archive:

- **Apple** (macOS / iOS / tvOS):

  ```
  -framework Metal -framework Foundation -framework CoreGraphics \
  -framework QuartzCore -framework IOKit -framework IOSurface
  ```

  `IOKit` and `IOSurface` are genuinely required at link time (Dawn compiles
  `IOSurfaceUtils.cpp` for all Apple platforms), even if a minimal program
  only calls the `wgpu*` API.

- **Linux**: `-lpthread -ldl -lm`. Add X11/Wayland libraries as needed
  if your application depends on them.

- **Android**: the system `.so` files (`liblog`, `libandroid`, `libatomic`) are
  provided by the Kotlin/Native runtime. See the NDK constraint in section 6.

The Dawn library is written in C++ even though its API is C. The final link
is therefore a C++ link: `scripts/run-smoke-test.sh` uses a C++ driver
(`c++`) and does **not** add `-lc++` itself. In Kotlin/Native cinterop, the
C++ toolchain of the target is provided by Kotlin/Native.

## 5. Shared variant: deploy the library with the application

The `-shared` archive contains `lib/libwebgpu_dawn.so` (Linux/Android) or
`lib/libwebgpu_dawn.dylib` (Apple); it must be shipped **alongside** the
application, not merely linked at build time:

- **Android**: place the `.so` for the right ABI in
  `src/androidMain/jniLibs/<abi>/libwebgpu_dawn.so` (ABIs: `arm64-v8a`,
  `armeabi-v7a`, `x86_64`, `x86`).
- **Apple**: embed and sign the `.dylib` (for example in
  `Contents/Frameworks/`), and reference its path via `@rpath`/`@loader_path`.
  The shared library already carries its Apple dependencies in its *load
  commands* (`otool -L` lists CoreFoundation, Foundation, IOSurface, QuartzCore,
  Cocoa, IOKit, Metal and `libc++`); the consumer therefore does not have to
  link them again.
- **Linux/desktop**: install the `.so` with the application and make it
  findable (`RPATH`, `LD_LIBRARY_PATH`, or next to the executable).
- **Windows**: the archive carries `webgpu_dawn.dll` and the MSVC runtime DLLs
  it needs in `bin/`; copy `bin/` next to the executable, because Windows
  resolves an adjacent DLL without configuration.

`scripts/run-smoke-test.sh` illustrates the dynamic link:
`-L<lib> -lwebgpu_dawn -Wl,-rpath,<lib>`.

## 6. Constraints and unavailable targets

- **macOS** (`macosArm64`): the library is built with
  `-DCMAKE_OSX_DEPLOYMENT_TARGET=12.0`, Kotlin/Native 2.4.20's minimum macOS.
  Its effective `minos` is therefore **12.0** (and not the build runner's
  version); `vtool -show-build` / `otool -l` on an archive member
  confirms it. The iOS/tvOS targets likewise carry their floor via their
  toolchain (`15.0`).
- **Android**: the `androidNative*` archives are built with NDK
  **27.3.13750724** (API 26, STL `c++_static`). Kotlin/Native consumability
  is **not** established: Kotlin/Native 2.4.20 links its own static libc++
  from the r19c era, which does not define all the `std::__ndk1` symbols
  referenced by the objects compiled with NDK 27. The risk is described in
  detail in `docs/spikes/android.md` ("Open risk: consumer C++ runtime") and is
  not retired by either of the candidate remediations until a KMP cinterop link
  **and** an on-device run have succeeded. Do not
  consider these targets proven consumable.
- **watchOS** (`watchosArm64`, `watchosDeviceArm64`, `watchosSimulatorArm64`):
  no archive. The watchOS SDKs provide neither `Metal.framework` nor
  `IOSurface.framework`, and `arm64_32` (ILP32) fails Dawn's
  `sizeof(size_t) == 8` assertion.
- **`mingwX64`**: the archive is built with MSVC (D3D12, D3D11, Vulkan and null
  backends) and consumed through its import library; the consumer triple stays
  `x86_64-pc-windows-gnu`. The shared archive carries `webgpu_dawn.dll` and the
  MSVC runtime DLLs it needs, so copying `bin/` next to the executable is the
  whole deployment. No redistributable or system package is required. The DLL
  also exports Dawn's native C++ API as MSVC-mangled names, which does not affect
  a C consumer.
- The headers and the manifest are the same across linkages; only the
  library changes. Check the Dawn revision actually built in
  `manifest.json` before debugging unexpected behavior.

See also:

- `README.md` -- target status and local build;
- `packaging/manifest.schema.json` -- the shipped manifest contract;
- `docs/spikes/` -- per-platform verdicts.

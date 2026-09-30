# dawn-packer

Prebuilt [Dawn](https://dawn.googlesource.com/dawn) (WebGPU) native libraries,
published as GitHub Releases for non-web Kotlin/Native targets.

This repository only produces libraries (`webgpu.h` headers plus the Dawn
library: `libwebgpu_dawn`, or `webgpu_dawn.dll` with its import library and MSVC
runtime on Windows); any Kotlin/Native, JNI, Swift, etc. binding lives in the
consuming project.

The Dawn pin (`chromium/8077`) is declared in `dawn-pin.env` (`DAWN_TAG`), resolved
to a fixed commit by the `dawn/` submodule and recorded in
`build/dawn-revision.txt`.

## Target status

`targets/matrix.json` is the source of truth (triple, runner, toolchain,
backends, status). Targets with `status != "dropped"` are built by CI and
published; the others are abandoned after the spike.

Targets that produce an archive (all declared linkages are built in CI):

| Target | Backends | Local validation |
|---|---|---|
| `macosArm64` | metal, null | archive + install (static + shared); smoke test run |
| `iosArm64` | metal, null | archive + install; device: structural check |
| `iosSimulatorArm64` | metal, null | archive + install (cross) |
| `iosX64` | metal, null | archive + install (cross) |
| `tvosArm64` | metal, null | archive + install (cross) |
| `tvosSimulatorArm64` | metal, null | install tree only (archive in CI) |
| `linuxX64` | vulkan, gles, null | built in CI (runner `ubuntu-24.04`); nothing locally |
| `linuxArm64` | vulkan, gles, null | built in CI (runner `ubuntu-24.04-arm`); nothing locally |
| `mingwX64` | d3d12, d3d11, vulkan, null | built in CI (runner `windows-2022`); consumer smoke run in CI |
| `androidNativeArm64` | vulkan, gles, null | install tree only (archive in CI); pinned NDK; consumer risk not retired |
| `androidNativeArm32` | vulkan, gles, null | install tree only (archive in CI); pinned NDK; consumer risk not retired |
| `androidNativeX64` | vulkan, gles, null | install tree only (archive in CI); pinned NDK; consumer risk not retired |
| `androidNativeX86` | vulkan, gles, null | install tree only (archive in CI); pinned NDK; consumer risk not retired |

Dropped targets (`dropped`, no archive):

| Target | Reason |
|---|---|
| `watchosArm64` | watchOS SDK without `Metal.framework`/`IOSurface.framework`; `arm64_32` (ILP32) fails Dawn's `sizeof(size_t) == 8` assertion |
| `watchosDeviceArm64` | watchOS SDK without `Metal.framework` or `IOSurface.framework` (configure `find_library(Metal) REQUIRED` fails) |
| `watchosSimulatorArm64` | same: watchOS SDK without Metal/IOSurface |

See `docs/spikes/android.md`, `docs/spikes/apple-watchos-tvos.md`,
`docs/spikes/mingw-x64.md` and `docs/spikes/windows-msvc.md` for the detailed
verdicts.

## Local build

```bash
bash scripts/sync.sh                       # Dawn submodule + patches + build/dawn-revision.txt
bash scripts/build-target.sh linuxX64 static
bash scripts/package.sh linuxX64 static    # -> dist/linuxX64/dawn-chromium-8077-linuxX64-static.tar.gz
```

The cross targets (iOS, tvOS, Android) need a host `protoc`, built
automatically by `scripts/build-target.sh` via `scripts/build-host-protoc.sh`.
Android targets additionally require `ANDROID_NDK_HOME` pointing at NDK
**27.3.13750724**.

## Tests

```bash
bash scripts/run-tests.sh
```

The aggregator discovers and runs `tests/test-*.sh`, prints a final summary
(`SUMMARY: N passed, N skipped, N failed`) and lists the failing tests when
applicable. Tests that run a real Dawn build are deliberately excluded from the
fast CI (see `.github/workflows/build.yml`). For a fast local feedback loop,
`DAWN_PACKER_SKIP_HEAVY=1 bash scripts/run-tests.sh` skips the
three expensive tests (`test-build-target.sh`, `test-shared-symbols.sh`,
`test-build-target-protoc.sh`) and prints a `SKIP (heavy)` line for each;
without that variable, the full suite runs.

## Consuming from Kotlin

See `docs/consumption.md`: archive URL pattern, `SHA256SUMS`
verification, cinterop `.def` file, Gradle snippet and system dependencies to
link per platform.

## Known gaps

GitHub actions are referenced as `@v4`. The SHA pinning required by the
spec is a post-v1 hardening.

The consumability of the `androidNative*` targets is not proven: the
libc++ Kotlin/Native/NDK 27 risk is documented in `docs/spikes/android.md`.

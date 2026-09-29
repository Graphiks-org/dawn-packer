# Apple tvOS (device, arm64) cross toolchain.
#
# Used by the `tvosArm64` entry of targets/matrix.json. Builds Dawn's Metal +
# null backends against the Xcode `appletvos` SDK. Feasibility is assessed in
# docs/spikes/apple-watchos-tvos.md.
set(CMAKE_SYSTEM_NAME tvOS)
set(CMAKE_OSX_SYSROOT appletvos)
set(CMAKE_OSX_DEPLOYMENT_TARGET 15.0)
set(CMAKE_OSX_ARCHITECTURES arm64)

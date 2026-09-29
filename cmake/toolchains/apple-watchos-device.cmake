# Apple watchOS (device, arm64 / 64-bit pointers) cross toolchain.
#
# Used by the `watchosDeviceArm64` entry of targets/matrix.json. The 32-bit
# pointer watchOS toolchain is cmake/toolchains/apple-watchos.cmake (see Ruling
# P3 in the plan ledger). Builds Dawn's Metal + null backends against the Xcode
# `watchos` SDK. Feasibility is assessed in
# docs/spikes/apple-watchos-tvos.md.
set(CMAKE_SYSTEM_NAME watchOS)
set(CMAKE_OSX_SYSROOT watchos)
set(CMAKE_OSX_DEPLOYMENT_TARGET 8.0)
set(CMAKE_OSX_ARCHITECTURES arm64)

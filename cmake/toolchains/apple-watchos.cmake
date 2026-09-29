# Apple watchOS (device, arm64_32 / ILP32) cross toolchain.
#
# Used by the `watchosArm64` entry of targets/matrix.json. This is the 32-bit
# pointer watchOS device ABI; the 64-bit pointer device toolchain is
# cmake/toolchains/apple-watchos-device.cmake (see Ruling P3 in the plan
# ledger). Builds Dawn's Metal + null backends against the Xcode `watchos` SDK.
# Feasibility is assessed in docs/spikes/apple-watchos-tvos.md.
set(CMAKE_SYSTEM_NAME watchOS)
set(CMAKE_OSX_SYSROOT watchos)
set(CMAKE_OSX_DEPLOYMENT_TARGET 8.0)
set(CMAKE_OSX_ARCHITECTURES arm64_32)

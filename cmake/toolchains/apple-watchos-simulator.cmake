# Apple watchOS Simulator (arm64) cross toolchain.
#
# Used by the `watchosSimulatorArm64` entry of targets/matrix.json. Builds Dawn's
# Metal + null backends against the Xcode `watchsimulator` SDK. Feasibility is
# assessed in docs/spikes/apple-watchos-tvos.md.
set(CMAKE_SYSTEM_NAME watchOS)
set(CMAKE_OSX_SYSROOT watchsimulator)
set(CMAKE_OSX_DEPLOYMENT_TARGET 8.0)
set(CMAKE_OSX_ARCHITECTURES arm64)

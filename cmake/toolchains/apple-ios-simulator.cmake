# Apple iOS Simulator (arm64) cross toolchain.
#
# Used by the `iosSimulatorArm64` entry of targets/matrix.json. Builds Dawn's
# Metal + null backends against the Xcode `iphonesimulator` SDK for the Apple
# Silicon simulator.
set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_OSX_SYSROOT iphonesimulator)
set(CMAKE_OSX_DEPLOYMENT_TARGET 15.0)
set(CMAKE_OSX_ARCHITECTURES arm64)

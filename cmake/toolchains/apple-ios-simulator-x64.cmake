# Apple iOS Simulator (x86_64) cross toolchain.
#
# Used by the `iosX64` entry of targets/matrix.json. Builds Dawn's Metal + null
# backends against the Xcode `iphonesimulator` SDK for the Intel simulator.
set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_OSX_SYSROOT iphonesimulator)
set(CMAKE_OSX_DEPLOYMENT_TARGET 15.0)
set(CMAKE_OSX_ARCHITECTURES x86_64)

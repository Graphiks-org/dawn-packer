# Apple iOS (device, arm64) cross toolchain.
#
# Used by the `iosArm64` entry of targets/matrix.json. Builds Dawn's Metal +
# null backends against the Xcode `iphoneos` SDK.
set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_OSX_SYSROOT iphoneos)
set(CMAKE_OSX_DEPLOYMENT_TARGET 15.0)
set(CMAKE_OSX_ARCHITECTURES arm64)

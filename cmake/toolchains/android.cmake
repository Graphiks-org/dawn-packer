# Android cross toolchain (NDK), shared by all four `androidNative*` entries of
# targets/matrix.json.
#
# The ABI is deliberately NOT set here: a single toolchain file cannot serve four
# ABIs (Ruling P14). Instead `scripts/build-target.sh` forwards the matrix
# entry's `androidAbi` field as -DCMAKE_ANDROID_ARCH_ABI (arm64-v8a, armeabi-v7a,
# x86_64, x86). This file relies on CMake's built-in Android/NDK support rather
# than re-deriving compiler paths by hand.
#
# Pinned and validated NDK: 27.3.13750724 (see docs/spikes/android.md).
set(CMAKE_SYSTEM_NAME Android)
set(CMAKE_SYSTEM_VERSION 26)
set(CMAKE_ANDROID_API 26)

# The NDK location comes from ANDROID_NDK_HOME. If it is absent, fall back to
# the Android SDK layout for the pinned revision so a plain SDK install works.
if (NOT DEFINED CMAKE_ANDROID_NDK OR CMAKE_ANDROID_NDK STREQUAL "")
  if (DEFINED ENV{ANDROID_NDK_HOME} AND NOT "$ENV{ANDROID_NDK_HOME}" STREQUAL "")
    set(CMAKE_ANDROID_NDK "$ENV{ANDROID_NDK_HOME}")
  elseif (DEFINED ENV{ANDROID_HOME} AND EXISTS "$ENV{ANDROID_HOME}/ndk/27.3.13750724")
    set(CMAKE_ANDROID_NDK "$ENV{ANDROID_HOME}/ndk/27.3.13750724")
  else()
    message(FATAL_ERROR
      "Android NDK not found. Set ANDROID_NDK_HOME to the pinned NDK 27.3.13750724.")
  endif()
endif()

if (NOT EXISTS "${CMAKE_ANDROID_NDK}")
  message(FATAL_ERROR "CMAKE_ANDROID_NDK='${CMAKE_ANDROID_NDK}' does not exist")
endif()

# STL selection only affects the target compile flags. For a static archive no
# STL runtime is linked in, so this does NOT make the shipped archive
# self-contained; the consumer chooses the runtime at final link. The value is
# kept at c++_static to match Kotlin/Native's Android flag set
# (`-lc++_static -lc++abi` in konan.properties) and CMake's Android default, but
# the consumer-side libc++ version is an open risk (docs/spikes/android.md).
#
# NOTE: the correct CMake variable is CMAKE_ANDROID_STL_TYPE (CMake's built-in
# Android support); the older `CMAKE_ANDROID_STL`/`ANDROID_STL` spelling used by
# the NDK's own toolchain file is a silent no-op here.
set(CMAKE_ANDROID_STL_TYPE c++_static)

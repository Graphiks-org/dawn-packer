# Toolchain: x86_64-pc-windows-gnu (Kotlin/Native mingwX64).
#
# STATUS: unused by the pipeline. The mingwX64 target is built with MSVC on a
# Windows runner instead; see docs/spikes/windows-msvc.md. This file is kept as
# the record of the abandoned MinGW cross route, and it only ever built the null
# backend.
#
# Builds with LLVM clang against a MinGW-w64 sysroot (GNU ABI), NOT MSVC.
# On macOS the host clang (/usr/bin/clang) cannot emit PE objects or link with
# MinGW, so this file prefers a full LLVM clang and pairs it with the GNU ld
# shipped by MinGW-w64.
#
# Overridable inputs (pass with -D, or via the environment):
#   MINGW_SYSROOT    prefix containing x86_64-w64-mingw32/{include,lib}
#   MINGW_CLANG_DIR  directory holding clang/clang++
#   MINGW_LD         linker binary (defaults to the sysroot's GNU ld)

set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

set(MINGW_TRIPLE x86_64-w64-mingw32)

if(NOT MINGW_SYSROOT)
  foreach(_cand
      "$ENV{MINGW_SYSROOT}"
      "/opt/homebrew/opt/mingw-w64/toolchain-x86_64"
      "/usr/local/opt/mingw-w64/toolchain-x86_64"
      "C:/msys64/mingw64")
    if(_cand AND EXISTS "${_cand}/${MINGW_TRIPLE}/include")
      set(MINGW_SYSROOT "${_cand}")
      break()
    endif()
  endforeach()
endif()
if(NOT MINGW_SYSROOT OR NOT EXISTS "${MINGW_SYSROOT}/${MINGW_TRIPLE}/include")
  message(FATAL_ERROR
    "mingw-x64.cmake: MinGW-w64 sysroot not found. "
    "Install mingw-w64 or pass -DMINGW_SYSROOT=<prefix>.")
endif()

if(NOT MINGW_CLANG_DIR)
  foreach(_dir
      "$ENV{MINGW_CLANG_DIR}"
      "/opt/homebrew/opt/llvm/bin"
      "/usr/local/opt/llvm/bin")
    if(_dir AND EXISTS "${_dir}/clang++")
      set(MINGW_CLANG_DIR "${_dir}")
      break()
    endif()
  endforeach()
endif()
if(MINGW_CLANG_DIR)
  set(CMAKE_C_COMPILER "${MINGW_CLANG_DIR}/clang")
  set(CMAKE_CXX_COMPILER "${MINGW_CLANG_DIR}/clang++")
else()
  set(CMAKE_C_COMPILER clang)
  set(CMAKE_CXX_COMPILER clang++)
endif()

set(CMAKE_C_COMPILER_TARGET "${MINGW_TRIPLE}")
set(CMAKE_CXX_COMPILER_TARGET "${MINGW_TRIPLE}")
set(CMAKE_SYSROOT "${MINGW_SYSROOT}")

# clang does not search for a cross "ld", so point it at MinGW's GNU ld.
if(NOT MINGW_LD)
  foreach(_ld
      "$ENV{MINGW_LD}"
      "${MINGW_SYSROOT}/../bin/${MINGW_TRIPLE}-ld"
      "/opt/homebrew/opt/mingw-w64/bin/${MINGW_TRIPLE}-ld"
      "/usr/local/opt/mingw-w64/bin/${MINGW_TRIPLE}-ld")
    if(_ld AND EXISTS "${_ld}")
      set(MINGW_LD "${_ld}")
      break()
    endif()
  endforeach()
endif()
if(MINGW_LD)
  set(CMAKE_EXE_LINKER_FLAGS_INIT "--ld-path=${MINGW_LD}")
  set(CMAKE_SHARED_LINKER_FLAGS_INIT "--ld-path=${MINGW_LD}")
  set(CMAKE_MODULE_LINKER_FLAGS_INIT "--ld-path=${MINGW_LD}")
endif()

# Resource compiler for the RC language / any .rc sources.
find_program(CMAKE_RC_COMPILER
  NAMES "${MINGW_TRIPLE}-windres" windres
  HINTS "${MINGW_SYSROOT}/../bin"
  NO_CMAKE_FIND_ROOT_PATH)

set(CMAKE_FIND_ROOT_PATH "${MINGW_SYSROOT}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

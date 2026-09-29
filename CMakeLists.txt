cmake_minimum_required(VERSION 3.22)
project(dawn_packer LANGUAGES C CXX)

if (NOT DEFINED DAWN_PACKER_LINKAGE)
  set(DAWN_PACKER_LINKAGE "STATIC")
endif()
string(TOUPPER "${DAWN_PACKER_LINKAGE}" DAWN_PACKER_LINKAGE)
if (NOT DAWN_PACKER_LINKAGE STREQUAL "STATIC" AND NOT DAWN_PACKER_LINKAGE STREQUAL "SHARED")
  message(FATAL_ERROR "DAWN_PACKER_LINKAGE must be STATIC or SHARED")
endif()

set(DAWN_FETCH_DEPENDENCIES ON CACHE BOOL "" FORCE)
set(DAWN_ENABLE_INSTALL ON CACHE BOOL "" FORCE)
set(DAWN_BUILD_SAMPLES OFF CACHE BOOL "" FORCE)
set(DAWN_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(DAWN_BUILD_MONOLITHIC_LIBRARY "${DAWN_PACKER_LINKAGE}" CACHE STRING "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

add_subdirectory(dawn)

if (NOT TARGET webgpu_dawn)
  message(FATAL_ERROR "webgpu_dawn target missing; DAWN_BUILD_MONOLITHIC_LIBRARY is not effective")
endif()

# The shared variant must only export the public WebGPU C API. Dawn's export
# macros mark the entry points, but nothing hides the bundled internal symbols
# (Abseil, Tint, Dawn native) by default, so restrict the dynamic symbol table.
if (DAWN_PACKER_LINKAGE STREQUAL "SHARED")
  if (APPLE)
    # ld64 has no --exclude-libs; an export list is the equivalent and accepts
    # shell-style wildcards (see `man ld`, -exported_symbols_list). Matching
    # Mach-O names carry a leading underscore (_wgpuCreateInstance).
    set(_dawn_packer_exports "${CMAKE_CURRENT_BINARY_DIR}/webgpu_dawn_exports.txt")
    file(WRITE "${_dawn_packer_exports}" "_wgpu*\n_dawn*\n")
    target_link_options(webgpu_dawn PRIVATE
      "-Wl,-exported_symbols_list,${_dawn_packer_exports}")
  else()
    # --exclude-libs only localizes symbols coming from static archives; Dawn's
    # directly-linked objects (Tint, Dawn native, bundled Abseil) would still
    # leak. An ELF version script localizes everything not listed, including
    # those objects, so only the public API stays in the dynamic symbol table.
    set(_dawn_packer_version_script "${CMAKE_CURRENT_BINARY_DIR}/webgpu_dawn_exports.map")
    file(WRITE "${_dawn_packer_version_script}"
      "{\n  global:\n    wgpu*;\n    dawn*;\n  local:\n    *;\n};\n")
    target_link_options(webgpu_dawn PRIVATE
      "-Wl,--version-script=${_dawn_packer_version_script}")
  endif()
endif()

# NOTE: Dawn must be added WITHOUT EXCLUDE_FROM_ALL: CMake ignores install()
# rules of an excluded subdirectory, which would install nothing (see
# https://cmake.org/cmake/help/latest/prop_dir/EXCLUDE_FROM_ALL.html).
# webgpu_upstream_cpp_headers_gen is not a dependency of webgpu_dawn but its
# generated headers are installed alongside the library, so the build target
# must pull it in (otherwise "cmake --install" fails on a missing generated file).
add_custom_target(dawn_packer DEPENDS webgpu_dawn webgpu_upstream_cpp_headers_gen)

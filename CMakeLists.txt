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

# NOTE: Dawn must be added WITHOUT EXCLUDE_FROM_ALL: CMake ignores install()
# rules of an excluded subdirectory, which would install nothing (see
# https://cmake.org/cmake/help/latest/prop_dir/EXCLUDE_FROM_ALL.html).
# webgpu_upstream_cpp_headers_gen is not a dependency of webgpu_dawn but its
# generated headers are installed alongside the library, so the build target
# must pull it in (otherwise "cmake --install" fails on a missing generated file).
add_custom_target(dawn_packer DEPENDS webgpu_dawn webgpu_upstream_cpp_headers_gen)

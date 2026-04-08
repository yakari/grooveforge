# Flutter FFI plugin CMakeLists for dart_vst_host (Linux).
#
# Flutter's build system invokes this file automatically when the package is
# declared as an FFI plugin (ffiPlugin: true in pubspec.yaml). The resulting
# libdart_vst_host.so is bundled into the app's lib/ directory without any
# manual cmake / make / cp steps.
#
# Source files live in ../native/  (dart_vst_host/native/)
# VST3 SDK lives in  ../../vst3sdk/ (packages/flutter_vst3/vst3sdk/)

cmake_minimum_required(VERSION 3.13)
set(PROJECT_NAME "dart_vst_host")
project(${PROJECT_NAME} LANGUAGES CXX)

cmake_policy(SET CMP0063 NEW)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# ── Paths ─────────────────────────────────────────────────────────────────────
#
# Flutter's build system places a SYMLINK to this package inside the app's
# build tree:
#   <app>/linux/flutter/ephemeral/.plugin_symlinks/dart_vst_host -> <real package dir>
#
# CMake expands CMAKE_CURRENT_SOURCE_DIR using the *symlink* path, so a naive
# "../../vst3sdk" would resolve to .plugin_symlinks/vst3sdk/ which doesn't
# exist.  get_filename_component(... REALPATH) follows the symlink chain and
# gives us the true on-disk location before we construct any derived paths.
get_filename_component(REAL_PLUGIN_DIR "${CMAKE_CURRENT_SOURCE_DIR}/.." REALPATH)

set(NATIVE_DIR "${REAL_PLUGIN_DIR}/native")

# The VST3 SDK is vendored at packages/flutter_vst3/vst3sdk/.
# Allow override via environment variable for custom build environments.
if(DEFINED ENV{VST3_SDK_DIR})
  set(VST3_SDK_DIR "$ENV{VST3_SDK_DIR}")
else()
  set(VST3_SDK_DIR "${REAL_PLUGIN_DIR}/../vst3sdk")
endif()

if(NOT EXISTS "${VST3_SDK_DIR}/CMakeLists.txt")
  message(FATAL_ERROR
    "VST3 SDK not found at ${VST3_SDK_DIR}.\n"
    "It should be vendored at packages/flutter_vst3/vst3sdk/ in the repo."
  )
endif()

# ── VST3 SDK sources ──────────────────────────────────────────────────────────

file(GLOB_RECURSE VST3_BASE_SOURCES
  ${VST3_SDK_DIR}/base/source/*.cpp
  ${VST3_SDK_DIR}/pluginterfaces/base/*.cpp
  ${VST3_SDK_DIR}/pluginterfaces/vst/*.cpp
  ${VST3_SDK_DIR}/pluginterfaces/gui/*.cpp
)

file(GLOB VST3_SDK_SOURCES
  ${VST3_SDK_DIR}/public.sdk/source/vst/vstbus.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/vstcomponent.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/vstcomponentbase.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/vsteditcontroller.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/vstinitiids.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/vstnoteexpressiontypes.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/vstparameters.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/vstpresetfile.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/vstrepresentation.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/hostclasses.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/pluginterfacesupport.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/module.cpp
  ${VST3_SDK_DIR}/public.sdk/source/common/pluginview.cpp
  ${VST3_SDK_DIR}/public.sdk/source/common/commoniids.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/utility/stringconvert.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/utility/sampleaccurate.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/eventlist.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/parameterchanges.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/plugprovider.cpp
  ${VST3_SDK_DIR}/public.sdk/source/common/updatehandler.cpp
  ${VST3_SDK_DIR}/public.sdk/source/common/memorystream.cpp
  ${VST3_SDK_DIR}/base/thread/source/flock.cpp
  ${VST3_SDK_DIR}/base/thread/source/fcondition.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/connectionproxy.cpp
  ${VST3_SDK_DIR}/public.sdk/source/common/commonstringconvert.cpp
)

# ── Library target ────────────────────────────────────────────────────────────

add_library(${PROJECT_NAME} SHARED
  ${NATIVE_DIR}/src/dart_vst_host.cpp
  ${NATIVE_DIR}/src/dart_vst_host_jack.cpp
  ${NATIVE_DIR}/src/dart_vst_host_editor_linux.cpp
  ${NATIVE_DIR}/src/gfpa_dsp.cpp
  ${VST3_BASE_SOURCES}
  ${VST3_SDK_SOURCES}
)

target_include_directories(${PROJECT_NAME} PRIVATE
  ${VST3_SDK_DIR}
  ${VST3_SDK_DIR}/pluginterfaces
  ${VST3_SDK_DIR}/public.sdk/source
  ${VST3_SDK_DIR}/base/thread/include
  ${NATIVE_DIR}/include
)

target_compile_definitions(${PROJECT_NAME} PRIVATE
  DART_VST_HOST_EXPORTS
  RELEASE=1
)

# ── AddressSanitizer (temporary — remove after debugging) ────────────────
# Enables ASAN for heap-use-after-free, buffer-overflow, and memory
# corruption detection.  Run the app with:
#   LD_PRELOAD=$(gcc -print-file-name=libasan.so) flutter run -d linux
option(ENABLE_ASAN "Enable AddressSanitizer for native code" OFF)
if(ENABLE_ASAN)
  target_compile_options(${PROJECT_NAME} PRIVATE
    -fsanitize=address -fno-omit-frame-pointer -g)
  target_link_options(${PROJECT_NAME} PRIVATE -fsanitize=address)
endif()

# Always build with debug symbols, frame pointers, and member-reorder warnings.
target_compile_options(${PROJECT_NAME} PRIVATE -g -fno-omit-frame-pointer -Wreorder)

# Platform-specific sources.
# Use GLOB_RECURSE so the build stays robust when the VST3 SDK is cloned at
# a different revision than the local copy (files may live at slightly
# different paths between SDK versions).
file(GLOB_RECURSE _LINUX_PLATFORM_SOURCES LIST_DIRECTORIES false
  "${VST3_SDK_DIR}/public.sdk/*.cpp")
list(FILTER _LINUX_PLATFORM_SOURCES INCLUDE REGEX
  "(^|/)(module_linux|threadchecker_linux)\\.cpp$")

if(NOT _LINUX_PLATFORM_SOURCES)
  message(FATAL_ERROR
    "module_linux.cpp / threadchecker_linux.cpp not found under\n"
    "  ${VST3_SDK_DIR}/public.sdk\n"
    "Make sure the VST3 SDK is fully cloned (git clone --depth=1 "
    "https://github.com/steinbergmedia/vst3sdk.git).")
endif()

target_sources(${PROJECT_NAME} PRIVATE ${_LINUX_PLATFORM_SOURCES})

# Suppress all warnings from vendored VST3 SDK sources — they are third-party
# code we do not maintain and warnings here are noise (pragma-pack, deprecated
# wstring_convert, format type mismatches, nontrivial-memcall, etc.).
set_source_files_properties(
  ${VST3_BASE_SOURCES}
  ${VST3_SDK_SOURCES}
  ${_LINUX_PLATFORM_SOURCES}
  PROPERTIES COMPILE_OPTIONS "-w"
)

find_package(PkgConfig REQUIRED)
pkg_check_modules(JACK REQUIRED jack)
target_link_libraries(${PROJECT_NAME} PRIVATE ${JACK_LIBRARIES})
target_include_directories(${PROJECT_NAME} PRIVATE ${JACK_INCLUDE_DIRS})

find_package(X11 REQUIRED)
target_link_libraries(${PROJECT_NAME} PRIVATE ${X11_LIBRARIES})
target_include_directories(${PROJECT_NAME} PRIVATE ${X11_INCLUDE_DIR})

# ── Flutter FFI plugin bundling ───────────────────────────────────────────────
# This variable is read by Flutter's generated_plugins.cmake and causes the
# built .so to be copied into the app bundle's lib/ directory automatically.
set(${PROJECT_NAME}_bundled_libraries
  "$<TARGET_FILE:${PROJECT_NAME}>"
  PARENT_SCOPE
)

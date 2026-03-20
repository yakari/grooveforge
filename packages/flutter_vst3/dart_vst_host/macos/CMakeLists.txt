# Flutter FFI plugin CMakeLists for dart_vst_host (macOS).
#
# Compiled automatically by Flutter's build system when ffiPlugin: true is
# declared in pubspec.yaml.  The resulting libdart_vst_host.dylib is bundled
# into the app bundle.
#
# Audio output: stub (ALSA is Linux-only). Add CoreAudio in the future via
#   dart_vst_host_coreaudio.mm.
# Editor GUI:   stub (X11 is Linux-only). On macOS, FlutterPlatformView allows
#   embedding NSView directly into the Flutter widget tree — a viable future
#   enhancement that would allow in-card plugin UI display on macOS.

cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "dart_vst_host")
project(${PROJECT_NAME} LANGUAGES CXX OBJCXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_OBJCXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# ── Paths (resolve through Flutter's plugin symlink) ──────────────────────────
get_filename_component(REAL_PLUGIN_DIR "${CMAKE_CURRENT_SOURCE_DIR}/.." REALPATH)

set(NATIVE_DIR "${REAL_PLUGIN_DIR}/native")

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

# ── VST3 SDK sources (cross-platform) ─────────────────────────────────────────

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

# ── Library target ─────────────────────────────────────────────────────────────

add_library(${PROJECT_NAME} SHARED
  ${NATIVE_DIR}/src/dart_vst_host.cpp
  # Platform stubs (ALSA + Linux editor → no-ops on macOS)
  ${NATIVE_DIR}/src/dart_vst_host_platform_stubs.cpp
  # GFPA built-in DSP effects (reverb, delay, wah, EQ, compressor, chorus)
  ${NATIVE_DIR}/src/gfpa_dsp.cpp
  # macOS specific implementation
  ${NATIVE_DIR}/src/dart_vst_host_audio_mac.cpp
  ${NATIVE_DIR}/src/dart_vst_host_editor_mac.mm
  ${VST3_BASE_SOURCES}
  ${VST3_SDK_SOURCES}
  # macOS VST3 module loader and thread checker (Objective-C++)
  ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/module_mac.mm
  ${VST3_SDK_DIR}/public.sdk/source/common/threadchecker_mac.mm
)

# The .mm files need Objective-C++ with ARC
set_source_files_properties(
  ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/module_mac.mm
  ${VST3_SDK_DIR}/public.sdk/source/common/threadchecker_mac.mm
  PROPERTIES COMPILE_FLAGS "-x objective-c++ -fobjc-arc"
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

# macOS system frameworks required by VST3 hosting
find_library(COCOA_FRAMEWORK         Cocoa)
find_library(CARBON_FRAMEWORK        Carbon)
find_library(COREFOUNDATION_FRAMEWORK CoreFoundation)
find_library(AUDIOTOOLBOX_FRAMEWORK  AudioToolbox)

target_link_libraries(${PROJECT_NAME} PRIVATE
  ${COCOA_FRAMEWORK}
  ${CARBON_FRAMEWORK}
  ${COREFOUNDATION_FRAMEWORK}
  ${AUDIOTOOLBOX_FRAMEWORK}
)

# ── Flutter FFI plugin bundling ────────────────────────────────────────────────
set(${PROJECT_NAME}_bundled_libraries
  "$<TARGET_FILE:${PROJECT_NAME}>"
  PARENT_SCOPE
)

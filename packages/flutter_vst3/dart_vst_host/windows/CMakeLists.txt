# Flutter FFI plugin CMakeLists for dart_vst_host (Windows).
#
# Compiled automatically by Flutter's build system when ffiPlugin: true is
# declared in pubspec.yaml.  The resulting dart_vst_host.dll is bundled into
# the app's bundle directory.
#
# Audio output: stub (ALSA is Linux-only). Add WASAPI / DirectSound in the
#   future via dart_vst_host_wasapi.cpp.
# Editor GUI:   stub (X11 is Linux-only). PlatformView-based HWND embedding
#   is possible on Windows via FlutterPlatformView — a future enhancement.

cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "dart_vst_host")
project(${PROJECT_NAME} LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# ── Paths (resolve through Flutter's plugin symlink) ──────────────────────────
get_filename_component(REAL_PLUGIN_DIR "${CMAKE_CURRENT_SOURCE_DIR}/.." REALPATH)
file(TO_CMAKE_PATH "${REAL_PLUGIN_DIR}" REAL_PLUGIN_DIR)

set(NATIVE_DIR "${REAL_PLUGIN_DIR}/native")

if(DEFINED ENV{VST3_SDK_DIR})
  set(VST3_SDK_DIR "$ENV{VST3_SDK_DIR}")
  # Convert native backslashes (e.g. D:\a\...) to forward slashes.
  # CMake interprets backslashes as escape sequences in string contexts,
  # so paths from Windows environment variables must be normalised first.
  file(TO_CMAKE_PATH "${VST3_SDK_DIR}" VST3_SDK_DIR)
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

# Find Win32-specific SDK files via GLOB_RECURSE so the build is robust
# across SDK versions where these files may live at different sub-paths.
file(GLOB_RECURSE _WIN32_PLATFORM_SOURCES LIST_DIRECTORIES false
  "${VST3_SDK_DIR}/public.sdk/*.cpp")
list(FILTER _WIN32_PLATFORM_SOURCES INCLUDE REGEX
  "(^|/)(module_win32|threadchecker_win32)\\.cpp$")

if(NOT _WIN32_PLATFORM_SOURCES)
  message(FATAL_ERROR
    "module_win32.cpp / threadchecker_win32.cpp not found under\n"
    "  ${VST3_SDK_DIR}/public.sdk\n"
    "Make sure the VST3 SDK is fully cloned.")
endif()

add_library(${PROJECT_NAME} SHARED
  ${NATIVE_DIR}/src/dart_vst_host.cpp
  # Platform stubs (ALSA + Linux editor → no-ops on Windows)
  ${NATIVE_DIR}/src/dart_vst_host_platform_stubs.cpp
  ${VST3_BASE_SOURCES}
  ${VST3_SDK_SOURCES}
  # Win32 VST3 module loader and thread checker (found by GLOB_RECURSE above)
  ${_WIN32_PLATFORM_SOURCES}
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
  # Suppress MSVC warnings from VST3 SDK
  _CRT_SECURE_NO_WARNINGS
)

# Windows system libraries required by VST3 hosting
target_link_libraries(${PROJECT_NAME} PRIVATE
  ole32
  uuid
  user32
  gdi32
  shell32
)

# ── Flutter FFI plugin bundling ────────────────────────────────────────────────
set(${PROJECT_NAME}_bundled_libraries
  "$<TARGET_FILE:${PROJECT_NAME}>"
  PARENT_SCOPE
)

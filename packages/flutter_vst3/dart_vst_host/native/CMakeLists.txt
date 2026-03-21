cmake_minimum_required(VERSION 3.20)
project(dart_vst_host LANGUAGES CXX)

# Build the VST host library for loading and controlling VST3 plugins.
# When consuming from Dart you will need to load
# libdart_vst_host.{so,dylib,dll} from your application.

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Use the properly downloaded VST3 SDK
if(NOT DEFINED ENV{VST3_SDK_DIR})
  set(VST3_SDK_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../vst3sdk)
else()
  set(VST3_SDK_DIR $ENV{VST3_SDK_DIR})
endif()

if(NOT EXISTS ${VST3_SDK_DIR}/CMakeLists.txt)
  message(FATAL_ERROR "VST3 SDK not found at ${VST3_SDK_DIR}. Download it first.")
endif()

# ── VST3 SDK hosting-layer sources ───────────────────────────────────────────
#
# IMPORTANT: Only include HOSTING-side sources here. Including plugin-side SDK
# sources (vstbus, vstcomponent, vsteditcontroller, vstparameters, etc.) causes
# vtable/virtual-dispatch conflicts with the host's expected ABI, which corrupts
# the C++ heap and crashes the Dart VM. See gfpa_dsp.cpp header for full notes.
#
# Required sources for a working VST3 host:
#   1. Interface IID definitions (coreiids, vstinitiids, commoniids, baseiids)
#   2. Hosting layer (plugprovider, hostclasses, module, eventlist, paramchanges)
#   3. Common utilities (pluginview, memorystream, stringconvert, updatehandler)
file(GLOB VST3_SDK_SOURCES
  ${VST3_SDK_DIR}/pluginterfaces/base/coreiids.cpp
  ${VST3_SDK_DIR}/pluginterfaces/base/funknown.cpp
  ${VST3_SDK_DIR}/pluginterfaces/base/ustring.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/vstinitiids.cpp
  ${VST3_SDK_DIR}/public.sdk/source/common/commoniids.cpp
  ${VST3_SDK_DIR}/public.sdk/source/common/pluginview.cpp
  ${VST3_SDK_DIR}/public.sdk/source/common/memorystream.cpp
  ${VST3_SDK_DIR}/public.sdk/source/common/commonstringconvert.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/hostclasses.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/pluginterfacesupport.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/module.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/eventlist.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/parameterchanges.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/plugprovider.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/connectionproxy.cpp
  ${VST3_SDK_DIR}/public.sdk/source/vst/utility/stringconvert.cpp
  ${VST3_SDK_DIR}/base/source/baseiids.cpp
  ${VST3_SDK_DIR}/base/source/fdebug.cpp
  ${VST3_SDK_DIR}/base/source/fobject.cpp
  ${VST3_SDK_DIR}/base/source/fstreamer.cpp
  ${VST3_SDK_DIR}/base/source/fstring.cpp
  ${VST3_SDK_DIR}/base/source/updatehandler.cpp
  ${VST3_SDK_DIR}/base/thread/source/flock.cpp
  ${VST3_SDK_DIR}/base/thread/source/fcondition.cpp
)


include_directories(
  ${VST3_SDK_DIR}
  ${VST3_SDK_DIR}/pluginterfaces
  ${VST3_SDK_DIR}/public.sdk/source
  ${VST3_SDK_DIR}/base/thread/include
  ${CMAKE_CURRENT_SOURCE_DIR}/include
)

# List source files. This library provides VST3 plugin hosting functionality.
# gfpa_dsp.cpp contains native DSP implementations for GFPA descriptor effects.
set(VstSources
  src/dart_vst_host.cpp
  src/gfpa_dsp.cpp
)

if(NOT APPLE AND NOT UNIX)
  list(APPEND VstSources src/dart_vst_host_platform_stubs.cpp)
endif()

add_library(dart_vst_host SHARED
  ${VstSources}
  ${VST3_SDK_SOURCES}
)

# Add platform-specific module files
if(APPLE)
  target_sources(dart_vst_host PRIVATE
    src/dart_vst_host_audio_mac.cpp
    src/dart_vst_host_editor_mac.mm
    ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/module_mac.mm
    ${VST3_SDK_DIR}/public.sdk/source/common/threadchecker_mac.mm
  )
elseif(UNIX)
  target_sources(dart_vst_host PRIVATE
    src/dart_vst_host_alsa.cpp
    src/dart_vst_host_editor_linux.cpp
    ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/module_linux.cpp
    ${VST3_SDK_DIR}/public.sdk/source/common/threadchecker_linux.cpp
  )
  find_package(ALSA REQUIRED)
  target_link_libraries(dart_vst_host ${ALSA_LIBRARIES})
  target_include_directories(dart_vst_host PRIVATE ${ALSA_INCLUDE_DIRS})
  # X11 for native plugin editor windows.
  find_package(X11 REQUIRED)
  target_link_libraries(dart_vst_host ${X11_LIBRARIES})
  target_include_directories(dart_vst_host PRIVATE ${X11_INCLUDE_DIR})
elseif(WIN32)
  target_sources(dart_vst_host PRIVATE
    ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/module_win32.cpp
    ${VST3_SDK_DIR}/public.sdk/source/common/threadchecker_win32.cpp
  )
endif()

target_compile_definitions(dart_vst_host PRIVATE 
  DART_VST_HOST_EXPORTS
  RELEASE=1
)

# -fno-common prevents multiple tentative definitions of interface IIDs
# from being silently merged by the linker into a single __DATA,__common
# symbol — which can cause dlopen to fail on macOS flat namespace.
target_compile_options(dart_vst_host PRIVATE -fno-common)

if(APPLE)
  find_library(COCOA_FRAMEWORK Cocoa)
  find_library(CARBON_FRAMEWORK Carbon)
  find_library(COREFOUNDATION_FRAMEWORK CoreFoundation)
  find_library(AUDIOTOOLBOX_FRAMEWORK AudioToolbox)
  target_link_libraries(dart_vst_host 
    ${COCOA_FRAMEWORK} 
    ${CARBON_FRAMEWORK}
    ${COREFOUNDATION_FRAMEWORK}
    ${AUDIOTOOLBOX_FRAMEWORK}
  )
  
  # Enable Objective-C++ for .mm files with ARC
  set_source_files_properties(
    src/dart_vst_host_editor_mac.mm
    ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/module_mac.mm
    ${VST3_SDK_DIR}/public.sdk/source/common/threadchecker_mac.mm
    PROPERTIES COMPILE_FLAGS "-x objective-c++ -fobjc-arc"
  )
endif()
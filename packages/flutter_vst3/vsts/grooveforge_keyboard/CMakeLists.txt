cmake_minimum_required(VERSION 3.20)
project(grooveforge_keyboard VERSION 1.0.0 LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 17)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

# ── VST3 SDK ──────────────────────────────────────────────────────────────
if(NOT DEFINED ENV{VST3_SDK_DIR})
    set(VST3_SDK_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../vst3sdk)
else()
    set(VST3_SDK_DIR $ENV{VST3_SDK_DIR})
endif()

if(NOT EXISTS ${VST3_SDK_DIR}/CMakeLists.txt)
    message(FATAL_ERROR "VST3 SDK not found at ${VST3_SDK_DIR}")
endif()

set(SMTG_RUN_VST_VALIDATOR           OFF CACHE BOOL "" FORCE)
set(SMTG_CREATE_MODULE_INFO          OFF CACHE BOOL "" FORCE)
set(SMTG_ADD_VST3_PLUGINS_SAMPLES    OFF CACHE BOOL "" FORCE)
set(SMTG_ADD_VST3_HOSTING_SAMPLES    OFF CACHE BOOL "" FORCE)
set(SMTG_ADD_VSTGUI                  OFF CACHE BOOL "" FORCE)
set(SMTG_CREATE_VST3_LINK            OFF CACHE BOOL "" FORCE)
set(SMTG_ENABLE_VST3_PLUGIN_EXAMPLES OFF CACHE BOOL "" FORCE)
set(SMTG_ENABLE_VST3_HOSTING_EXAMPLES OFF CACHE BOOL "" FORCE)

if(NOT TARGET sdk)
    set(CMAKE_MESSAGE_LOG_LEVEL WARNING)
    add_subdirectory(${VST3_SDK_DIR} ${CMAKE_CURRENT_BINARY_DIR}/vst3sdk EXCLUDE_FROM_ALL)
    set(CMAKE_MESSAGE_LOG_LEVEL STATUS)
endif()

# ── FluidSynth (built from source, static, synthesis-only) ────────────────
# We build FluidSynth ourselves instead of linking the system shared library.
# Reason: the system libfluidsynth pulls in audio-backend deps (SDL3, PortAudio,
# readline…) compiled against a newer glibc than the one in Flatpak DAW runtimes
# (Ardour, Reaper). By disabling ALL audio drivers we reduce FluidSynth's
# runtime dependencies to GLib2 only — which every Flatpak runtime provides.
include(FetchContent)

# All options must be set BEFORE FetchContent_MakeAvailable
set(enable-alsa         OFF CACHE BOOL "" FORCE)
set(enable-aufile       OFF CACHE BOOL "" FORCE)
set(enable-dbus         OFF CACHE BOOL "" FORCE)
set(enable-jack         OFF CACHE BOOL "" FORCE)
set(enable-ladspa       OFF CACHE BOOL "" FORCE)
set(enable-libinstpatch OFF CACHE BOOL "" FORCE)
set(enable-libsndfile   OFF CACHE BOOL "" FORCE)
set(enable-midishare    OFF CACHE BOOL "" FORCE)
set(enable-oboe         OFF CACHE BOOL "" FORCE)
set(enable-opensles     OFF CACHE BOOL "" FORCE)
set(enable-oss          OFF CACHE BOOL "" FORCE)
set(enable-pipewire     OFF CACHE BOOL "" FORCE)
set(enable-portaudio    OFF CACHE BOOL "" FORCE)
set(enable-pulseaudio   OFF CACHE BOOL "" FORCE)
set(enable-readline     OFF CACHE BOOL "" FORCE)
set(enable-sdl2         OFF CACHE BOOL "" FORCE)
set(enable-sdl3         OFF CACHE BOOL "" FORCE)
set(enable-waveout      OFF CACHE BOOL "" FORCE)
set(enable-winmidi      OFF CACHE BOOL "" FORCE)
set(enable-tests        OFF CACHE BOOL "" FORCE)
set(enable-benchmark    OFF CACHE BOOL "" FORCE)
# Static library — gets linked directly into the plugin .so, no extra .so to ship
set(BUILD_SHARED_LIBS   OFF CACHE BOOL "" FORCE)
# -fPIC is required: static code linked into a shared MODULE must be relocatable
set(CMAKE_POSITION_INDEPENDENT_CODE ON CACHE BOOL "" FORCE)

FetchContent_Declare(
    fluidsynth
    GIT_REPOSITORY https://github.com/FluidSynth/fluidsynth.git
    GIT_TAG        v2.4.0
    GIT_SHALLOW    TRUE
)
FetchContent_MakeAvailable(fluidsynth)

# GLib2 is FluidSynth's only remaining runtime dependency; it is present in all
# Flatpak runtimes (Ardour, Reaper) so we do NOT need to bundle it.
find_package(PkgConfig REQUIRED)
pkg_check_modules(GLIB REQUIRED glib-2.0)

# ── Plugin target ─────────────────────────────────────────────────────────
smtg_add_vst3plugin(grooveforge_keyboard src/factory.cpp)
smtg_target_configure_version_file(grooveforge_keyboard)

target_include_directories(grooveforge_keyboard PRIVATE
    include
    ${VST3_SDK_DIR}
    ${fluidsynth_SOURCE_DIR}/include
    ${fluidsynth_BINARY_DIR}/include   # generated fluidsynth/version.h
    ${GLIB_INCLUDE_DIRS}
)

target_link_libraries(grooveforge_keyboard PRIVATE
    sdk
    libfluidsynth          # static — built above via FetchContent
    ${GLIB_LINK_LIBRARIES}
)

smtg_target_set_bundle(grooveforge_keyboard
    BUNDLE_IDENTIFIER "com.grooveforge.keyboard"
    COMPANY_NAME      "GrooveForge"
)

# ── Bundle any remaining transitive .so deps (Flatpak compatibility) ───────
# With static FluidSynth the plugin's only dynamic dep is GLib2 (excluded by
# bundle_deps.sh). The script is still run as a safety net for unexpected deps.
set(BUNDLE_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/../../scripts/bundle_deps.sh")
find_program(PATCHELF_EXE patchelf)
find_program(BASH_EXE bash)

if(PATCHELF_EXE AND BASH_EXE AND EXISTS "${BUNDLE_SCRIPT}")
    add_custom_command(TARGET grooveforge_keyboard POST_BUILD
        COMMAND ${BASH_EXE} "${BUNDLE_SCRIPT}"
                "$<TARGET_FILE:grooveforge_keyboard>"
                "$<TARGET_FILE_DIR:grooveforge_keyboard>"
        COMMENT "Bundling .so dependencies for Flatpak DAW compatibility"
        VERBATIM
    )
else()
    message(WARNING "patchelf/bash/bundle_deps.sh not found — dependencies will not be bundled.")
endif()

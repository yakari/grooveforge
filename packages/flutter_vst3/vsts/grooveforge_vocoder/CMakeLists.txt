cmake_minimum_required(VERSION 3.20)
project(grooveforge_vocoder VERSION 1.0.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_C_STANDARD   99)

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

# ── vocoder_dsp (from the main app's native_audio/) ───────────────────────
set(NATIVE_AUDIO_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../../native_audio)

if(NOT EXISTS ${NATIVE_AUDIO_DIR}/vocoder_dsp.c)
    message(FATAL_ERROR "vocoder_dsp.c not found at ${NATIVE_AUDIO_DIR}")
endif()

# Build as a static lib so C and C++ compile separately (different standards)
add_library(vocoder_dsp STATIC ${NATIVE_AUDIO_DIR}/vocoder_dsp.c)
target_include_directories(vocoder_dsp PUBLIC ${NATIVE_AUDIO_DIR})
target_compile_options(vocoder_dsp PRIVATE
    -fvisibility=hidden
    # -ffast-math inlines sqrtf/sinf/cosf etc. as hardware instructions, avoiding
    # glibc versioned symbol references (e.g. sqrtf@@GLIBC_2.43) that would fail
    # to load in Flatpak DAW runtimes which have an older glibc. Safe for DSP code.
    -ffast-math
)

find_library(M_LIB m)
if(M_LIB)
    target_link_libraries(vocoder_dsp PRIVATE ${M_LIB})
endif()

# ── Plugin target ─────────────────────────────────────────────────────────
smtg_add_vst3plugin(grooveforge_vocoder src/factory.cpp)

smtg_target_configure_version_file(grooveforge_vocoder)

target_include_directories(grooveforge_vocoder PRIVATE
    include
    ${VST3_SDK_DIR}
    ${NATIVE_AUDIO_DIR}
)

target_link_libraries(grooveforge_vocoder PRIVATE
    sdk
    vocoder_dsp
)

smtg_target_set_bundle(grooveforge_vocoder
    BUNDLE_IDENTIFIER "com.grooveforge.vocoder"
    COMPANY_NAME      "GrooveForge"
)

# -fPIC required: static vocoder_dsp is linked into a shared MODULE
set_target_properties(vocoder_dsp PROPERTIES POSITION_INDEPENDENT_CODE ON)

# ── Bundle transitive .so deps and patch RPATH (Flatpak compatibility) ────
set(BUNDLE_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/../../scripts/bundle_deps.sh")
find_program(PATCHELF_EXE patchelf)
find_program(BASH_EXE bash)

if(PATCHELF_EXE AND BASH_EXE AND EXISTS "${BUNDLE_SCRIPT}")
    add_custom_command(TARGET grooveforge_vocoder POST_BUILD
        COMMAND ${BASH_EXE} "${BUNDLE_SCRIPT}"
                "$<TARGET_FILE:grooveforge_vocoder>"
                "$<TARGET_FILE_DIR:grooveforge_vocoder>"
        COMMENT "Bundling .so dependencies for Flatpak DAW compatibility"
        VERBATIM
    )
else()
    message(WARNING "patchelf/bash/bundle_deps.sh not found — dependencies will not be bundled.")
endif()

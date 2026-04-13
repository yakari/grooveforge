cmake_minimum_required(VERSION 3.10)
project(audio_input C)

set(CMAKE_C_STANDARD 99)

# Build a shared library that Dart can load via FFI.
# keyboard_synth.c is compiled on all platforms (with Linux-only implementation
# and no-op stubs on other platforms).
add_library(audio_input SHARED
    audio_input.c
    keyboard_synth.c
    gf_phase_vocoder.c
)

find_package(Threads REQUIRED)
target_link_libraries(audio_input PRIVATE Threads::Threads)

if (ANDROID)
    find_library(log-lib log)
    target_link_libraries(audio_input PRIVATE m ${log-lib})
elseif (APPLE)
    find_library(COREAUDIO_LIB CoreAudio)
    find_library(COREFOUNDATION_LIB CoreFoundation)
    find_library(AUDIOUNIT_LIB AudioUnit)
    # FluidSynth installed via Homebrew (arm64: /opt/homebrew, x86_64: /usr/local).
    find_library(FLUIDSYNTH_LIB fluidsynth HINTS /opt/homebrew/lib /usr/local/lib)
    find_path(FLUIDSYNTH_INCLUDE_DIR fluidsynth.h
              HINTS /opt/homebrew/include /usr/local/include)
    target_include_directories(audio_input PRIVATE ${FLUIDSYNTH_INCLUDE_DIR})
    target_link_libraries(audio_input PRIVATE
        ${COREAUDIO_LIB}
        ${COREFOUNDATION_LIB}
        ${AUDIOUNIT_LIB}
        ${FLUIDSYNTH_LIB}
        m
    )
elseif (UNIX AND NOT APPLE)
    find_library(M_LIB m)
    find_library(DL_LIB dl)
    # Link libfluidsynth for in-process GF Keyboard rendering (Linux only).
    find_library(FLUIDSYNTH_LIB fluidsynth)
    find_path(FLUIDSYNTH_INCLUDE_DIR fluidsynth.h)
    target_include_directories(audio_input PRIVATE ${FLUIDSYNTH_INCLUDE_DIR})
    target_link_libraries(audio_input PRIVATE ${M_LIB} ${DL_LIB} ${FLUIDSYNTH_LIB})
endif()

# Offline smoke test for the phase vocoder. Host-side only (not included
# in any platform build). Uses miniaudio's built-in WAV encoder.
if (NOT ANDROID AND NOT IOS)
    add_executable(gf_pv_smoke_test gf_pv_smoke_test.c gf_phase_vocoder.c)
    if (UNIX)
        target_link_libraries(gf_pv_smoke_test PRIVATE m ${CMAKE_DL_LIBS})
    endif()
endif()

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
    gf_harmony.c
    gf_pitch.c
    gf_latency.c
    gf_rehearsal.c
    gf_media_import.c
)

find_package(Threads REQUIRED)
target_link_libraries(audio_input PRIVATE Threads::Threads)

# ── Optimisation floor for the DSP ────────────────────────────────────────
# Flutter's debug configuration compiles native code with no -O flag at all,
# which for clang means -O0. That is fine for glue but not for the phase
# vocoder, which runs FFTs inside the audio callback and is several times
# slower unoptimised. Target options are appended after
# CMAKE_<LANG>_FLAGS_<CONFIG>, so this wins over the configuration's own
# setting without disturbing debug symbols.
if(MSVC)
    target_compile_options(audio_input PRIVATE /O2)
else()
    target_compile_options(audio_input PRIVATE -O2 -fno-math-errno)
endif()

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
elseif (WIN32)
    # FluidSynth prebuilt SDK (cpp11 variant — no GLib dependency).
    set(FLUIDSYNTH_WIN_DIR "${CMAKE_CURRENT_SOURCE_DIR}/fluidsynth_win64")
    find_library(FLUIDSYNTH_LIB libfluidsynth-3
                 HINTS "${FLUIDSYNTH_WIN_DIR}/lib")
    find_path(FLUIDSYNTH_INCLUDE_DIR fluidsynth.h
              HINTS "${FLUIDSYNTH_WIN_DIR}/include")
    if(FLUIDSYNTH_LIB AND FLUIDSYNTH_INCLUDE_DIR)
        target_include_directories(audio_input PRIVATE ${FLUIDSYNTH_INCLUDE_DIR})
        target_link_libraries(audio_input PRIVATE ${FLUIDSYNTH_LIB})
    else()
        message(FATAL_ERROR
          "FluidSynth not found at ${FLUIDSYNTH_WIN_DIR}.\n"
          "Run the setup script or download the cpp11 build from "
          "https://github.com/FluidSynth/fluidsynth/releases")
    endif()
    # miniaudio's WASAPI backend needs COM + multimedia libs.
    target_link_libraries(audio_input PRIVATE ole32 winmm ksuser avrt)
    target_compile_definitions(audio_input PRIVATE NOMINMAX)
endif()

# ── Offline smoke tests ───────────────────────────────────────────────────────
#
# Developer tools, not part of the app. EXCLUDE_FROM_ALL keeps them out of the
# default build, so `flutter build` on any platform ignores them entirely and
# only `scripts/run_smoke_tests.sh` — which builds them by name — pays for
# them. Without it they were compiled into every desktop release build, which
# cost CI time and meant a mistake in a test-only target could break a
# platform build.

# Phase vocoder time-stretching. Uses miniaudio's built-in WAV encoder.
if (NOT ANDROID AND NOT IOS)
    add_executable(gf_pv_smoke_test EXCLUDE_FROM_ALL
        gf_pv_smoke_test.c gf_phase_vocoder.c)
    if (UNIX)
        target_link_libraries(gf_pv_smoke_test PRIVATE m ${CMAKE_DL_LIBS})
    endif()
endif()

# Overdub latency alignment (P0 of the Rehearsals plan). Pure DSP, no audio
# device and no external library — it proves the measure/compensate maths on
# synthetic signals so a failure on real hardware can be blamed on the hardware.
if (NOT ANDROID AND NOT IOS)
    add_executable(gf_latency_smoke_test EXCLUDE_FROM_ALL
        gf_latency_smoke_test.c gf_latency.c)
    if (UNIX)
        target_link_libraries(gf_latency_smoke_test PRIVATE m)
    endif()
endif()

# Multitrack rehearsal engine (P1). Streams takes from disk, so the test needs
# a writable directory but no audio device.
if (NOT ANDROID AND NOT IOS)
    add_executable(gf_rehearsal_smoke_test EXCLUDE_FROM_ALL
        gf_rehearsal_smoke_test.c gf_rehearsal.c gf_media_import.c)
    target_link_libraries(gf_rehearsal_smoke_test PRIVATE Threads::Threads)
    if (UNIX)
        target_link_libraries(gf_rehearsal_smoke_test PRIVATE m)
    endif()
endif()

# The same measurement against real hardware. Needs an audio device, so it is a
# hand-run tool rather than part of the smoke suite.
if (NOT ANDROID AND NOT IOS)
    add_executable(gf_latency_probe EXCLUDE_FROM_ALL
        gf_latency_probe.c gf_latency.c)
    if (UNIX AND NOT APPLE)
        target_link_libraries(gf_latency_probe PRIVATE m ${CMAKE_DL_LIBS} pthread)
    elseif (APPLE)
        find_library(P_COREAUDIO CoreAudio)
        find_library(P_COREFOUNDATION CoreFoundation)
        find_library(P_AUDIOUNIT AudioUnit)
        target_link_libraries(gf_latency_probe PRIVATE
            ${P_COREAUDIO} ${P_COREFOUNDATION} ${P_AUDIOUNIT} m)
    elseif (WIN32)
        target_link_libraries(gf_latency_probe PRIVATE ole32 winmm ksuser avrt)
    endif()
endif()

# Audio Harmonizer. Links the real GFPA DSP (which lives in flutter_vst3) plus
# the phase vocoder, and checks the properties that only exist once audio has
# actually been rendered: headroom, block continuity, and gain flatness across
# intervals. C++ because gfpa_dsp is C++.
if (NOT ANDROID AND NOT IOS)
    set(GF_GFPA_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../packages/flutter_vst3/dart_vst_host/native)
    if (EXISTS "${GF_GFPA_DIR}/src/gfpa_dsp.cpp")
        # This project is declared C-only; the GFPA DSP it links is C++.
        # Enabling the language here rather than in project() keeps the
        # requirement on the one target that actually needs it.
        enable_language(CXX)
        add_executable(gf_harmonizer_smoke_test EXCLUDE_FROM_ALL
            gf_harmonizer_smoke_test.c
            ${GF_GFPA_DIR}/src/gfpa_dsp.cpp
            gf_phase_vocoder.c
            gf_harmony.c
            gf_pitch.c)
        set_target_properties(gf_harmonizer_smoke_test PROPERTIES LINKER_LANGUAGE CXX)
        target_include_directories(gf_harmonizer_smoke_test PRIVATE
            ${GF_GFPA_DIR}/include
            ${CMAKE_CURRENT_SOURCE_DIR})
        if (UNIX)
            target_link_libraries(gf_harmonizer_smoke_test PRIVATE m)
        endif()
    endif()
endif()

# Microtonal key tuning. Renders real FluidSynth output and measures the
# resulting pitch, so it needs the same FluidSynth the app links against —
# skipped when none was found.
if (NOT ANDROID AND NOT IOS AND FLUIDSYNTH_LIB)
    add_executable(gf_tuning_smoke_test EXCLUDE_FROM_ALL
        gf_tuning_smoke_test.c keyboard_synth.c)
    target_include_directories(gf_tuning_smoke_test PRIVATE ${FLUIDSYNTH_INCLUDE_DIR})
    target_link_libraries(gf_tuning_smoke_test PRIVATE ${FLUIDSYNTH_LIB})
    # libm is a separate library only on Unix; on MSVC the math functions live
    # in the CRT and asking for "m" makes the linker look for a nonexistent
    # m.lib.
    if (UNIX)
        target_link_libraries(gf_tuning_smoke_test PRIVATE m)
    endif()
endif()

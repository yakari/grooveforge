# GrooveForge Android native build.
#
# For more information about using CMake with Android Studio, read the
# documentation: https://d.android.com/studio/projects/add-native-code.html

cmake_minimum_required(VERSION 3.22.1)

# ── FluidSynth, built from source ─────────────────────────────────────────────
#
# This file used to link ~20 prebuilt .so files vendored under fluidsynth/lib/
# (90 MB across three ABIs). Those blobs are gone: F-Droid's inclusion policy
# rejects prebuilt binaries outright, and nearly all of them were dead weight
# anyway — Oboe was never called (we use raw AAudio), libsndfile only matters
# for SF3, libinstpatch only for DLS/GIG, and the whole glib stack was merely
# FluidSynth's internal OS abstraction.
#
# FluidSynth >= 2.5.0 can drop GLib entirely via `osal=cpp11`, which collapses
# glib/gio/gobject/gmodule/gthread/pcre into the C++11 standard library. What
# survives is a single libfluidsynth.so (~3.3 MB/ABI) whose only NEEDED entries
# are NDK libraries: libm, liblog, libc++_shared, libdl, libc.
#
# GrooveForge uses FluidSynth strictly as an SF2 sample-playback engine:
#   - no audio driver — fluid_synth_process() is driven from our own AAudio
#     callback in oboe_stream_android.cpp, so every driver below is off;
#   - no reverb/chorus — disabled in native-lib.cpp, we run our own insert
#     chain in gfpa_dsp.cpp so effects can also cover VST3 and the looper;
#   - no SF3/DLS — the soundfont picker accepts .sf2 only.
# Everything not on that list is switched off to keep the build minimal.

set(osal                "cpp11" CACHE STRING "" FORCE)  # no glib
set(BUILD_SHARED_LIBS   ON      CACHE BOOL   "" FORCE)

set(enable-libinstpatch OFF CACHE BOOL "" FORCE)  # DLS/GIG loader — unused
set(enable-libsndfile   OFF CACHE BOOL "" FORCE)  # SF3 + file rendering — unused
set(enable-openmp       OFF CACHE BOOL "" FORCE)  # drops libomp; cpp11 threads suffice

# Audio/MIDI drivers: all unused, we render the synth ourselves.
set(enable-oboe         OFF CACHE BOOL "" FORCE)
set(enable-opensles     OFF CACHE BOOL "" FORCE)
set(enable-alsa         OFF CACHE BOOL "" FORCE)
set(enable-jack         OFF CACHE BOOL "" FORCE)
set(enable-oss          OFF CACHE BOOL "" FORCE)
set(enable-pulseaudio   OFF CACHE BOOL "" FORCE)
set(enable-pipewire     OFF CACHE BOOL "" FORCE)
set(enable-sdl3         OFF CACHE BOOL "" FORCE)
set(enable-midishare    OFF CACHE BOOL "" FORCE)
set(enable-aufile       OFF CACHE BOOL "" FORCE)

# Desktop-only extras with no meaning on Android.
set(enable-dbus         OFF CACHE BOOL "" FORCE)
set(enable-ladspa       OFF CACHE BOOL "" FORCE)
set(enable-network      OFF CACHE BOOL "" FORCE)
set(enable-ipv6         OFF CACHE BOOL "" FORCE)
set(enable-readline     OFF CACHE BOOL "" FORCE)

# EXCLUDE_FROM_ALL: FluidSynth unconditionally declares a CLI executable plus
# test/ and doc/ subdirectories. Excluding them from the default target means
# only libfluidsynth gets built, as a dependency of native-lib below.
add_subdirectory(fluidsynth-src EXCLUDE_FROM_ALL)

# The Android Gradle Plugin packages shared libraries it finds in the ABI's
# output directory, so make sure libfluidsynth.so lands beside libnative-lib.so
# instead of staying in fluidsynth-src/src/.
set_target_properties(libfluidsynth PROPERTIES
        LIBRARY_OUTPUT_DIRECTORY "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}")

# Library that will be called directly from JAVA.
# gfpa_audio_android.cpp provides the FluidSynth audio callback and insert chain.
# gfpa_dsp.cpp contains the C++ DSP implementations (reverb, delay, wah, EQ,
# compressor, chorus) shared with the Linux/macOS ALSA path.
add_library(native-lib SHARED
        native-lib.cpp
        gfpa_audio_android.cpp
        oboe_stream_android.cpp
        ../../../../../flutter_vst3/dart_vst_host/native/src/gfpa_dsp.cpp
        ../../../../../flutter_vst3/dart_vst_host/native/src/audio_looper.cpp
        # Phase vocoder — tempo-sync stretching for the audio looper.
        # Source of truth at repo-root native_audio/.
        ../../../../../../native_audio/gf_phase_vocoder.c
)

# ── Optimisation floor for the DSP ────────────────────────────────────────
# Flutter's debug configuration compiles native code at -O0, which is fine
# for JNI glue but not for the signal path: the harmonizer runs several FFTs
# per audio callback and is roughly four times slower unoptimised. On a
# phone, where an AAudio burst is 96-240 frames (2-5 ms), that is the
# difference between the insert chain finishing inside the callback and
# missing every deadline — which the user hears as continuous crackling.
# Target options are appended after CMAKE_<LANG>_FLAGS_<CONFIG>, so this
# wins over the -O0 the debug configuration supplies.
target_compile_options(native-lib PRIVATE -O2 -fno-math-errno)

# Include directories:
#  - FluidSynth_SOURCE_DIR/include : public headers (fluidsynth.h, fluidsynth/*.h)
#  - FluidSynth_BINARY_DIR/include : generated version.h
#    (libfluidsynth keeps its include dirs PRIVATE, so they are not inherited
#     through target_link_libraries and must be named here)
#  - CMAKE_CURRENT_SOURCE_DIR : gfpa_audio_android.h (local header)
#  - flutter_vst3 native/include : gfpa_dsp.h and dart_vst_host.h
target_include_directories(native-lib PRIVATE
        ${FluidSynth_SOURCE_DIR}/include
        ${FluidSynth_BINARY_DIR}/include
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../flutter_vst3/dart_vst_host/native/include
        ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../../native_audio
)

# Link everything alltogether. Notice that native-lib should be the first element in the list.
target_link_libraries(
        native-lib
        libfluidsynth
        android
        aaudio
        log
)

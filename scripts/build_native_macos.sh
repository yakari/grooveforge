#!/bin/bash
# build_native_macos.sh
#
# Rebuilds the two native shared libraries required by GrooveForge on macOS:
#   - libaudio_input.dylib   (CoreAudio synthesis: keyboard, theremin, vocoder, stylophone)
#   - libdart_vst_host.dylib (VST3 plugin host + GFPA effects routing)
#
# Invoked automatically as an Xcode pre-build script phase so the libs are
# always in sync with the C/C++ sources when running `flutter run`.
#
# Environment variables set by Xcode:
#   PROJECT_DIR — path to the macos/ directory containing Runner.xcodeproj
#
# Usage (manual):
#   PROJECT_DIR=/path/to/grooveforge/macos ./scripts/build_native_macos.sh

set -euo pipefail

# ── CI guard ──────────────────────────────────────────────────────────────────
# On GitHub Actions (CI=true) the dylibs are built by an explicit cmake step
# before this Xcode build phase runs.  Rebuilding here would:
#   1. Waste several minutes of build time, and
#   2. Overwrite the dylibbundler-patched, self-contained dylib with a raw
#      Homebrew-linked one — breaking the app bundle.
# Skip the rebuild and let the pre-built libs remain in macos/Runner/.
if [ "${CI:-false}" = "true" ]; then
    echo "CI environment detected — native libs pre-built by workflow; skipping."
    exit 0
fi

# ── PATH setup ────────────────────────────────────────────────────────────────
# Xcode build-phase scripts run with a minimal PATH (/usr/bin:/bin only).
# Add standard Homebrew locations so cmake and ninja are discoverable.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Resolve the Flutter project root from Xcode's PROJECT_DIR (which is macos/).
PROJECT_ROOT="${PROJECT_DIR}/.."
NCPU="$(sysctl -n hw.ncpu)"

# Destination where the app bundle picks up the dylibs at runtime.
RUNNER_DIR="${PROJECT_DIR}/Runner"

# ── libaudio_input.dylib ─────────────────────────────────────────────────────
# CoreAudio synthesis engine: keyboard (FluidSynth), theremin, vocoder, stylophone.
echo "▶ Building libaudio_input.dylib..."

BUILD_AUDIO="${PROJECT_ROOT}/native_audio/build_mac"

# Always re-run configure: CMakeCache.txt embeds absolute paths, so a stale
# cache from a different checkout (or committed build dir) would cause CMake
# to reject the source tree with a path mismatch error.
rm -f "${BUILD_AUDIO}/CMakeCache.txt"
cmake -S "${PROJECT_ROOT}/native_audio" \
      -B "${BUILD_AUDIO}" \
      -DCMAKE_BUILD_TYPE=Release \
      -Wno-dev

cmake --build "${BUILD_AUDIO}" --parallel "${NCPU}"

# Copy to Runner bundle and project root (used by `dart test`).
cp "${BUILD_AUDIO}/libaudio_input.dylib" "${RUNNER_DIR}/libaudio_input.dylib"
cp "${BUILD_AUDIO}/libaudio_input.dylib" "${PROJECT_ROOT}/libaudio_input.dylib"

echo "✅ libaudio_input.dylib ready"

# ── libdart_vst_host.dylib ───────────────────────────────────────────────────
# VST3 plugin host + GFPA effects (reverb, delay, EQ, compressor, chorus, wah).
echo "▶ Building libdart_vst_host.dylib..."

VST3_SDK_DIR="${PROJECT_ROOT}/packages/flutter_vst3/vst3sdk"

if [ ! -d "${VST3_SDK_DIR}" ]; then
    echo "⚠️  VST3 SDK not found at ${VST3_SDK_DIR}"
    echo "   Run packages/flutter_vst3/setup.sh first, or set VST3_SDK_DIR manually."
    echo "   Skipping libdart_vst_host.dylib build."
    exit 0
fi

BUILD_VST="${PROJECT_ROOT}/packages/flutter_vst3/dart_vst_host/native/build"

# Always re-run configure for the same reason as libaudio_input above.
rm -f "${BUILD_VST}/CMakeCache.txt"
VST3_SDK_DIR="${VST3_SDK_DIR}" \
cmake -S "${PROJECT_ROOT}/packages/flutter_vst3/dart_vst_host/native" \
      -B "${BUILD_VST}" \
      -DCMAKE_BUILD_TYPE=Release \
      -Wno-dev

VST3_SDK_DIR="${VST3_SDK_DIR}" cmake --build "${BUILD_VST}" --parallel "${NCPU}"

# Copy to all locations that consume the library.
cp "${BUILD_VST}/libdart_vst_host.dylib" "${RUNNER_DIR}/libdart_vst_host.dylib"
cp "${BUILD_VST}/libdart_vst_host.dylib" "${PROJECT_ROOT}/libdart_vst_host.dylib"
cp "${BUILD_VST}/libdart_vst_host.dylib" \
   "${PROJECT_ROOT}/packages/flutter_vst3/dart_vst_host/libdart_vst_host.dylib"

echo "✅ libdart_vst_host.dylib ready"

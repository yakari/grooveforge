#!/bin/bash
# run_smoke_tests.sh
#
# Builds and runs GrooveForge's offline native smoke tests — the checks that
# need real audio rendered by the real libraries, and so cannot live in the
# Dart test suite.
#
# These are deliberately NOT part of CI (yet): they link against whatever
# FluidSynth the host has installed, so a failure here can mean "the code
# broke" or "this machine's FluidSynth differs from the one we ship". Run them
# by hand after touching anything in native_audio/, and read the output rather
# than just the exit code.
#
#   gf_tuning_smoke_test — microtonal key tuning (MIDI Tuning Standard).
#       Renders notes through FluidSynth and measures the pitch that comes
#       back: a −50 cent table must shift a key by exactly a quarter-tone, and
#       a maqam Rast table on one channel must flatten a held chord's third
#       while leaving its root and fifth alone. Guards the whole Xen module —
#       a FluidSynth built without tuning support would silently play every
#       microtonal scale as equal temperament, with no error anywhere.
#
#   gf_pv_smoke_test — phase vocoder time-stretching. Writes WAV files to the
#       output directory so the result can also be auditioned.
#
#   gf_harmonizer_smoke_test — Audio Harmonizer headroom, block continuity and
#       gain flatness across intervals. Every one of these has shipped broken
#       at least once, and none of them is visible from the Dart suite: they
#       only exist once real audio has been rendered. Needs no soundfont.
#
# Usage:
#   ./scripts/run_smoke_tests.sh            # run everything
#   ./scripts/run_smoke_tests.sh tuning     # just the tuning test
#   ./scripts/run_smoke_tests.sh vocoder    # just the phase vocoder test
#   ./scripts/run_smoke_tests.sh harmonizer # just the harmonizer test
#
# Build artefacts go to native_audio/build-smoke/ so the normal build tree is
# left untouched.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NATIVE_DIR="$REPO_ROOT/native_audio"
BUILD_DIR="$NATIVE_DIR/build-smoke"
SOUNDFONT="$REPO_ROOT/assets/soundfonts/default.sf2"

WHICH="${1:-all}"

# ── Configure ─────────────────────────────────────────────────────────────────

echo "── Configuring $BUILD_DIR"
cmake -S "$NATIVE_DIR" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release > /dev/null

# ── Tuning ────────────────────────────────────────────────────────────────────

run_tuning() {
    if [ ! -f "$SOUNDFONT" ]; then
        echo "SKIP gf_tuning_smoke_test — no soundfont at $SOUNDFONT" >&2
        return 0
    fi
    echo
    echo "── Building gf_tuning_smoke_test"
    # The CMake target only exists when FluidSynth was found. Its absence is a
    # real finding (the app could not be built either), not something to hide.
    if ! cmake --build "$BUILD_DIR" --target gf_tuning_smoke_test -j"$(nproc 2>/dev/null || echo 4)" > /dev/null 2>&1; then
        echo "FAIL: gf_tuning_smoke_test did not build — is FluidSynth installed?" >&2
        return 1
    fi
    echo "── Running gf_tuning_smoke_test"
    # FluidSynth writes ALSA probing noise to stderr on headless machines;
    # it is unrelated to the test, which renders offline.
    "$BUILD_DIR/gf_tuning_smoke_test" "$SOUNDFONT" 2>/dev/null
}

# ── Phase vocoder ─────────────────────────────────────────────────────────────

run_vocoder() {
    echo
    echo "── Building gf_pv_smoke_test"
    cmake --build "$BUILD_DIR" --target gf_pv_smoke_test -j"$(nproc 2>/dev/null || echo 4)" > /dev/null
    echo "── Running gf_pv_smoke_test (WAVs → $BUILD_DIR)"
    "$BUILD_DIR/gf_pv_smoke_test" "$BUILD_DIR"
}

# ── Harmonizer ────────────────────────────────────────────────────────────────

run_harmonizer() {
    echo
    echo "── Building gf_harmonizer_smoke_test"
    cmake --build "$BUILD_DIR" --target gf_harmonizer_smoke_test -j"$(nproc 2>/dev/null || echo 4)" > /dev/null
    echo "── Running gf_harmonizer_smoke_test"
    "$BUILD_DIR/gf_harmonizer_smoke_test"
}

# ── Dispatch ──────────────────────────────────────────────────────────────────

FAILED=0
case "$WHICH" in
    tuning)     run_tuning     || FAILED=1 ;;
    vocoder)    run_vocoder    || FAILED=1 ;;
    harmonizer) run_harmonizer || FAILED=1 ;;
    all)
        run_tuning     || FAILED=1
        run_vocoder    || FAILED=1
        run_harmonizer || FAILED=1
        ;;
    *)
        echo "usage: $0 [all|tuning|vocoder|harmonizer]" >&2
        exit 2
        ;;
esac

echo
if [ "$FAILED" -eq 0 ]; then
    echo "✓ smoke tests passed"
else
    echo "✗ smoke tests FAILED"
fi
exit "$FAILED"

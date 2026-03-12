#!/usr/bin/env bash
# bundle_deps.sh — Recursively bundle all shared library dependencies of a VST3 plugin
# into its bundle directory, then patch all their RPATHs to $ORIGIN.
#
# Usage: bundle_deps.sh <plugin.so> <bundle_lib_dir>
#
# The script excludes low-level system libraries that are always present
# on any modern Linux (glibc, libstdc++, libgcc, ld-linux, etc.) and
# libraries that are guaranteed to be in the Ardour/Reaper Flatpak runtime
# (JACK, ALSA, PipeWire, PulseAudio, GLib2, X11/XCB).

set -euo pipefail

PLUGIN_SO="$1"
OUT_DIR="$2"

if [[ -z "$PLUGIN_SO" || -z "$OUT_DIR" ]]; then
    echo "Usage: $0 <plugin.so> <bundle_lib_dir>" >&2
    exit 1
fi

if ! command -v patchelf &>/dev/null; then
    echo "ERROR: patchelf not found. Install it: sudo pacman -S patchelf" >&2
    exit 1
fi

# ── Libraries to EXCLUDE (present in every Linux userspace or Flatpak runtime) ──
# glibc family: always present
# libstdc++, libgcc_s: always present
# JACK, ALSA, PipeWire, PulseAudio: Ardour Flatpak runtime includes these
# GLib2, libdbus: Flatpak runtime
# X11/XCB: Flatpak runtime
EXCLUDE_PATTERN='(
    linux-vdso|ld-linux|
    libc\.so|libm\.so|libdl\.so|libpthread|librt\.so|libresolv\.so|libutil\.so|
    libgcc_s|libstdc\+\+|
    libjack|libasound|libpipewire|libpulse|
    libglib|libgmodule|libgobject|libgio|libgthread|
    libdbus|
    libX11|libXcb|libxcb|libXau|libXdmcp|libXext|libXfixes|libXrender|
    libwayland|libdrm|libGL|libEGL|libvulkan|
    libsystemd|libcap
)'
# Collapse to a single regex (remove newlines/spaces)
EXCLUDE_RE=$(echo "$EXCLUDE_PATTERN" | tr -d ' \n')

mkdir -p "$OUT_DIR"

declare -A VISITED

bundle_recursive() {
    local lib="$1"
    local deps
    deps=$(ldd "$lib" 2>/dev/null | grep "=> /" | awk '{print $3}') || return 0

    while IFS= read -r dep; do
        [[ -z "$dep" ]] && continue
        local base
        base=$(basename "$dep")

        # Skip excluded system/runtime libraries
        if echo "$base" | grep -qE "$EXCLUDE_RE"; then
            continue
        fi

        # Skip already processed
        if [[ -n "${VISITED[$base]+set}" ]]; then
            continue
        fi
        VISITED[$base]=1

        local dest="$OUT_DIR/$base"
        if [[ ! -f "$dest" ]]; then
            echo "  + Bundling $base"
            cp "$dep" "$dest"
            chmod 755 "$dest"
        else
            echo "  ~ Already present: $base"
        fi
        # Always patch RPATH — even pre-existing files may have a system RPATH
        patchelf --set-rpath '$ORIGIN' "$dest"
        # Recurse into this library's own dependencies
        bundle_recursive "$dest"
    done <<< "$deps"
}

echo "Bundling dependencies for: $(basename "$PLUGIN_SO")"
echo "Output directory: $OUT_DIR"

bundle_recursive "$PLUGIN_SO"

echo "Patching RPATH of plugin itself..."
patchelf --set-rpath '$ORIGIN' "$PLUGIN_SO"

# ── FluidSynth: strip optional audio-backend DT_NEEDED entries ────────────
# Inside a VST3 plugin the host owns the audio pipeline; FluidSynth's own
# audio drivers (SDL3, PortAudio, readline) are never initialised and must
# not be hard-linked — they can require newer glibc than the Flatpak runtime.
FLUID_IN_BUNDLE="$OUT_DIR/libfluidsynth.so.3"
if [[ -f "$FLUID_IN_BUNDLE" ]]; then
    echo "Stripping unused FluidSynth audio-backend deps (not needed in VST3 context)..."
    for dep in libSDL3.so.0 libSDL2.so.0 libportaudio.so.2 libreadline.so.8 libncursesw.so.6 libdb-5.3.so libtinfo.so.6; do
        if patchelf --print-needed "$FLUID_IN_BUNDLE" 2>/dev/null | grep -qF "$dep"; then
            echo "  - Removing DT_NEEDED: $dep"
            patchelf --remove-needed "$dep" "$FLUID_IN_BUNDLE"
            rm -f "$OUT_DIR/$dep"
        fi
    done
fi

echo "Done. Bundle contents:"
ls -lh "$OUT_DIR"
